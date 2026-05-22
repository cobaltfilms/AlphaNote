import Foundation

enum AIPromptBuilder {
    static let systemPrompt = """
    Tu es l'assistant local d'AlphaNote.
    Contraintes non négociables:
    - Réponds en français clair, utile, précis.
    - Reste strictement dans le contexte et les fonctionnalités d'AlphaNote.
    - Ne fournis jamais de réflexion interne ni de plan caché.
    - Produis un résultat exploitable pour la note (contenu final).
    - Respecte strictement la consigne de format quand elle est demandée.
    """

    static func prompt(for task: AITask, note: Note, context: AIContext) -> String {
        let title = note.effectiveTitle
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

        case .modeRouting:
            let noteMode = context.noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return """
            Tâche: Choisir le ou les modes AlphaNote à activer pour traiter la requête.
            Réponds uniquement en JSON valide avec ce schéma strict:
            {
              "modes": ["math","list","web","qa","transform"],
              "confidence": 0.0,
              "reason": "court"
            }

            Règles:
            - "modes" contient uniquement ces valeurs autorisées.
            - Tu peux cumuler plusieurs modes (ex: ["web","list"], ["web","qa"]).
            - Si la requête demande une recherche internet/web/URL: inclure "web" et "qa".
            - Si la requête demande une liste de contenu: inclure "list".
            - Si la requête demande un calcul: inclure "math".
            - Si la requête demande de réécrire/modifier la note: inclure "transform".
            - Si doute: inclure au minimum "qa".
            - Priorité du mode courant de la note (si fourni): \(noteMode.isEmpty ? "aucun" : noteMode).
            - Aucune clé supplémentaire.

            Requête:
            \(content)
            """

        case .semanticAnswer:
            let related = context.relatedNotes.prefix(5).map {
                "- [\($0.uuid)] \($0.title): \(clipped($0.content, maxCharacters: 700))"
            }.joined(separator: "\n")
            let relatedBlock = related.isEmpty ? "- (aucune note fournie)" : related
            let wantsList = AIIntentDetector.isExplicitListRequest(content) || AIIntentDetector.isListRefinementRequest(content)
            let asksQuantity = AIIntentDetector.asksForQuantityDetails(content)
            let wantsTransformation = AIIntentDetector.isNoteTransformationRequest(content)
            let wantsWebResearch = AIIntentDetector.isWebResearchRequest(content)
            let preferredAction: String
            if wantsList {
                preferredAction = "list"
            } else if wantsWebResearch {
                preferredAction = "append"
            } else if wantsTransformation {
                preferredAction = "replace"
            } else {
                preferredAction = "none"
            }
            let listRule = asksQuantity
                ? "Si l'utilisateur demande des quantités, ajoute une quantité explicite à chaque ligne de liste."
                : "Quand tu produis une liste, un élément par ligne."

            return """
            Tâche: Interagir avec les notes fournies et répondre à la demande utilisateur.
            Contexte produit AlphaNote (documentation):
            - AlphaNote est une app de notes locales orientée capture rapide.
            - Les modes principaux sont: math, list, code, timer.
            - En mode math: calculs, pourcentages, conversions unités/devises.
            - En mode list: produire des listes claires, actionnables et directement insérables.
            - Tu dois aider à produire du contenu de note, pas un raisonnement sur l'utilisateur.
            - Si la demande implique le web/internet/actualité, utilise prioritairement les blocs [WEB SEARCH] et [SOURCE URL].
            Important:
            - Si une note est marquée "[NOTE ACTIVE PRIORITAIRE]", commence par elle.
            - Si la réponse est dans cette note active, ne dis pas que l'information est absente.
            - Utilise uniquement les informations présentes dans les notes, sauf demande explicite de reformulation/réécriture.
            - Tu peux réorganiser, reformuler et structurer pour améliorer la note.
            - Jamais de balise <think>.
            - Réponds uniquement en JSON valide avec ce schéma strict:
            {
              "answer": "message court pour l'utilisateur",
              "operation": {
                "type": "none|replace|append|list",
                "content": "contenu à appliquer sur la note (vide si none)",
                "title": "titre optionnel pour une liste (sinon vide)"
              },
              "sources": ["uuid1","uuid2"]
            }
            Règles JSON:
            - Si la demande vise à modifier la note, choisis replace, append ou list.
            - Si c'est uniquement une question/réponse, choisis none.
            - Pour type=list, "content" doit contenir uniquement la liste finale (une ligne par élément, sans préface).
            - "sources" doit contenir seulement des UUID présents dans les notes pertinentes.
            - En cas de recherche web, "answer" doit être concret et contenir une mini section "Sources:" avec URLs lisibles.
            - Aucune clé supplémentaire.
            - Action préférée pour cette requête: \(preferredAction).
            \(listRule)
            Si l'information n'est pas présente dans les notes, indique-le dans "answer" et utilise "type":"none".

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
