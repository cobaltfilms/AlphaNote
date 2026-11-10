package be.cobaltfilms.alphanote.domain

import be.cobaltfilms.alphanote.model.Note
import java.text.BreakIterator
import java.text.Normalizer
import kotlin.math.ln
import kotlin.math.sqrt

/**
 * Thème d'une note, pour ranger la liste par sujets.
 *
 * Un thème choisi est une ligne du texte, comme un rappel :
 *
 *     thème : Recettes
 *
 * Le texte se synchronise tel quel, donc le thème aussi, sans champ en plus.
 * Même format et mêmes règles que la version Apple (`Models/NoteThemes.swift`).
 *
 * Une note sans cette ligne reçoit un thème **proposé**, calculé sur l'appareil
 * ([ThemeSorter]) : jamais écrit dans la note, jamais envoyé sur le réseau.
 */
object NoteThemes {
    /** Section des notes qu'aucune règle ne range. */
    const val NONE = "Sans thème"
    const val MAX_LENGTH = 40

    private val line = Regex("""^\s*th[eè]me\s*:\s*(.+?)\s*$""", RegexOption.IGNORE_CASE)
    private val marks = Regex("\\p{Mn}+")

    fun isThemeLine(raw: String): Boolean = line.find(raw) != null

    /** Thème écrit dans la note (dernière ligne « thème : … »), sinon null. */
    fun explicit(content: String): String? {
        for (raw in content.split("\n").asReversed()) {
            val match = line.find(raw) ?: continue
            val name = normalized(match.groupValues[1])
            if (name.isNotEmpty()) return name
        }
        return null
    }

    /** Nom présentable : espaces resserrés, longueur bornée. */
    fun normalized(name: String): String {
        val collapsed = name.split(' ', '\t', '\n', '\r', '\u000B', '\u000C', '\u0085', ' ', ' ')
            .filter { it.isNotEmpty() }.joinToString(" ")
        return trimSpaces(prefix(collapsed, MAX_LENGTH))
    }

    /** Clé de comparaison : « Recettes », « recettes » et « RECETTES » sont un seul thème. */
    fun key(name: String): String = fold(normalized(name))

    fun removingTheme(content: String): String =
        content.split("\n").filterNot(::isThemeLine).joinToString("\n")

    /**
     * Écrit (ou retire, si [theme] est null ou vide) la ligne de thème. Elle se
     * place en fin de texte, avant les pièces jointes qui ferment la note.
     */
    fun settingTheme(theme: String?, content: String): String {
        val lines = removingTheme(content).split("\n").toMutableList()
        val name = theme?.let(::normalized).orEmpty()
        if (name.isEmpty()) return lines.joinToString("\n")

        val tail = mutableListOf<String>()
        while (lines.isNotEmpty()) {
            val last = lines.last()
            val isAttachment = NoteAttachments.isImageLine(last)
            if (!isAttachment && trimSpaces(last).isNotEmpty()) break
            if (isAttachment) tail.add(0, last)
            lines.removeAt(lines.lastIndex)
        }
        lines.add("thème : $name")
        return (lines + tail).joinToString("\n")
    }

    /** Texte utile au classement : sans en-tête de mode, thème, rappels ni pièces jointes. */
    fun classifiableText(title: String, content: String): ClassifiableText {
        val lines = content.split("\n").filterNot {
            isThemeLine(it) || NoteAttachments.isImageLine(it) || trimSpaces(it).lowercase().startsWith("rappel ")
        }.toMutableList()
        val header = lines.firstOrNull()?.let(::trimSpaces)
        if (header != null && isModeHeader(header)) {
            lines.removeAt(0)
            // « list: courses » : ce qui suit le mot-clé sert de titre.
            val colon = header.indexOf(':')
            if (colon >= 0) lines.add(0, header.substring(colon + 1))
        }
        val explicitTitle = title.trim()
        val firstLine = lines.firstOrNull { trimSpaces(it).isNotEmpty() }.orEmpty()
        return ClassifiableText(explicitTitle.ifEmpty { firstLine }, lines.joinToString("\n"))
    }

    data class ClassifiableText(val title: String, val body: String)

    // ---- Sections de la liste ----

    data class Section(val theme: String, val noteUuids: List<String>)

    /**
     * Notes regroupées par thème, dans l'ordre reçu à l'intérieur d'un thème.
     * Thèmes par ordre alphabétique, « Sans thème » en dernier.
     */
    fun sections(noteUuids: List<String>, themes: Map<String, String>): List<Section> {
        val names = LinkedHashMap<String, String>()
        val members = HashMap<String, MutableList<String>>()
        for (uuid in noteUuids) {
            val name = themes[uuid] ?: NONE
            val themeKey = key(name)
            if (themeKey !in names) names[themeKey] = name
            members.getOrPut(themeKey) { mutableListOf() }.add(uuid)
        }
        val noneKey = key(NONE)
        val sorted = names.keys.filter { it != noneKey }.sorted() + (if (noneKey in names) listOf(noneKey) else emptyList())
        return sorted.map { Section(names[it] ?: NONE, members[it].orEmpty()) }
    }

    /** Thèmes présents (une seule orthographe par clé), par ordre alphabétique. */
    fun distinctNames(themes: Collection<String>): List<String> {
        val seen = HashMap<String, String>()
        // Parcours trié : l'orthographe gardée ne dépend pas de l'ordre de la carte.
        for (name in themes.sorted()) seen.getOrPut(key(name)) { name }
        return seen.keys.sorted().mapNotNull { seen[it] }
    }

    // ---- Outils de texte (mêmes règles que Foundation côté Apple) ----

    /** Minuscules, sans accents. */
    internal fun fold(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(marks, "").lowercase()

    /** Espaces et tabulations en bord de chaîne (pas les retours à la ligne). */
    internal fun trimSpaces(text: String): String =
        text.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }

    /** Les [count] premiers caractères affichés (un emoji compte pour un). */
    internal fun prefix(text: String, count: Int): String {
        if (text.length <= count) return text
        val iterator = BreakIterator.getCharacterInstance().apply { setText(text) }
        var end = 0
        repeat(count) {
            val next = iterator.next()
            if (next == BreakIterator.DONE) return text
            end = next
        }
        return text.substring(0, end)
    }

    /** Nombre de caractères affichés (comme `count` côté Apple : un emoji compte pour un). */
    internal fun count(text: String): Int {
        val iterator = BreakIterator.getCharacterInstance().apply { setText(text) }
        var total = 0
        while (iterator.next() != BreakIterator.DONE) total++
        return total
    }

    /** Même règle que l'éditeur (`EditorDecorations.isModeHeader`), sans dépendre de l'interface. */
    internal fun isModeHeader(trimmed: String): Boolean {
        val lower = trimmed.lowercase()
        return lower in Note.knownKeywords || Note.knownKeywords.any { lower.startsWith("$it:") }
    }
}

/**
 * Classement local et déterministe des notes par thème — aucune IA, aucun
 * réseau, même résultat sur chaque appareil (port de `ThemeSorter` côté Apple).
 *
 * Pour une note sans thème écrit, dans l'ordre :
 * 1. **par l'exemple** : elle ressemble (mots pondérés TF-IDF, cosinus) aux
 *    notes qui portent déjà un thème écrit — ranger quelques notes à la main
 *    apprend le thème aux autres ;
 * 2. **par le vocabulaire** : un catalogue de thèmes courants, chacun avec ses
 *    mots (français et anglais) ;
 * 3. **par la forme** : une note en mode `code`, ou faite surtout de lignes de
 *    terminal ou de code, va dans « Informatique » ;
 * 4. sinon elle reste « Sans thème » : pas de classement forcé.
 */
object ThemeSorter {
    data class Item(val uuid: String, val title: String, val content: String, val keyword: String)

    /** Ressemblance minimale avec les notes d'un thème pour le rejoindre. */
    const val EXAMPLE_THRESHOLD = 0.22
    /**
     * Points du catalogue à réunir : un mot compte 1, un mot du titre 2. Trois
     * points = trois mots, ou un mot du titre et un autre : un seul mot ne suffit pas.
     */
    const val CATALOG_THRESHOLD = 3
    /** Part des lignes « de terminal ou de code » qui fait une note technique. */
    const val CODE_LINE_SHARE = 0.4

    private class Prepared(val item: Item, val title: List<String>, val body: List<String>, val explicit: String?)
    private class Example(val name: String, val vectors: MutableList<Map<String, Double>> = mutableListOf())

    /** uuid → thème (écrit ou proposé). Une note absente n'a pas de thème. */
    fun assign(items: List<Item>): Map<String, String> {
        val result = HashMap<String, String>()
        val pending = mutableListOf<Prepared>()
        val examples = HashMap<String, Example>()

        val prepared = items.map { item ->
            val text = NoteThemes.classifiableText(item.title, item.content)
            Prepared(item, tokens(text.title), tokens(text.body), NoteThemes.explicit(item.content))
        }

        // Fréquence documentaire sur toutes les notes.
        val documentFrequency = HashMap<String, Int>()
        for (entry in prepared) {
            for (token in (entry.title + entry.body).toSet()) documentFrequency[token] = (documentFrequency[token] ?: 0) + 1
        }
        val count = prepared.size.toDouble()
        fun vector(title: List<String>, body: List<String>): Map<String, Double> {
            val weights = HashMap<String, Double>()
            for (token in body) weights[token] = (weights[token] ?: 0.0) + 1
            for (token in title) weights[token] = (weights[token] ?: 0.0) + 1
            for ((token, frequency) in weights.entries.toList()) {
                val idf = ln((count + 1) / ((documentFrequency[token] ?: 0) + 1.0)) + 1
                weights[token] = (1 + ln(frequency)) * idf
            }
            return normalize(weights)
        }

        for (entry in prepared) {
            val explicit = entry.explicit
            if (explicit != null) {
                result[entry.item.uuid] = explicit
                examples.getOrPut(NoteThemes.key(explicit)) { Example(explicit) }.vectors.add(vector(entry.title, entry.body))
            } else {
                pending.add(entry)
            }
        }

        // Centre de chaque thème appris, dans un ordre stable.
        val centroids = examples.keys.sorted().map { themeKey ->
            val entry = examples.getValue(themeKey)
            val sum = HashMap<String, Double>()
            for (vector in entry.vectors) {
                for ((token, weight) in vector) sum[token] = (sum[token] ?: 0.0) + weight
            }
            entry.name to normalize(sum)
        }

        for (entry in pending) {
            if (entry.title.isEmpty() && entry.body.isEmpty()) continue
            val own = vector(entry.title, entry.body)
            var bestName: String? = null
            var bestScore = 0.0
            for ((name, centroid) in centroids) {
                val score = dot(own, centroid)
                if (score >= EXAMPLE_THRESHOLD && score > bestScore) { bestName = name; bestScore = score }
            }
            val catalogName = if (bestName == null) catalogTheme(entry.title, entry.body) else null
            when {
                bestName != null -> result[entry.item.uuid] = bestName
                // Un thème appris du même nom garde son orthographe.
                catalogName != null -> result[entry.item.uuid] = examples[NoteThemes.key(catalogName)]?.name ?: catalogName
                entry.item.keyword == "code" || looksLikeCode(entry.item.content) -> result[entry.item.uuid] = examples[NoteThemes.key(CODE_THEME)]?.name ?: CODE_THEME
            }
        }
        return result
    }

    /** Thème du catalogue pour un texte seul (sans apprentissage par l'exemple). */
    fun catalogTheme(title: String, content: String): String? {
        val text = NoteThemes.classifiableText(title, content)
        return catalogTheme(tokens(text.title), tokens(text.body))
    }

    private fun catalogTheme(title: List<String>, body: List<String>): String? {
        val titleSet = title.toSet()
        val all = titleSet + body
        var bestName: String? = null
        var bestScore = 0
        for (theme in catalog) {
            var score = 0
            for (word in theme.words) if (word in all) score += if (word in titleSet) 2 else 1
            if (score >= CATALOG_THRESHOLD && score > bestScore) { bestName = theme.name; bestScore = score }
        }
        return bestName
    }

    // ---- Forme ----

    private val codeLine = Regex(
        """^\s*[$#>]\s|\s--?[a-z][a-z0-9-]+|/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+|[{};]\s*$|[A-Za-z_]+\(.*\)|^\s*[A-Za-z_]+=\S|\[[ 0-9.:]+\]|\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"""
    )

    /**
     * Vrai quand au moins deux lignes, et [CODE_LINE_SHARE] des lignes non vides,
     * ont l'allure d'une commande, d'un journal ou de code.
     */
    fun looksLikeCode(content: String): Boolean {
        val lines = content.split("\n").filter {
            NoteThemes.trimSpaces(it).isNotEmpty() && !NoteThemes.isThemeLine(it) && !NoteAttachments.isImageLine(it)
        }
        if (lines.size < 2) return false
        val matching = lines.count { codeLine.containsMatchIn(it) }
        return matching >= 2 && matching.toDouble() >= lines.size * CODE_LINE_SHARE
    }

    // ---- Mots ----

    /**
     * Mots utiles : minuscules, sans accents, 3 lettres au moins, pluriels
     * simples ramenés au singulier, mots vides retirés.
     */
    fun tokens(text: String): List<String> {
        val words = mutableListOf<String>()
        val current = StringBuilder()
        fun close() {
            if (current.isEmpty()) return
            val word = current.toString()
            current.setLength(0)
            val stemmed = stem(word)
            if (stemmed.length >= 3 && word !in stopWords && stemmed !in stopWords) words.add(stemmed)
        }
        for (char in NoteThemes.fold(text)) {
            if (char.isLetter()) current.append(char) else close()
        }
        close()
        return words
    }

    fun stem(word: String): String =
        if (word.length > 3 && (word.last() == 's' || word.last() == 'x')) word.dropLast(1) else word

    private fun normalize(vector: Map<String, Double>): Map<String, Double> {
        // Somme dans l'ordre des clés : la même norme à chaque calcul.
        val norm = sqrt(vector.keys.sorted().fold(0.0) { sum, token -> sum + vector.getValue(token) * vector.getValue(token) })
        if (norm <= 0) return vector
        return vector.mapValues { it.value / norm }
    }

    private fun dot(lhs: Map<String, Double>, rhs: Map<String, Double>): Double {
        val (small, large) = if (lhs.size <= rhs.size) lhs to rhs else rhs to lhs
        // Somme dans un ordre stable : le même score sur chaque appareil.
        return small.keys.sorted().fold(0.0) { sum, token -> sum + (small[token] ?: 0.0) * (large[token] ?: 0.0) }
    }

    // ---- Catalogue ----

    class CatalogTheme(val name: String, words: String) {
        val words: Set<String> = tokens(words).toSet()
    }

    const val CODE_THEME = "Informatique"

    val stopWords: Set<String> = setOf(
        "les", "des", "une", "est", "pour", "que", "qui", "dans", "sur", "pas", "plus", "par", "avec", "son",
        "ses", "aux", "mes", "tes", "nos", "vos", "leur", "mon", "ton", "notre", "votre", "cette", "ces",
        "elle", "ils", "elles", "nous", "vous", "mais", "donc", "car", "comme", "tout", "tous", "toute",
        "etre", "avoir", "fait", "faire", "sont", "ont", "ete", "aussi", "tres", "bien", "sans", "sous",
        "entre", "vers", "chez", "puis", "alors", "quand", "dont", "cela", "ceci", "celui", "celle",
        "the", "and", "for", "that", "with", "this", "from", "are", "was", "were", "have", "has", "had",
        "not", "but", "you", "your", "they", "them", "their", "will", "would", "can", "could", "should",
        "what", "when", "where", "which", "who", "how", "all", "any", "its", "our", "out", "about", "into",
        "http", "https", "www", "com",
    )

    /**
     * Les rayons : peu nombreux et larges, les mêmes que ceux proposés au
     * serveur JEV (`ThemeClassificationFeature`). L'ordre départage les égalités.
     */
    val catalog: List<CatalogTheme> = listOf(
        CatalogTheme("Cuisine",
            "recette ingredient cuisson four farine beurre sucre oeuf levure oignon ail creme cuillere gramme " +
            "prechauffer melanger cuire poele casserole sauce gateau tarte soupe poulet mijoter eplucher hacher " +
            "marinade dessert plat entree vinaigrette bouillon recipe bake flour butter sugar cook oven tablespoon " +
            "teaspoon simmer ingredients courses supermarche panier delhaize colruyt carrefour lidl aldi " +
            "groceries epicerie pain fromage legume fruit yaourt boucherie boulangerie"),
        CatalogTheme("Image & son",
            "tournage montage camera rush etalonnage davinci timeline scenario storyboard casting cadrage codec " +
            "prores lut dcp trepied drone focale diaphragme realisateur monteur etalonneur shooting footage " +
            "grading mixage generique mastering"),
        CatalogTheme("Argent & papiers",
            "banque iban virement facture impot tva salaire budget depense remboursement pret credit loyer " +
            "assurance paiement comptable comptabilite fiscal epargne invoice tax bank payment montant solde " +
            "echeance mensualite devis contrat client prestataire fournisseur administration commune formulaire " +
            "attestation certificat permis immatriculation notaire avocat identite declaration guichet " +
            "prefecture mairie justificatif"),
        CatalogTheme("Vie perso",
            "medecin docteur ordonnance medicament pharmacie dentiste hopital symptome vaccin mutuelle kine " +
            "voyage vol avion train hotel reservation billet valise passeport itineraire aeroport airbnb " +
            "vacances camping randonnee musee plage maison appartement travaux peinture plombier electricien " +
            "meuble jardin demenagement bricolage ikea chauffage livre serie podcast album musique roman " +
            "cinema concert exposition spectacle theatre cadeau anniversaire noel fete mariage naissance " +
            "famille ecole enfant"),
        CatalogTheme(CODE_THEME,
            "serveur server ssh docker git python swift kotlin script api bug linux terminal install config " +
            "database sql json token regex compile build deploy backup nas routeur dns javascript html css " +
            "function variable kernel sudo bash kubectl compose container snapshot proxmox nginx yaml npm pip " +
            "curl chmod mount ubuntu debian driver gpu nvidia cuda dataset error failed systemctl daemon " +
            "firmware firewall vlan subnet localhost password login identifiant wifi username licence serial"),
    )
}
