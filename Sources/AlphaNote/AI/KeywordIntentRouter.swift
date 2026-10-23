import Foundation

/// Routage de secours par mots-clés, purement déterministe.
/// Utilisé quand le serveur de décision JEV est hors-ligne ou désactivé.
/// Il ne fait que classer — jamais il ne rédige.
enum KeywordIntentRouter {
    enum TimerType: String, Sendable {
        case countdown
        case stopwatch
        case pomodoro
    }

    static func classify(_ question: String, noteKeyword: String?) -> NoteMode {
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
            "pomodoro", "countdown", "stopwatch"
        ]
        if markers.contains(where: { query.contains($0) }) {
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
        if query.contains("pomodoro") {
            type = .pomodoro
        } else if query.contains("stopwatch") || query.contains("chrono") {
            type = .stopwatch
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

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
