import Foundation

/// Seule exception au contrat JEV (décision de Paul, 2026-10-24) : en mode
/// math, le modèle du serveur peut RÉDIGER une formule à partir d'une demande
/// en mots (« aire d'un cercle de rayon 3 »). Garde-fous :
/// - la formule n'est gardée que si l'évaluateur local la calcule, et chaque
///   mot doit être une fonction connue, `pi` ou une variable définie juste
///   au-dessus (l'évaluateur ignorerait sinon les mots inconnus en silence) ;
/// - elle est écrite sous un commentaire qui dit qu'elle vient de l'IA ;
/// - un échec est franc : rien n'est écrit et l'écran dit pourquoi.
struct FormulaDraftFeature {

    struct Draft: Equatable, Sendable {
        /// Lignes de la note math : `nom: expr` pour les intermédiaires, la
        /// dernière (`expr =` ou `nom: expr =`) affiche le résultat.
        let lines: [String]
        let model: String?
    }

    static let systemPrompt = """
    Tu traduis une demande en formule pour la note math d'AlphaNote.
    Réponds uniquement en JSON : {"lignes": ["...", "..."]}.
    Règles :
    - Chaque ligne intermédiaire définit une variable : "nom: expression". Noms en minuscules sans accent, lettres, chiffres et _ uniquement.
    - La dernière ligne donne le résultat : "nom: expression =" (sans le résultat).
    - Convertis vers l'unité demandée (m³ → litres : × 1000 ; minutes → heures : / 60).
    - Opérateurs : + - * / ^ ( ). Décimales avec un point. Pourcentages en décimal (3 % → 0.03).
    - Fonctions : sqrt abs round floor ceil ln log log2 exp sin cos tan min max ; constante pi. Angles en radians.
    - Aucun autre mot, aucune unité, aucun commentaire.
    Exemple : "mensualité d'un prêt de 200000 à 3 % sur 20 ans" →
    {"lignes": ["taux: 0.03 / 12", "mois: 20 * 12", "mensualite: 200000 * taux / (1 - (1 + taux)^(-mois)) ="]}
    """

    /// Le modèle réfléchit avant de répondre (Qwen3 « thinking ») : 7 à 20 s
    /// au lieu d'une, mais sans réflexion il se trompait sur des formules
    /// simples (secondes par semaine, m³ → litres). D'où un délai propre.
    static let minimumDelaiMs = 60_000

    static let maxLines = 8

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AISettingsKeys.formulaDraftEnabled) as? Bool ?? true
    }

    func draft(
        question: String,
        transport: JEVTransport = URLSessionJEVTransport()
    ) async -> JEVOutcome<Draft> {
        guard let config = JEVClient.config() else {
            return .erreur("Aucun serveur IA configuré.")
        }
        return await draft(question: question, config: config, transport: transport)
    }

    func draft(
        question: String,
        config: JEVConfig,
        transport: JEVTransport = URLSessionJEVTransport()
    ) async -> JEVOutcome<Draft> {
        guard let url = URL(string: config.url + "/v1/chat/completions") else {
            return .erreur("L'URL du serveur IA est invalide.")
        }
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": question]
            ],
            "temperature": 0,
            "max_tokens": 4_000
        ]

        let data: Data
        do {
            data = try await transport.post(
                url: url,
                body: try JSONSerialization.data(withJSONObject: body),
                delaiMs: max(config.delaiMs, Self.minimumDelaiMs),
                headers: config.headers
            )
        } catch let error as JEVTransportError {
            return .erreur(error.message(serveur: "le serveur IA"))
        } catch {
            return .erreur("Le serveur IA n'a pas répondu.")
        }

        guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = ((response["choices"] as? [Any])?.first as? [String: Any])
                .flatMap({ $0["message"] as? [String: Any] })?["content"] as? String else {
            return .erreur("Réponse du serveur IA illisible.")
        }
        let model = (response["model"] as? String).map { ($0 as NSString).lastPathComponent }

        switch Self.parseLines(content) {
        case let .ok(lines):
            if let fault = Self.validate(lines) {
                return .erreur("Formule de l'IA rejetée : \(fault).")
            }
            return .ok(Draft(lines: lines, model: model))
        case let .erreur(message):
            return .erreur(message)
        }
    }

    // MARK: - Lecture et contrôle (purs, testés)

    static func parseLines(_ content: String) -> JEVOutcome<[String]> {
        // Un éventuel bloc <think>…</think> ou des balises ``` autour du JSON.
        var text = content.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["lignes"] as? [Any] else {
            return .erreur("L'IA n'a pas rendu de formule.")
        }
        let lines = raw.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return .erreur("L'IA n'a pas rendu de formule.")
        }
        return .ok(lines)
    }

    /// nil si la formule est acceptable, sinon la raison du rejet.
    static func validate(_ lines: [String]) -> String? {
        guard lines.count <= maxLines else { return "trop de lignes" }
        guard let last = lines.last, last.hasSuffix("=") else { return "pas de ligne de résultat" }

        var defined = Set<String>()
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            let expression: String
            if isLast, let assignment = MathDocumentEvaluator.parseVariableAssignment(from: line) {
                guard assignment.showsResult else { return "pas de ligne de résultat" }
                expression = assignment.expression
            } else if isLast {
                expression = String(line.dropLast()).trimmingCharacters(in: .whitespaces)
                guard !expression.contains("=") else { return "ligne de résultat mal formée" }
            } else {
                guard let assignment = MathDocumentEvaluator.parseVariableAssignment(from: line),
                      !assignment.showsResult,
                      assignment.name.range(of: #"^[a-z_][a-z0-9_]*$"#, options: .regularExpression) != nil else {
                    return "« \(line) » n'est pas une variable valide"
                }
                guard !MathEvaluator.isKnownName(assignment.name) else {
                    return "« \(assignment.name) » est un nom réservé"
                }
                expression = assignment.expression
            }
            guard !expression.isEmpty else { return "expression vide" }
            if let unknown = unknownWord(in: expression, defined: defined) {
                return "mot inconnu « \(unknown) »"
            }
            if !isLast, let assignment = MathDocumentEvaluator.parseVariableAssignment(from: line) {
                defined.insert(assignment.name)
            }
        }

        // La note doit effectivement calculer la dernière ligne.
        let outcomes = MathDocumentEvaluator().evaluate(content: (["math"] + lines).joined(separator: "\n"))
        guard let result = outcomes.last?.transformed,
              let equal = result.lastIndex(of: "="),
              !result[result.index(after: equal)...].trimmingCharacters(in: .whitespaces).isEmpty else {
            return "le calcul n'aboutit pas"
        }
        return nil
    }

    private static func unknownWord(in expression: String, defined: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}_][\p{L}\p{N}_]*"#) else { return nil }
        let nsExpression = expression as NSString
        for match in regex.matches(in: expression, range: NSRange(location: 0, length: nsExpression.length)) {
            let word = nsExpression.substring(with: match.range)
            if !defined.contains(word) && !MathEvaluator.isKnownName(word) {
                return word
            }
        }
        return nil
    }
}
