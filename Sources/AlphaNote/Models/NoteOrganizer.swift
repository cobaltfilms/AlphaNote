import Foundation

/// Façons de ranger la liste des notes. Même liste et mêmes règles sur
/// Android (`domain/NoteOrganizer.kt`).
enum NoteGrouping: String, CaseIterable, Sendable {
    /// Ordre habituel : épinglées, puis de la plus récente à la plus ancienne.
    case recent
    /// Par rayon : thème écrit dans la note, sinon proposé (`ThemeSorter`).
    case theme
    /// Par forme : ce qu'est la note (commandes, liste, lien…), pas son sujet.
    case shape
    /// Par mois de création.
    case month
    /// Tri à faire : ce qui est probablement à archiver ou à supprimer.
    case triage

    static let storageKey = "noteGrouping"

    var title: String {
        switch self {
        case .recent: return "Par date"
        case .theme: return "Par rayon"
        case .shape: return "Par forme"
        case .month: return "Par mois de création"
        case .triage: return "Tri à faire"
        }
    }

    var symbol: String {
        switch self {
        case .recent: return "clock"
        case .theme: return "tag"
        case .shape: return "square.grid.2x2"
        case .month: return "calendar"
        case .triage: return "tray.full"
        }
    }
}

/// Forme d'une note, lue dans son texte : aucun réseau, aucune IA.
enum NoteShape: String, CaseIterable, Sendable {
    case terminal, list, link, oneLine, longText, shortText, math, timer, vault

    var title: String {
        switch self {
        case .terminal: return "Commandes et code"
        case .list: return "Listes"
        case .link: return "Liens"
        case .oneLine: return "Une seule ligne"
        case .longText: return "Textes longs"
        case .shortText: return "Textes courts"
        case .math: return "Calculs"
        case .timer: return "Minuteurs"
        case .vault: return "Notes sécurisées"
        }
    }
}

/// Pourquoi une note figure dans le « tri à faire ».
enum TriageReason: String, CaseIterable, Sendable {
    case duplicate, timer, link, oneLine

    var title: String {
        switch self {
        case .duplicate: return "Doublons probables"
        case .timer: return "Minuteurs"
        case .link: return "Liens seuls"
        case .oneLine: return "Une seule ligne"
        }
    }
}

enum NoteOrganizer {
    struct Section: Equatable {
        let title: String
        let noteUUIDs: [String]
    }

    static let longTextLength = 1500
    static let linkMaxLength = 300
    static let oneLineMaxLength = 80
    /// Section du tri qui rassemble tout ce qui n'appelle aucun tri.
    static let keepTitle = "Le reste"

    private static let url = try! NSRegularExpression(pattern: #"https?://\S+"#, options: [.caseInsensitive])

    /// Lignes utiles : sans en-tête de mode, thème, rappels, pièces jointes ni lignes vides.
    static func meaningfulLines(_ note: Note) -> [String] {
        var lines = note.content.components(separatedBy: "\n")
        if let first = lines.first, EditorTextRules.isModeHeader(first.trimmingCharacters(in: .whitespaces)) {
            lines.removeFirst()
        }
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !NoteThemes.isThemeLine(line) && !NoteAttachments.isImageLine(line)
                && !trimmed.lowercased().hasPrefix("rappel ")
        }
    }

    /// Forme de la note. Mise en cache par note et par date de modification :
    /// la liste est redessinée à chaque frappe.
    static func shape(of note: Note) -> NoteShape {
        shapes.value(for: note) { computeShape(of: note) }
    }

    private static let shapes = PerNoteCache<NoteShape>()
    private static let duplicateKeys = PerNoteCache<String>()

    private static func computeShape(of note: Note) -> NoteShape {
        if note.isVault { return .vault }
        switch note.keyword {
        case "timer": return .timer
        case "math": return .math
        case "list": return .list
        case "code": return .terminal
        default: break
        }
        let lines = meaningfulLines(note)
        let text = lines.joined(separator: "\n")
        if ThemeSorter.looksLikeCode(text) { return .terminal }
        if text.count < linkMaxLength, url.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil { return .link }
        if lines.count >= 4, lines.filter({ $0.count < 40 }).count * 5 >= lines.count * 4 { return .list }
        if lines.count <= 1, text.count < oneLineMaxLength { return .oneLine }
        return text.count > longTextLength ? .longText : .shortText
    }

    /// Raison de trier la note, nil si elle n'en appelle aucune. Une note
    /// épinglée ou sécurisée n'est jamais proposée au tri. `duplicates` : uuid
    /// des doublons (voir `duplicateUUIDs`).
    static func triageReason(for note: Note, duplicates: Set<String>) -> TriageReason? {
        if note.isPinned || note.isVault { return nil }
        if duplicates.contains(note.uuid) { return .duplicate }
        switch shape(of: note) {
        case .timer: return .timer
        case .link: return .link
        case .oneLine: return NoteAttachments.names(in: note.content).isEmpty ? .oneLine : nil
        default: return nil
        }
    }

    /// Notes dont le début (120 caractères, casse, accents et espaces ignorés)
    /// répète celui d'une note plus ancienne : la plus ancienne est gardée.
    static func duplicateUUIDs(_ notes: [Note]) -> Set<String> {
        var firstByKey: [String: Note] = [:]
        var duplicates: Set<String> = []
        let ordered = notes.filter { !$0.isVault }.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.uuid < $1.uuid
        }
        for note in ordered {
            let key = duplicateKeys.value(for: note) { duplicateKey(of: note) }
            guard !key.isEmpty else { continue }
            if firstByKey[key] == nil { firstByKey[key] = note } else { duplicates.insert(note.uuid) }
        }
        return duplicates
    }

    /// Début de la note ramené à l'essentiel ; vide si la note est trop courte pour être comparée.
    private static func duplicateKey(of note: Note) -> String {
        let text = meaningfulLines(note).joined(separator: " ")
        guard text.count > 20 else { return "" }
        let folded = String(text.prefix(400))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return String(folded.prefix(120))
    }

    /// Les notes en sections, dans l'ordre reçu à l'intérieur d'une section.
    /// `.recent` rend une seule section sans titre.
    static func sections(_ notes: [Note], grouping: NoteGrouping, themes: [String: String], calendar: Calendar = .current) -> [Section] {
        switch grouping {
        case .recent:
            return notes.isEmpty ? [] : [Section(title: "", noteUUIDs: notes.map(\.uuid))]
        case .theme:
            return NoteThemes.sections(noteUUIDs: notes.map(\.uuid), themes: themes).map {
                Section(title: $0.theme, noteUUIDs: $0.noteUUIDs)
            }
        case .shape:
            let byShape = Dictionary(grouping: notes, by: shape(of:))
            return NoteShape.allCases.compactMap { shape in
                byShape[shape].map { Section(title: shape.title, noteUUIDs: $0.map(\.uuid)) }
            }
        case .month:
            var order: [Int] = []
            var members: [Int: [Note]] = [:]
            for note in notes {
                let parts = calendar.dateComponents([.year, .month], from: note.createdAt)
                let key = (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
                if members[key] == nil { order.append(key) }
                members[key, default: []].append(note)
            }
            return order.sorted(by: >).map { key in
                Section(title: monthTitle(year: key / 12, month: key % 12 + 1), noteUUIDs: (members[key] ?? []).map(\.uuid))
            }
        case .triage:
            let duplicates = duplicateUUIDs(notes)
            var members: [TriageReason: [String]] = [:]
            var keep: [String] = []
            for note in notes {
                if let reason = triageReason(for: note, duplicates: duplicates) {
                    members[reason, default: []].append(note.uuid)
                } else {
                    keep.append(note.uuid)
                }
            }
            var sections = TriageReason.allCases.compactMap { reason in
                members[reason].map { Section(title: reason.title, noteUUIDs: $0) }
            }
            if !keep.isEmpty { sections.append(Section(title: keepTitle, noteUUIDs: keep)) }
            return sections
        }
    }

    private static let months = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre",
    ]

    static func monthTitle(year: Int, month: Int) -> String {
        "\(months[max(0, min(11, month - 1))]) \(year)"
    }
}

/// Valeur calculée une fois par note et par version (date de modification).
final class PerNoteCache<Value>: @unchecked Sendable {
    private var entries: [String: (updatedAt: Date, content: Int, value: Value)] = [:]
    private let lock = NSLock()

    func value(for note: Note, compute: () -> Value) -> Value {
        // La longueur du texte couvre une frappe pas encore datée.
        let signature = note.content.utf8.count &+ note.keyword.count
        lock.lock()
        if let entry = entries[note.uuid], entry.updatedAt == note.updatedAt, entry.content == signature {
            lock.unlock()
            return entry.value
        }
        lock.unlock()
        let value = compute()
        lock.lock()
        entries[note.uuid] = (note.updatedAt, signature, value)
        lock.unlock()
        return value
    }
}
