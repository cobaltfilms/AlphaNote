import Foundation

enum AIPromptBuilder {
    static let systemPrompt = """
    Tu es l'assistant local d'AlphaNote. Réponds en français clair, utile, précis. Respecte strictement la consigne de format quand elle est demandée.
    """

    static func prompt(for task: AITask, note: Note, context: AIContext) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = clipped(note.content, maxCharacters: 6000)

        switch task {
        case .summarize:
            return """
            Tâche: Résumer cette note.
            Contraintes:
            - 5 puces maximum.
            - Garde seulement l'essentiel.
            - N'invente rien.

            Titre: \(title)
            Contenu:
            \(content)
            """

        case let .rewrite(style):
            return """
            Tâche: Réécrire la note dans un style \(style.rawValue).
            Contraintes:
            - Préserver les faits et les décisions.
            - Corriger les fautes.
            - Ne pas ajouter d'informations non présentes.

            Titre: \(title)
            Contenu:
            \(content)
            """

        case .extractActions:
            return """
            Tâche: Extraire les actions concrètes de cette note.
            Réponds uniquement en JSON valide avec ce schéma:
            {"actions":[{"title":"...","owner":"...","deadline":"...","priority":"low|medium|high"}]}

            Règles:
            - Si une donnée manque, mets une chaîne vide.
            - Aucune clé supplémentaire.
            - Si aucune action: {"actions":[]}

            Titre: \(title)
            Contenu:
            \(content)
            """

        case .semanticAnswer:
            let related = context.relatedNotes.prefix(5).map {
                "- [\($0.uuid)] \($0.title): \(clipped($0.content, maxCharacters: 700))"
            }.joined(separator: "\n")
            let relatedBlock = related.isEmpty ? "- (aucune note fournie)" : related
            let listRefinement = AIIntentDetector.isListRefinementRequest(content)
            let quantityRequest = AIIntentDetector.asksForQuantityDetails(content)
            let formattingRule: String
            if listRefinement || quantityRequest {
                formattingRule = """
                Format:
                - Réponds uniquement avec la liste finale, un élément par ligne commençant par "* ".
                - Si l'utilisateur demande des quantités, ajoute une quantité à chaque ingrédient.
                - Pas d'introduction, pas de conclusion, pas de section Sources.
                """
            } else {
                formattingRule = "Termine par une section \"Sources\" listant les UUID utilisés."
            }

            return """
            Tâche: Répondre à la question en t'appuyant uniquement sur les notes fournies.
            Important:
            - Si une note est marquée "[NOTE ACTIVE PRIORITAIRE]", commence par elle.
            - Si la réponse est dans cette note active, ne dis pas que l'information est absente.
            - Respecte la forme demandée par l'utilisateur (ex: liste, calcul, explication).
            Si l'information n'est pas présente, dis-le clairement.
            \(formattingRule)

            Question:
            \(content)

            Notes pertinentes:
            \(relatedBlock)
            """
        }
    }

    private static func clipped(_ text: String, maxCharacters: Int) -> String {
        if text.count <= maxCharacters {
            return text
        }
        let index = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<index])
    }
}
