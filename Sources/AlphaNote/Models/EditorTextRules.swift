import Foundation

/// Règles de texte de l'éditeur unique, sans AppKit ni UIKit : en-tête de mode,
/// éléments cochés, bascule d'une case, puces. Partagées par l'éditeur macOS et
/// l'éditeur iOS pour qu'ils se comportent pareil (Android : NoteEditor.kt).
enum EditorTextRules {
    static func detectMode(in content: String) -> NoteMode {
        var probe = Note(content: content)
        probe.detectKeyword()
        return NoteMode(rawValue: probe.keyword) ?? .plain
    }

    static func isModeHeader(_ trimmed: String) -> Bool {
        let lower = trimmed.lowercased()
        return Note.knownKeywords.contains(lower)
            || Note.knownKeywords.contains(where: { lower.hasPrefix("\($0):") })
    }

    static func isChecked(_ trimmed: String, trigger: String) -> Bool {
        trimmed.range(of: trigger, options: [.caseInsensitive, .anchored, .backwards]) != nil
    }

    /// Ligne de liste après un clic sur sa case : ajoute ou retire le déclencheur.
    static func toggledListLine(_ line: String, trigger rawTrigger: String) -> String {
        let trigger = rawTrigger.isEmpty ? "/x" : rawTrigger
        let trimmedTrailing = line.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        if isChecked(trimmedTrailing.trimmingCharacters(in: .whitespaces), trigger: trigger),
           let range = trimmedTrailing.range(of: trigger, options: [.caseInsensitive, .backwards]) {
            return String(trimmedTrailing[..<range.lowerBound])
                .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        }
        return trimmedTrailing.isEmpty ? trigger : "\(trimmedTrailing) \(trigger)"
    }

    /// Puce en tête de ligne (« - », « * », « • » suivis d'une espace), s'il y en a une.
    static func bulletMarker(in line: String) -> String? {
        guard let marker = line.range(of: #"^\s*[-*•]\s"#, options: .regularExpression) else { return nil }
        return String(line[marker])
    }

    /// Vrai si la ligne n'est qu'une puce vide (Entrée la retire au lieu d'en ajouter une).
    static func isEmptyBullet(_ line: String) -> Bool {
        guard let marker = bulletMarker(in: line) else { return false }
        return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).isEmpty
    }

    static let numberRegex = try! NSRegularExpression(pattern: "(?<![\\p{L}_])[-+]?\\d+(?:[.,]\\d+)?")
    static let unitRegex = try! NSRegularExpression(pattern: "(?i)\\b(usd|eur|gbp|jpy|chf|cad|kg|g|mg|lb|oz|km|m|cm|mm|mi|yd|ft|in|sqm|sqft|ha|acre|l|ml|gal|qt|pt|cup|°c|°f|k|min|h|s)\\b")

    static func variableRegex(_ name: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])", options: [.caseInsensitive])
    }
}
