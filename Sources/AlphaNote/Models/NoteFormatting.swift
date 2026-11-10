import Foundation

/// Présentation d'une note dans les listes (titre, aperçu, date courte),
/// partagée par la liste macOS et la liste iOS.
enum NoteFormatting {
    static func displayTitle(_ note: Note) -> String {
        let title = note.effectiveTitle
        if title.isEmpty { return "Note sans titre" }
        // En-tête de mode nu (« timer », « math ») : un nom lisible plutôt
        // que le mot-clé.
        if note.title.isEmpty, let name = modeName[title.lowercased()] { return name }
        return title
    }

    private static let modeName = [
        "math": "Calcul", "list": "Liste", "code": "Code", "timer": "Minuteur", "vault": "Note sécurisée",
    ]

    /// Aperçu sur une ligne : sans l'en-tête de mode, sans la ligne de titre,
    /// sans les lignes d'images.
    static func preview(for note: Note) -> String {
        if note.isVault { return "Note sécurisée" }
        var lines = note.content.components(separatedBy: .newlines)
        if let first = lines.first, EditorTextRules.isModeHeader(first.trimmingCharacters(in: .whitespaces)) {
            lines.removeFirst()
        }
        if note.title.isEmpty, !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces) == note.effectiveTitle {
            lines.removeFirst()
        }
        lines.removeAll { NoteAttachments.isImageLine($0) || NoteThemes.isThemeLine($0) }
        let text = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Vide" : text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func shortDate(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            return "hier"
        } else if let weekAgo = calendar.date(byAdding: .day, value: -6, to: now), date > weekAgo {
            formatter.dateFormat = "EEE"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "d MMM"
        } else {
            formatter.dateFormat = "MMM yyyy"
        }
        return formatter.string(from: date)
    }
}
