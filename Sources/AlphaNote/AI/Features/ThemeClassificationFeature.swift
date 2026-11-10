import Foundation

/// Rangement par rayon à la JEV : le serveur de décision CLASSE chaque note
/// dans un rayon selon un schéma strict, il ne rédige rien.
///
/// Uniquement à la demande (« Ranger avec JEV ») : c'est le seul endroit où le
/// **contenu** de notes part vers le serveur (titre et début du texte). Une note
/// sécurisée ne part jamais, une note qui a déjà un thème écrit non plus. Une
/// réponse manquante ou « fourre_tout » laisse la note sans thème : pas de
/// classement forcé.
struct ThemeClassificationFeature {
    struct Shelf: Sendable {
        let choice: String
        /// Nom écrit dans la note (`thème : …`). Nil : la note n'est pas rangée.
        let theme: String?
        let description: String
    }

    /// Les rayons, décrits en phrases : c'est la description qui fait la
    /// qualité de la réponse. Mêmes noms que le catalogue local (`ThemeSorter`).
    static let shelves: [Shelf] = [
        Shelf(choice: "informatique", theme: "Informatique",
              description: "commandes de terminal, serveurs, réseau, NAS, Linux, Docker, code, journaux d'erreurs, matériel d'ordinateur, numéros de série et licences de logiciels"),
        Shelf(choice: "image_et_son", theme: "Image & son",
              description: "cinéma, tournage, montage, étalonnage, DaVinci Resolve, DCP, mastering, caméras, écrans, son, films"),
        Shelf(choice: "argent_et_papiers", theme: "Argent & papiers",
              description: "factures, banque, TVA, impôts, contrats, clients, démarches administratives, candidatures, attestations"),
        Shelf(choice: "vie_perso", theme: "Vie perso",
              description: "famille, enfants, santé, maison, voyages, trajets, sorties, cadeaux, réflexions personnelles, lectures"),
        Shelf(choice: "cuisine", theme: "Cuisine",
              description: "recettes, ingrédients, courses alimentaires"),
        Shelf(choice: "fourre_tout", theme: nil,
              description: "note trop courte ou trop vague pour être rangée (un mot, un lien seul, un minuteur, des chiffres sans contexte)"),
    ]

    static let instructions = """
    Tu classes une note personnelle (français ou anglais) dans un seul rayon.
    Réponds uniquement selon le schéma, sans rédiger. En cas de doute, fourre_tout.
    """

    static let field: JEVField = .string(
        choices: shelves.map(\.choice),
        description: "Le rayon où ranger la note. " + shelves.map { "\($0.choice) = \($0.description)" }.joined(separator: ". ") + "."
    )

    static let schema: JEVSchema = ["rayon": field]

    /// Longueur de texte envoyée par note.
    static let excerptLength = 700
    static let batchSize = 8

    /// Notes à proposer au serveur : ni sécurisées, ni déjà rangées à la main,
    /// ni vides.
    static func candidates(_ notes: [Note]) -> [Note] {
        notes.filter { note in
            !note.isVault && !note.isDeleted && NoteThemes.explicit(in: note.content) == nil
                && !NoteOrganizer.meaningfulLines(note).isEmpty
        }
    }

    /// Ce qui part au serveur pour une note : son titre, puis le début du texte utile.
    static func fragment(for note: Note) -> String {
        let text = NoteThemes.classifiableText(title: note.title, content: note.content)
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(excerptLength))
        return title.isEmpty ? body : title + "\n" + body
    }

    struct Outcome: Sendable, Equatable {
        /// uuid → thème décidé par le serveur.
        var themes: [String: String] = [:]
        /// Notes que le serveur a laissées au fourre-tout.
        var unsorted = 0
        /// Notes sans réponse exploitable.
        var failed = 0
        /// Message de la première erreur de transport, s'il y en a eu une.
        var error: String?
    }

    /// Classe les notes par lots. Une erreur de serveur arrête tout de suite :
    /// ce qui est déjà décidé est rendu, le reste compte comme échec.
    func classify(
        _ notes: [Note],
        config: JEVConfig,
        transport: JEVTransport = URLSessionJEVTransport(),
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> Outcome {
        var outcome = Outcome()
        let byChoice = Dictionary(uniqueKeysWithValues: Self.shelves.map { ($0.choice, $0) })
        var index = 0
        while index < notes.count {
            let batch = Array(notes[index..<min(index + Self.batchSize, notes.count)])
            let result = await JEVClient.decider(
                config: config, instructions: Self.instructions, schema: Self.schema,
                fragments: batch.map(Self.fragment(for:)), transport: transport
            )
            switch result {
            case let .erreur(message):
                outcome.error = message
                outcome.failed += notes.count - index
                return outcome
            case let .ok(decisions):
                for (note, decision) in zip(batch, decisions) {
                    guard case let .string(choice)? = decision["rayon"], let shelf = byChoice[choice] else {
                        outcome.failed += 1
                        continue
                    }
                    if let theme = shelf.theme { outcome.themes[note.uuid] = theme } else { outcome.unsorted += 1 }
                }
            }
            index += batch.count
            await progress(index, notes.count)
        }
        return outcome
    }
}
