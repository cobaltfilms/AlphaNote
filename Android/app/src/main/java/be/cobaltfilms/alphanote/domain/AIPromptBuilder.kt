package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.model.Note

/**
 * Constructeur de prompts pour l'assistant IA.
 * Portage fidèle de AI/AIPromptBuilder.swift (macOS).
 *
 * Génère des prompts en français pour les différentes tâches IA.
 */
object AIPromptBuilder {

    /** Prompt système commun à toutes les tâches */
    const val SYSTEM_PROMPT = """
Tu es l'assistant local d'AlphaNote.
Contraintes non négociables:
- Réponds en français clair, utile, précis.
- Reste strictement dans le contexte et les fonctionnalités d'AlphaNote.
- Ne fournis jamais de réflexion interne ni de plan caché.
- Produis un résultat exploitable pour la note (contenu final).
- Respecte strictement la consigne de format quand elle est demandée.
    """.trimIndent()

    /**
     * Construit le prompt pour une tâche spécifique.
     *
     * @param task le type de tâche IA
     * @param note la note concernée
     * @param relatedNotes notes liées pour le contexte (recherche sémantique)
     */
    fun build(
        task: AITask,
        note: Note,
        relatedNotes: List<Note> = emptyList()
    ): String {
        val title = note.effectiveTitle
        val content = note.content.take(6000)

        return when (task) {
            AITask.SUMMARIZE -> buildSummarize(title, content)
            is AITask.REWRITE -> buildRewrite(title, content, task.style)
            AITask.EXTRACT_ACTIONS -> buildExtractActions(title, content)
            AITask.MODE_ROUTING -> buildModeRouting(content, note.keyword)
            is AITask.SEMANTIC_ANSWER -> buildSemanticAnswer(content, relatedNotes)
        }
    }

    private fun buildSummarize(title: String, content: String): String = """
Tâche: Résumer cette note.
Contraintes:
- 5 puces maximum.
- Garde seulement l'essentiel.
- N'invente rien.

Titre: $title
Contenu:
$content
    """.trimIndent()

    private fun buildRewrite(title: String, content: String, style: String): String = """
Tâche: Réécrire la note dans un style $style.
Contraintes:
- Préserver les faits et les décisions.
- Corriger les fautes.
- Ne pas ajouter d'informations non présentes.

Titre: $title
Contenu:
$content
    """.trimIndent()

    private fun buildExtractActions(title: String, content: String): String = """
Tâche: Extraire les actions concrètes de cette note.
Réponds uniquement en JSON valide avec ce schéma:
{"actions":[{"title":"...","owner":"...","deadline":"...","priority":"low|medium|high"}]}

Règles:
- Si une donnée manque, mets une chaîne vide.
- Aucune clé supplémentaire.
- Si aucune action: {"actions":[]}

Titre: $title
Contenu:
$content
    """.trimIndent()

    private fun buildModeRouting(content: String, noteKeyword: String): String = """
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
- Priorité du mode courant de la note (si fourni): ${noteKeyword.ifEmpty { "aucun" }}.
- Aucune clé supplémentaire.

Requête:
$content
    """.trimIndent()

    private fun buildSemanticAnswer(content: String, relatedNotes: List<Note>): String {
        val relatedBlock = if (relatedNotes.isEmpty()) {
            "- (aucune note fournie)"
        } else {
            relatedNotes.take(5).joinToString("\n") { note ->
                "- [${note.uuid}] ${note.effectiveTitle}: ${note.content.take(700)}"
            }
        }

        val wantsList = KeywordDetector.isExplicitListRequest(content) ||
            KeywordDetector.isListRefinementRequest(content)
        val asksQuantity = KeywordDetector.asksForQuantityDetails(content)
        val wantsTransformation = KeywordDetector.isNoteTransformationRequest(content)
        val wantsWebResearch = KeywordDetector.isWebResearchRequest(content)

        val preferredAction = when {
            wantsList -> "list"
            wantsWebResearch -> "append"
            wantsTransformation -> "replace"
            else -> "none"
        }

        val listRule = if (asksQuantity) {
            "Si l'utilisateur demande des quantités, ajoute une quantité explicite à chaque ligne de liste."
        } else {
            "Quand tu produis une liste, un élément par ligne."
        }

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
- Jamais de balise  thinking.
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
- Action préférée pour cette requête: $preferredAction.
$listRule
Si l'information n'est pas présente dans les notes, indique-le dans "answer" et utilise "type":"none".

Question:
$content

Notes pertinentes:
$relatedBlock
        """.trimIndent()
    }
}

/** Types de tâches que l'assistant IA peut effectuer */
sealed class AITask {
    /** Résumer une note */
    data object SUMMARIZE : AITask()

    /** Réécrire une note dans un style donné */
    data class REWRITE(val style: String) : AITask()

    /** Extraire les actions concrètes */
    data object EXTRACT_ACTIONS : AITask()

    /** Router vers le bon mode */
    data object MODE_ROUTING : AITask()

    /** Réponse sémantique basée sur les notes liées */
    data object SEMANTIC_ANSWER : AITask()
}
