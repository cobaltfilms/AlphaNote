import Foundation

/// Nature d'une alerte. Une alerte peut en combiner plusieurs.
enum ReminderKind: String, CaseIterable {
    case notification
    case sonnerie
    case vibration

    static func parse(_ raw: String) -> ReminderKind? {
        ReminderKind(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }
}

/// Un rappel : une date et heure locales, et les natures d'alerte à cette heure.
struct Reminder: Equatable {
    let at: Date
    let kinds: Set<ReminderKind>
}

/// Rappels stockés dans le texte de la note, une ligne chacun :
///
///     rappel 2026-11-10 18:00 : notification, sonnerie, vibration
///
/// Même format que la version Android (`domain/Reminders.kt`) : le texte se
/// synchronise tel quel, chaque appareil reprogramme ses propres alertes.
enum Reminders {
    static let stampFormat = "yyyy-MM-dd HH:mm"

    private static let line = try! NSRegularExpression(
        pattern: #"^\s*rappel\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\s*:\s*(.+?)\s*$"#,
        options: [.caseInsensitive]
    )

    /// Rappels de la note, dans l'ordre du texte. Une ligne mal formée est ignorée.
    static func parse(_ content: String) -> [Reminder] {
        content.components(separatedBy: "\n").compactMap { raw in
            let range = NSRange(raw.startIndex..., in: raw)
            guard let match = line.firstMatch(in: raw, range: range),
                  let stampRange = Range(match.range(at: 1), in: raw),
                  let kindsRange = Range(match.range(at: 2), in: raw),
                  let at = formatter().date(from: String(raw[stampRange]))
            else { return nil }
            let kinds = Set(raw[kindsRange].split(separator: ",").compactMap { ReminderKind.parse(String($0)) })
            return kinds.isEmpty ? nil : Reminder(at: at, kinds: kinds)
        }
    }

    /// La ligne de rappel. Les natures sont écrites dans l'ordre de `ReminderKind`.
    static func line(at: Date, kinds: Set<ReminderKind>) -> String {
        let names = ReminderKind.allCases.filter { kinds.contains($0) }.map(\.rawValue).joined(separator: ", ")
        return "rappel \(formatter().string(from: at)) : \(names)"
    }

    /// Ajoute un rappel en fin de texte, sur sa propre ligne.
    static func withReminder(_ content: String, at: Date, kinds: Set<ReminderKind>) -> String {
        let separator = content.isEmpty || content.hasSuffix("\n") ? "" : "\n"
        return content + separator + line(at: at, kinds: kinds)
    }

    /// Formatteur strict, heure locale : « 2026-11-10 18:00 » ↔ Date.
    static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = stampFormat
        formatter.isLenient = false
        return formatter
    }
}
