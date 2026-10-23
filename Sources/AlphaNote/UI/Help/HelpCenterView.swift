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

            1. Appuyez sur le raccourci global (⌥A par défaut, réglable) : la fenêtre apparaît au-dessus de tout.
            2. Écrivez. C'est tout.
            3. Tapez `math`, `list`, `code` ou `timer` en première ligne pour changer le mode — ou choisissez-le dans la pastille en haut à droite.
            4. Échap cache la fenêtre. Les notes vides disparaissent toutes seules.

            ## Naviguer

            - `⌥⌘L` ouvre le volet des notes à gauche (recherche, épinglées, archives). Il pousse l'éditeur et reste ouvert tant que vous ne le refermez pas ; ↑ / ↓ dans la recherche changent de note.
            - Swipe horizontal sur le trackpad, ou `⌥⌘←` / `⌥⌘→`, pour passer d'une note à l'autre.
            - `⌘K` ouvre la demande en langage naturel (« minuteur 25 min », « courses : pain, lait »).

            ## Principes

            - **Local-first** : vos notes vivent dans une base SQLite sur votre Mac.
            - **Éphémère** : AlphaNote est un bloc-notes, pas une archive. Épinglez ce qui doit rester.
            - **Les mots sont des commandes** : la première ligne pilote le mode.
            """
        case .shortcuts:
            return """
            # Raccourcis

            - Raccourci global (par défaut `⌥A`) : afficher / masquer AlphaNote
            - `Échap` : fermer la demande ⌘K, sinon cacher la fenêtre (Échap dans la recherche referme le volet)
            - `⌥⌘N` : nouvelle note
            - `⌥⌘←` / `⌥⌘→` : note précédente / suivante
            - `⌥⌘L` : afficher / masquer le volet des notes
            - `⇧⌘F` : rechercher dans les notes
            - `⌘K` : demande en langage naturel
            - `⌥⌘1` … `⌥⌘5` : mode Texte, Math, Liste, Code, Minuteur
            - `⇧⌘L` (réglable) : convertir la note en liste
            - `⌥⌘P` : épingler / désépingler
            - `⌥⌘E` : archiver
            - `⌥⌘⌫` : supprimer
            - `⌘F` : rechercher dans la note
            - `⌘,` : réglages · `⇧⌘H` : cette aide
            """
        case .noteModes:
            return """
            # Modes de notes

            Le mode est décidé par la première ligne (`math`, `list`, `code`, `timer`, avec ou sans `: titre`).
            Un seul éditeur sert à tous les modes : changer de mode ne fait jamais perdre le curseur.

            ## Texte

            Aucune première ligne spéciale. Les adresses web deviennent cliquables.

            ## `math`

            - Variables : `loyer: 900`, réutilisables dans les lignes suivantes.
            - Résultat inline sur toute ligne terminée par `=` : `loyer * 12 =`.
            - Fonctions : `sqrt`, `abs`, `round`, `floor`, `ceil`, `ln`, `log`, `exp`, `sin`, `cos`, `tan`, `min`, `max`, factorielle `5!`, constante `pi`.
            - Pourcentages : `prix - 15% =`, variables en % (`tva: 21%` puis `total + tva =`).
            - Unités : `10 kg + 500 g =`, `12 km to mi =`, `72°F to °C =`.
            - Devises : `100 USD to EUR =` (taux BCE, mis en cache une heure ; `…` le temps du chargement).
            - `//` commence un commentaire.

            ## `list`

            - Chaque ligne est un élément ; cliquez la case en marge pour cocher.
            - `# Titre` pour une section, `// texte` pour un commentaire.
            - Entrée après une ligne commençant par `- ` continue la puce.
            - Une ligne cochée porte le déclencheur (par défaut `/x`), réglable dans Apparence.

            ## `code`

            - Police monospace, retrait conservé.

            ## `timer`

            - Minuteur, chrono ou pomodoro ; préréglages 5 à 60 min.
            - Le minuteur continue si vous changez de note ou cachez la fenêtre, et survit au redémarrage.
            - À la fin : sonnerie en boucle jusqu'à « Arrêter la sonnerie », et l'icône du Dock rebondit.
            """
        case .sync:
            return """
            # Synchronisation Nextcloud

            ## Configuration

            1. Ouvrez **Réglages › Synchronisation**.
            2. Activez « Synchroniser via Nextcloud ».
            3. Saisissez l'URL du serveur, l'utilisateur et un mot de passe d'application.
            4. « Tester la connexion ».

            ## Fonctionnement

            - Un fichier JSON par note dans `AlphaNote/notes/`, identifié par UUID.
            - Sync toutes les N minutes, et 30 s après une modification locale.
            - Les notes distantes inchangées (même ETag) ne sont pas re-téléchargées.
            - Conflit : la modification la plus récente gagne.
            - Suppressions propagées ; purge après 30 jours.

            ## Sécurité

            - Le mot de passe est dans le trousseau macOS, jamais dans la base.
            - Une app signée ad-hoc change d'identité à chaque build : macOS peut redemander l'accès au trousseau après une mise à jour. Une identité de signature stable (`CODESIGN_IDENTITY`) évite cela.
            """
        case .settings:
            return """
            # Réglages

            ## Général

            - Raccourci global : activé / combinaison (cliquez, puis appuyez).
            - Toujours au premier plan, Dock, barre des menus.
            - Suppression des notes vides quand la fenêtre se cache.

            ## Apparence

            - Thème (système, clair, sombre) et taille du texte.
            - Déclencheur « coché » et raccourci « Convertir en liste ».

            ## Synchronisation

            - Nextcloud (WebDAV) et imports Nextcloud Notes / Apple Notes.

            ## IA

            - Routage de mode par serveur de décision JEV : il **classe** la demande, il ne rédige jamais. Le schéma envoyé est affiché.

            ## Mises à jour

            - Canal appcast, vérification et installation.

            ## Avancé

            - Dossier de la base (déplacement sûr avec relance), exports JSON et Markdown.
            """
        case .troubleshooting:
            return """
            # Dépannage

            ## Le raccourci global ne répond pas

            - Vérifiez qu'il est activé dans Réglages › Général et qu'aucune autre app ne l'utilise.
            - Le raccourci est physique : sur un clavier AZERTY, l'étiquette affichée suit la disposition.

            ## La sync échoue

            - Vérifiez URL, utilisateur, mot de passe d'application, puis « Tester la connexion ».
            - Le WebDAV doit répondre sur `remote.php/dav/files/<utilisateur>/`.

            ## Une conversion de devise affiche `…`

            - Les taux se chargent en arrière-plan (sans réseau, ils restent indisponibles). Le résultat apparaît dès réception.

            ## Où sont mes données

            - Réglages › Avancé affiche le dossier de la base et permet de l'ouvrir dans le Finder.
            - Si le dossier configuré n'est pas accessible, AlphaNote revient au dossier par défaut et le signale.

            ## Une note a disparu

            - Volet des notes › Archives. Les notes vides sont supprimées à la fermeture (réglable).
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
