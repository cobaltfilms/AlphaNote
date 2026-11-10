package be.cobaltfilms.alphanote.ai

import be.cobaltfilms.alphanote.domain.NoteOrganizer
import be.cobaltfilms.alphanote.domain.NoteThemes
import be.cobaltfilms.alphanote.model.Note

/**
 * Rangement par rayon à la JEV : le serveur de décision CLASSE chaque note
 * dans un rayon selon un schéma strict, il ne rédige rien. Port de
 * AI/Features/ThemeClassificationFeature.swift.
 *
 * Uniquement à la demande (« Ranger avec JEV ») : c'est le seul endroit où le
 * **contenu** de notes part vers le serveur (titre et début du texte). Une note
 * sécurisée ne part jamais, une note qui a déjà un thème écrit non plus. Une
 * réponse manquante ou « fourre_tout » laisse la note sans thème : pas de
 * classement forcé.
 */
object ThemeClassificationFeature {
    /** [theme] : nom écrit dans la note (`thème : …`). Null : la note n'est pas rangée. */
    class Shelf(val choice: String, val theme: String?, val description: String)

    /**
     * Les rayons, décrits en phrases : c'est la description qui fait la
     * qualité de la réponse. Mêmes noms que le catalogue local (`ThemeSorter`).
     */
    val shelves: List<Shelf> = listOf(
        Shelf("informatique", "Informatique",
            "commandes de terminal, serveurs, réseau, NAS, Linux, Docker, code, journaux d'erreurs, matériel d'ordinateur, numéros de série et licences de logiciels"),
        Shelf("image_et_son", "Image & son",
            "cinéma, tournage, montage, étalonnage, DaVinci Resolve, DCP, mastering, caméras, écrans, son, films"),
        Shelf("argent_et_papiers", "Argent & papiers",
            "factures, banque, TVA, impôts, contrats, clients, démarches administratives, candidatures, attestations"),
        Shelf("vie_perso", "Vie perso",
            "famille, enfants, santé, maison, voyages, trajets, sorties, cadeaux, réflexions personnelles, lectures"),
        Shelf("cuisine", "Cuisine",
            "recettes, ingrédients, courses alimentaires"),
        Shelf("fourre_tout", null,
            "note trop courte ou trop vague pour être rangée (un mot, un lien seul, un minuteur, des chiffres sans contexte)"),
    )

    const val instructions = """Tu classes une note personnelle (français ou anglais) dans un seul rayon.
Réponds uniquement selon le schéma, sans rédiger. En cas de doute, fourre_tout."""

    val rayonField = JEVField.Str(
        choices = shelves.map { it.choice },
        description = "Le rayon où ranger la note. " + shelves.joinToString(". ") { "${it.choice} = ${it.description}" } + "."
    )

    val schema: JEVSchema get() = mapOf("rayon" to rayonField)

    /** Longueur de texte envoyée par note. */
    const val EXCERPT_LENGTH = 700
    const val BATCH_SIZE = 8

    /** Notes à proposer au serveur : ni sécurisées, ni déjà rangées à la main, ni vides. */
    fun candidates(notes: List<Note>): List<Note> = notes.filter { note ->
        !note.isVault && !note.isDeleted && NoteThemes.explicit(note.content) == null &&
            NoteOrganizer.meaningfulLines(note).isNotEmpty()
    }

    /** Ce qui part au serveur pour une note : son titre, puis le début du texte utile. */
    fun fragment(note: Note): String {
        val text = NoteThemes.classifiableText(note.title, note.content)
        val title = note.title.trim()
        val body = NoteThemes.prefix(text.body.trim(), EXCERPT_LENGTH)
        return if (title.isEmpty()) body else title + "\n" + body
    }

    data class Outcome(
        /** uuid → thème décidé par le serveur. */
        val themes: Map<String, String> = emptyMap(),
        /** Notes que le serveur a laissées au fourre-tout. */
        val unsorted: Int = 0,
        /** Notes sans réponse exploitable. */
        val failed: Int = 0,
        /** Message de la première erreur de transport, s'il y en a eu une. */
        val error: String? = null
    )

    /**
     * Classe les notes par lots. Une erreur de serveur arrête tout de suite :
     * ce qui est déjà décidé est rendu, le reste compte comme échec.
     */
    suspend fun classify(
        notes: List<Note>,
        config: JEVConfig,
        transport: JEVTransport = OkHttpJEVTransport,
        progress: suspend (done: Int, total: Int) -> Unit = { _, _ -> }
    ): Outcome {
        val themes = LinkedHashMap<String, String>()
        var unsorted = 0
        var failed = 0
        val byChoice = shelves.associateBy { it.choice }
        var index = 0
        while (index < notes.size) {
            val batch = notes.subList(index, minOf(index + BATCH_SIZE, notes.size))
            when (val result = JEVClient.decider(config, instructions, schema, batch.map(::fragment), transport)) {
                is JEVOutcome.Erreur -> return Outcome(themes, unsorted, failed + notes.size - index, result.message)
                is JEVOutcome.Ok -> for ((note, decision) in batch.zip(result.value)) {
                    val shelf = (decision["rayon"] as? JEVValue.Str)?.let { byChoice[it.value] }
                    when {
                        shelf == null -> failed++
                        shelf.theme != null -> themes[note.uuid] = shelf.theme
                        else -> unsorted++
                    }
                }
            }
            index += batch.size
            progress(index, notes.size)
        }
        return Outcome(themes, unsorted, failed)
    }
}
