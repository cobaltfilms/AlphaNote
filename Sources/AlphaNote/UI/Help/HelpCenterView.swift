import SwiftUI
import AppKit

struct HelpCenterView: View {
    @State private var selectedSection: HelpSection = .quickStart

    var body: some View {
        NavigationSplitView {
            List(HelpSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("Aide AlphaNote")
            .padding(.top, 6)
        } detail: {
            ScrollView {
                markdownView(for: selectedSection.markdown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(selectedSection.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ouvrir le guide") {
                        Self.openGuideInExternalViewer()
                    }
                }
            }
        }
        .frame(minWidth: 840, minHeight: 620)
    }

    @ViewBuilder
    private func markdownView(for markdown: String) -> some View {
        HelpMarkdownView(markdown: markdown)
    }

    static func openGuideInExternalViewer() {
        if let url = HelpDocumentationLoader.guideURL {
            NSWorkspace.shared.open(url)
            return
        }

        let fallback = HelpDocumentationLoader.fullGuideMarkdown
        guard !fallback.isEmpty else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlphaNote-Guide-Complet.md")
        try? fallback.write(to: tempURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tempURL)
    }
}

private struct HelpMarkdownView: View {
    let markdown: String

    private enum RowKind {
        case h1
        case h2
        case bullet
        case numbered(String)
        case body
        case empty
    }

    private struct Row: Identifiable {
        let id = UUID()
        let kind: RowKind
        let text: String
    }

    private var rows: [Row] {
        markdown
            .components(separatedBy: .newlines)
            .map(parseRow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                rowView(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row.kind {
        case .h1:
            formattedText(row.text)
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 10)
                .padding(.bottom, 4)
        case .h2:
            formattedText(row.text)
                .font(.system(size: 21, weight: .semibold))
                .padding(.top, 8)
                .padding(.bottom, 3)
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .semibold))
                formattedText(row.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
            }
        case let .numbered(number):
            HStack(alignment: .top, spacing: 8) {
                Text(number)
                    .font(.system(size: 14, weight: .semibold))
                formattedText(row.text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
            }
        case .body:
            formattedText(row.text)
                .font(.system(size: 15))
                .lineSpacing(3)
        case .empty:
            Color.clear
                .frame(height: 6)
        }
    }

    private func parseRow(_ rawLine: String) -> Row {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            return Row(kind: .empty, text: "")
        }

        if line.hasPrefix("# ") {
            return Row(kind: .h1, text: String(line.dropFirst(2)))
        }

        if line.hasPrefix("## ") {
            return Row(kind: .h2, text: String(line.dropFirst(3)))
        }

        if line.hasPrefix("- ") {
            return Row(kind: .bullet, text: String(line.dropFirst(2)))
        }

        if let numbered = parseNumberedLine(line) {
            return numbered
        }

        return Row(kind: .body, text: line)
    }

    private func parseNumberedLine(_ line: String) -> Row? {
        let pattern = #"^(\d+\.)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ),
              let numberRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        return Row(kind: .numbered(String(line[numberRange])), text: String(line[textRange]))
    }

    private func formattedText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        }
        return Text(text)
    }
}

private enum HelpSection: String, CaseIterable, Identifiable {
    case quickStart
    case shortcuts
    case noteModes
    case sync
    case settings
    case troubleshooting
    case fullGuide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickStart:
            return "Démarrage"
        case .shortcuts:
            return "Raccourcis"
        case .noteModes:
            return "Modes de notes"
        case .sync:
            return "Synchronisation"
        case .settings:
            return "Réglages"
        case .troubleshooting:
            return "Dépannage"
        case .fullGuide:
            return "Guide complet"
        }
    }

    var symbol: String {
        switch self {
        case .quickStart:
            return "play.circle"
        case .shortcuts:
            return "keyboard"
        case .noteModes:
            return "square.and.pencil"
        case .sync:
            return "arrow.triangle.2.circlepath"
        case .settings:
            return "gearshape"
        case .troubleshooting:
            return "wrench.and.screwdriver"
        case .fullGuide:
            return "doc.text"
        }
    }

    var markdown: String {
        switch self {
        case .quickStart:
            return """
            # Démarrage rapide

            1. Ouvrez AlphaNote.
            2. Appuyez sur `⌥A` pour afficher/masquer la fenêtre flottante.
            3. Créez une note avec `⌥⌘N` ou le bouton `Nouvelle note`.
            4. Naviguez dans les notes avec un swipe horizontal ou en cliquant dans la liste.

            ## Navigation

            - `⌥⌘L` affiche/masque la liste des notes.
            - Le compteur en haut (`2 / 8`) montre votre position dans les notes actives.
            - Archiver une note la retire de la liste principale sans la supprimer.

            ## Principes clés

            - AlphaNote fonctionne en **local-first** (base SQLite locale).
            - Une note est un simple texte dont la première ligne peut activer un mode (`math`, `list`, `code`, `timer`).
            """
        case .shortcuts:
            return """
            # Raccourcis disponibles

            - `⌥A` : afficher/masquer AlphaNote (hotkey globale)
            - `⌥⌘N` : créer une nouvelle note
            - `⌥⌘L` : afficher/masquer la liste des notes
            - `⌘⇧L` (par défaut) : convertir la note active en mode liste
            - `⌘⇧H` : ouvrir le centre d’aide AlphaNote
            - `⌘,` : ouvrir les réglages

            ## Raccourci liste personnalisable

            Le raccourci “Convertir en liste” est configurable dans **Réglages > Keywords**.
            """
        case .noteModes:
            return """
            # Modes de notes

            ## Texte simple

            Aucune première ligne spéciale: vous êtes en édition texte libre.

            ## `math`

            - Première ligne: `math` ou `math: titre`
            - Variables: `salaire: 3200`
            - Résultat inline: `salaire * 12 =`
            - Conversions: `12 km to mi =`, `72 kg in lb =`, `100 USD to EUR =`

            ## `list`

            - Première ligne: `list` ou `list: titre`
            - Lignes cliquables en checklist
            - Déclencheur “coché” configurable (par défaut: `/x`)
            - Lignes `#`, `##`, `###` affichées comme titres
            - Lignes `//` affichées comme commentaires

            ## `code`

            - Police monospace
            - Détection visuelle du langage à partir du titre (`swift`, `python`, `js`, `rust`, etc.)

            ## `timer`

            - Modes: Stopwatch, Countdown, Pomodoro
            - Notification locale quand un compte à rebours se termine
            """
        case .sync:
            return """
            # Synchronisation Nextcloud

            ## Configuration

            1. Ouvrez **Réglages > Advanced**.
            2. Activez `Enable cloud sync`.
            3. Saisissez l’URL serveur Nextcloud.
            4. Saisissez le nom d’utilisateur.
            5. Saisissez un mot de passe d’application.
            6. Lancez `Test connection`.

            ## Fonctionnement

            - Les notes sont synchronisées au format JSON par UUID.
            - Résolution de conflit basée sur `updatedAt`, puis `lastModifiedByDeviceId`.
            - Les suppressions sont propagées (soft delete + purge distante après délai).

            ## Sécurité

            - Le mot de passe n’est pas stocké en clair dans la base.
            - Il est enregistré dans le Trousseau macOS (Keychain).
            """
        case .settings:
            return """
            # Réglages

            ## General

            - Hotkey globale (`⌥A`)
            - Présence Dock/Menu Bar
            - Auto-cleanup des notes vides

            ## Appearance

            - Taille de police
            - Thème

            ## Keywords

            - Mots-clés de modes (`math`, `list`, `code`, `timer`)
            - Déclencheur check-list
            - Raccourci “Convertir en liste”

            ## Advanced

            - Emplacement de base de données
            - Synchronisation Nextcloud
            - Export JSON
            """
        case .troubleshooting:
            return """
            # Dépannage

            ## Le hotkey `⌥A` ne répond pas

            - Vérifiez qu’AlphaNote est bien lancée.
            - Vérifiez qu’aucune autre app n’utilise déjà ce raccourci.

            ## La sync échoue

            - Vérifiez URL, utilisateur, mot de passe applicatif.
            - Testez via le bouton `Test connection`.
            - Vérifiez que le WebDAV Nextcloud est actif (`remote.php/dav/files/...`).

            ## Mes données sont où

            - Base SQLite locale: chemin visible dans **Réglages > Advanced**.
            - Bouton `Reveal in Finder` pour ouvrir le dossier.

            ## Export

            - Utilisez `Export Data` pour générer un JSON de toutes les notes non supprimées logiquement.
            """
        case .fullGuide:
            return HelpDocumentationLoader.fullGuideMarkdown
        }
    }
}

private enum HelpDocumentationLoader {
    static var guideURL: URL? {
        let candidates: [(String, String, String?)] = [
            ("ALPHANOTE_HELP_FR", "md", "Docs"),
            ("ALPHANOTE_HELP_FR", "md", nil),
            ("ALPHANOTE_HELP_FR", "md", "Resources/Docs")
        ]

        for candidate in candidates {
            let url = Bundle.module.url(
                forResource: candidate.0,
                withExtension: candidate.1,
                subdirectory: candidate.2
            )
            if let url {
                return url
            }
        }

        let projectRelativePath = "Sources/AlphaNote/Resources/Docs/ALPHANOTE_HELP_FR.md"
        let cwdURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let cwdGuideURL = cwdURL.appendingPathComponent(projectRelativePath)
        if FileManager.default.fileExists(atPath: cwdGuideURL.path) {
            return cwdGuideURL
        }

        return nil
    }

    static var fullGuideMarkdown: String {
        if let url = guideURL,
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        return """
        # Guide complet

        ## État
        Le fichier embarqué du guide complet n'a pas été trouvé dans le bundle de l'application.

        ## Où trouver la version source
        - `Sources/AlphaNote/Resources/Docs/ALPHANOTE_HELP_FR.md`

        ## Actions recommandées
        - Nettoyer et reconstruire l'application.
        - Vérifier que le fichier est bien inclus dans la cible SPM.
        - Ouvrir le centre d’aide depuis le menu Help pour retester le chargement.
        """
    }
}
