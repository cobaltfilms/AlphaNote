import Foundation

/// Routage de secours par mots-clés, purement déterministe.
/// Utilisé quand le serveur de décision JEV est hors-ligne ou désactivé.
/// Il ne fait que classer — jamais il ne rédige.
enum KeywordIntentRouter {
    enum TimerType: String, Sendable {
        case countdown
        case stopwatch
        /// Sonne à une heure donnée ; `totalSeconds` = secondes depuis minuit.
        case alarm
    }

    static func classify(_ question: String, noteKeyword: String?) -> NoteMode {
        // Un lien = une recette à lire en liste ; à tester avant les maths,
        // qu'une URL (chiffres, « / », « - ») déclencherait.
        if !URLDetector.extractURLs(from: question).isEmpty {
            return .list
        }
        if isTimerRequest(question, noteKeyword: noteKeyword) {
            return .timer
        }
        if isMathRequest(question, noteKeyword: noteKeyword) {
            return .math
        }
        if isListRequest(question, noteKeyword: noteKeyword) {
            return .list
        }
        return .plain
    }

    static func isMathRequest(_ question: String, noteKeyword: String?) -> Bool {
        if (noteKeyword ?? "").lowercased() == "math" {
            return true
        }

        let query = normalized(question)
        let markers = [
            "math",
            "calcule", "calcul", "combien",
            "pourcentage", "reduction", "réduction",
            "equation", "équation",
            "convertis", "conversion"
        ]
        if markers.contains(where: { query.contains($0) }) {
            return true
        }

        if query.range(of: #"\d+\s*[\+\-\*\/\^]\s*\d+"#, options: .regularExpression) != nil {
            return true
        }

        if query.range(of: #"\d+\s*[a-zA-Z°"'\u00B2\u00B3]+\s*(?:to|in|en)\s*[a-zA-Z°"'\u00B2\u00B3]+"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    static func isListRequest(_ question: String, noteKeyword: String?) -> Bool {
        if (noteKeyword ?? "").lowercased() == "list" {
            return true
        }

        let query = normalized(question)
        let markers = [
            "todo", "to-do", "checklist", "liste", "courses",
            "ingredients", "ingrédients", "taches", "tâches"
        ]
        if markers.contains(where: { query.contains($0) }) {
            return true
        }

        let commaParts = question
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if commaParts.count >= 3 {
            return true
        }

        return false
    }

    static func isTimerRequest(_ question: String, noteKeyword: String?) -> Bool {
        if (noteKeyword ?? "").lowercased() == "timer" {
            return true
        }

        let query = normalized(question)
        let markers = [
            "timer", "minuteur", "chrono",
            "countdown", "stopwatch",
            "alarme", "alarm", "reveil"
        ]
        if markers.contains(where: { query.contains($0) }) {
            return true
        }
        // « à 7h30 », « vers 14:15 » : une heure, donc une alarme.
        if query.range(of: #"\b(a|vers|pour)\s+\d{1,2}\s*(h|:)\s*\d{0,2}\b"#, options: .regularExpression) != nil {
            return true
        }

        let timePatterns = [
            #"\d+\s*(min|minute|mn)\b"#,
            #"\d+\s*(sec|secondes?)\b"#,
            #"\d+\s*(h|heure|hour)s?\b"#
        ]
        for pattern in timePatterns where query.range(of: pattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    static func parseTimerRequest(_ question: String) -> (type: TimerType, totalSeconds: Int)? {
        let query = normalized(question)

        let type: TimerType
        if query.contains("stopwatch") || query.contains("chrono") {
            type = .stopwatch
        } else if isAlarmRequest(query) {
            return (.alarm, alarmTime(in: query) ?? 7 * 3600)
        } else {
            type = .countdown
        }

        var totalSeconds = 0

        let patterns: [(pattern: String, unit: String)] = [
            (#"(\d+)\s*(?:h|heure|hour)s?"#, "hour"),
            (#"(\d+)\s*(?:min|minute|mn)s?"#, "min"),
            (#"(\d+)\s*(?:sec|secondes?)s?"#, "sec"),
            (#"(\d+)s"#, "sec")
        ]

        for (pattern, unit) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(query.startIndex..., in: query)
            guard let match = regex.firstMatch(in: query, options: [], range: range),
                  let numberRange = Range(match.range(at: 1), in: query) else { continue }
            let digits = Int(query[numberRange]) ?? 0
            guard digits > 0 else { continue }
            switch unit {
            case "hour": totalSeconds += digits * 3600
            case "min": totalSeconds += digits * 60
            case "sec": totalSeconds = max(totalSeconds, digits)
            default: break
            }
        }

        if totalSeconds == 0 {
            totalSeconds = 10 * 60
        }

        return (type, totalSeconds)
    }

    /// Une heure de la journée plutôt qu'une durée : « réveille-moi à 7h »,
    /// « alarme 6:45 », « sonne à 18h ». « alarme dans 10 minutes » reste un
    /// minuteur, comme « minuteur pour 2h ».
    private static func isAlarmRequest(_ query: String) -> Bool {
        if query.contains("dans ") || query.contains("pendant ") { return false }
        if ["alarme", "alarm", "reveil"].contains(where: { query.contains($0) }) { return true }
        let durationWords = ["minuteur", "timer", "countdown", "compte a rebours", "decompte", "minuterie"]
        if durationWords.contains(where: { query.contains($0) }) { return false }
        return query.range(of: #"\b(a|vers|pour)\s+(\d{1,2}\s*(h|:)|midi\b|minuit\b)"#, options: .regularExpression) != nil
    }

    /// Heure lue dans la demande, en secondes depuis minuit.
    static func alarmTime(in question: String) -> Int? {
        let query = normalized(question)
        if query.range(of: #"\bmidi\b"#, options: .regularExpression) != nil { return 12 * 3600 }
        if query.range(of: #"\bminuit\b"#, options: .regularExpression) != nil { return 0 }
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*(?:h|:|heures?)\s*(\d{1,2})?"#),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let hourRange = Range(match.range(at: 1), in: query),
              var hours = Int(query[hourRange]) else { return nil }
        let minutes = Range(match.range(at: 2), in: query).flatMap { Int(query[$0]) } ?? 0
        guard hours < 24, minutes < 60 else { return nil }
        let evening = query.range(of: #"\bdu soir\b|apres-midi|\d\s*pm\b|\bpm\b"#, options: .regularExpression) != nil
        if evening, hours < 12 { hours += 12 }
        return hours * 3600 + minutes * 60
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
