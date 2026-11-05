import Foundation

enum NoteMode: String, CaseIterable, Sendable {
    case math
    case list
    case timer
    case code
    case plain
    /// Note sécurisée : corps chiffré. Jamais proposé au serveur JEV.
    case vault

    var label: String {
        switch self {
        case .math: return "MATH"
        case .list: return "LISTE"
        case .timer: return "TIMER"
        case .code: return "CODE"
        case .plain: return "TEXTE"
        case .vault: return "COFFRE"
        }
    }

    /// Modes que JEV peut choisir : une demande ne crée jamais de note sécurisée.
    static var routable: [NoteMode] { allCases.filter { $0 != .vault } }
}

enum RouteSource: Sendable {
    case jev
    case local
    case motsCles

    var label: String {
        switch self {
        case .jev: return "JEV"
        case .local: return "modèle local"
        case .motsCles: return "mots-clés"
        }
    }
}

struct ModeDecision: Sendable, Equatable {
    let mode: NoteMode
    let source: RouteSource
    var echec: String? = nil
}

/// Routage de mode à la JEV : le serveur de décision CLASSE la demande dans
/// un mode selon un schéma strict, il ne rédige rien. En cas d'échec
/// (serveur muet, réponse incomplète, schéma refusé), on retombe franchement
/// sur les mots-clés, et la décision porte sa source pour qu'on le sache.
struct ModeRoutingFeature {
    static let instructions = """
    Classe la demande de l'utilisateur dans un seul mode d'une note AlphaNote.
    Réponds uniquement selon le schéma, sans rédiger. En cas de doute, plain.
    """

    static let modeField: JEVField = .string(
        choices: NoteMode.routable.map(\.rawValue),
        description: """
        Le mode que la demande appelle.
        - math : la demande cherche un résultat chiffré — calcul, pourcentage, \
        réduction, écart de prix, conversion d'unités ou de devises, ou une formule \
        décrite en mots (aire, volume, mensualité, intérêts…). \
        Exemples : « 12 * 8 », « pourcentage de réduction entre 120 et 90 », « 10 km to mi », \
        « aire d'un cercle de rayon 3 ».
        - list : la demande veut une liste, une check-list, des tâches, des courses, \
        des ingrédients, ajouter des éléments à une liste, ou contient le lien d'une \
        recette (ses ingrédients deviennent la liste). \
        Exemples : « courses : tomates, pâtes, huile », « ajoute de l'huile d'olive à la liste », \
        « https://www.marmiton.org/recettes/recette_crepes.aspx ».
        - timer : la demande veut un minuteur, un compte à rebours, un chronomètre \
        ou une alarme à une heure donnée. Exemples : « minuteur 25 minutes », « lance un chrono », \
        « réveille-moi à 7h30 », « alarme à 14h ».
        - code : la demande écrit, corrige ou range un snippet de code ou une commande.
        - plain : cas par défaut — une pensée, une question, du texte, une note \
        qui ne correspond à aucun autre mode.
        """
    )

    static var schema: JEVSchema {
        ["mode": modeField]
    }

    func route(question: String, noteKeyword: String?) async -> ModeDecision {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ModeDecision(mode: .plain, source: .motsCles)
        }

        var echec: String? = nil
        if AIFeatureGate.isEnabled, JEVClient.config() != nil {
            switch await JEVClient.decider(
                instructions: Self.instructions,
                schema: Self.schema,
                fragments: [trimmed]
            ) {
            case let .ok(decisions):
                if case let .string(modeRaw)? = decisions.first?["mode"],
                   let mode = NoteMode(rawValue: modeRaw) {
                    return ModeDecision(mode: mode, source: .jev)
                }
                echec = "Le serveur n'a pas désigné de mode valide."
            case let .erreur(message):
                echec = message
            }
        }

        // Sans serveur (ou s'il a échoué) : le modèle local de l'appareil.
        if let local = LocalModeClassifier.shared.classify(trimmed),
           local.confidence >= LocalModeClassifier.minimumConfidence {
            return ModeDecision(mode: local.mode, source: .local, echec: echec)
        }

        return ModeDecision(
            mode: KeywordIntentRouter.classify(trimmed, noteKeyword: noteKeyword),
            source: .motsCles,
            echec: echec
        )
    }
}

enum AIFeatureGate {
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: AISettingsKeys.enabled)
    }
}
