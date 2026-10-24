package be.cobaltfilms.alphanote.domain

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.util.concurrent.TimeUnit

/**
 * Lit la liste d'ingrédients d'une page de recette, sans IA — port de
 * Services/RecipeIngredientExtractor.swift. La plupart des sites publient la
 * recette en données structurées schema.org (`recipeIngredient`, JSON-LD ou
 * microdonnées) ; une page qui n'en publie pas est un échec franc.
 */
object RecipeIngredientExtractor {

    data class Recipe(val title: String?, val ingredients: List<String>)

    sealed class Failure(val message: String) {
        class Http(status: Int) : Failure("la page répond HTTP $status")
        object Unreadable : Failure("page illisible")
        object NoStructuredRecipe : Failure("aucune liste d'ingrédients structurée sur la page")
    }

    sealed class Outcome {
        data class Ok(val recipe: Recipe) : Outcome()
        data class Ko(val failure: Failure) : Outcome()
    }

    const val MAX_INGREDIENTS = 60

    private val URL_PATTERN = Regex("""(?i)\bhttps?://[^\s<>()"]+|\bwww\.[^\s<>()"]+""")

    /** Premier lien http(s) de la demande (« www. » complété en https). */
    fun firstUrl(text: String): String? {
        val raw = URL_PATTERN.find(text)?.value?.trimEnd('.', ',', ';', ':', '!', '?', ')', ']', '}', '"') ?: return null
        return if (raw.lowercase().startsWith("www.")) "https://$raw" else raw
    }

    // ---- Réseau ----

    suspend fun fetch(url: String, timeoutMs: Long = 15_000): Outcome = withContext(Dispatchers.IO) {
        val client = OkHttpClient.Builder()
            .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .build()
        val request = try {
            Request.Builder().url(url)
                // Certains sites refusent les clients sans User-Agent de navigateur.
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36")
                .header("Accept", "text/html,application/xhtml+xml")
                .header("Accept-Language", "fr,en;q=0.8")
                .build()
        } catch (_: IllegalArgumentException) {
            return@withContext Outcome.Ko(Failure.Unreadable)
        }
        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext Outcome.Ko(Failure.Http(response.code))
                val html = response.body?.string() ?: return@withContext Outcome.Ko(Failure.Unreadable)
                val recipe = extract(html) ?: return@withContext Outcome.Ko(Failure.NoStructuredRecipe)
                Outcome.Ok(recipe)
            }
        } catch (_: Exception) {
            Outcome.Ko(Failure.Unreadable)
        }
    }

    // ---- Analyse (pure) ----

    fun extract(html: String): Recipe? = extractFromJsonLd(html) ?: extractFromMicrodata(html)

    private val JSON_LD = Regex(
        """<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>(.*?)</script>""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )

    private fun extractFromJsonLd(html: String): Recipe? {
        for (match in JSON_LD.findAll(html)) {
            val parsed = try {
                JSONTokener(match.groupValues[1].trim()).nextValue()
            } catch (_: Exception) {
                continue
            }
            findRecipe(parsed)?.let { return it }
        }
        return null
    }

    /** Parcourt le JSON-LD (objets, tableaux, `@graph`) jusqu'au premier `Recipe` qui porte des ingrédients. */
    private fun findRecipe(value: Any?): Recipe? {
        when (value) {
            is JSONArray -> {
                for (i in 0 until value.length()) findRecipe(value.opt(i))?.let { return it }
                return null
            }
            is JSONObject -> {
                if (isRecipeType(value.opt("@type"))) {
                    val raw = (value.opt("recipeIngredient") ?: value.opt("ingredients")) as? JSONArray
                    val items = clean((0 until (raw?.length() ?: 0)).mapNotNull { raw?.opt(it) as? String })
                    if (items.isNotEmpty()) {
                        val title = (value.opt("name") as? String)?.let(::cleanText)?.takeIf { it.isNotEmpty() }
                        return Recipe(title, items)
                    }
                }
                for (key in value.keys()) findRecipe(value.opt(key))?.let { return it }
                return null
            }
            else -> return null
        }
    }

    private fun isRecipeType(value: Any?): Boolean = when (value) {
        is String -> value.lowercase().endsWith("recipe")
        is JSONArray -> (0 until value.length()).any { (value.opt(it) as? String)?.lowercase()?.endsWith("recipe") == true }
        else -> false
    }

    private val MICRODATA_META = Regex(
        """<meta[^>]*itemprop\s*=\s*["']recipeIngredient["'][^>]*content\s*=\s*["']([^"']*)["']""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )
    private val MICRODATA_ELEMENT = Regex(
        """<(\w+)[^>]*itemprop\s*=\s*["']recipeIngredient["'][^>]*>(.*?)</\1>""",
        setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
    )

    private fun extractFromMicrodata(html: String): Recipe? {
        val items = MICRODATA_META.findAll(html).map { it.groupValues[1] }.toList() +
            MICRODATA_ELEMENT.findAll(html).map { it.groupValues[2] }.toList()
        val cleaned = clean(items)
        return if (cleaned.isEmpty()) null else Recipe(null, cleaned)
    }

    // ---- Nettoyage ----

    private fun clean(items: List<String>): List<String> {
        val seen = HashSet<String>()
        val result = mutableListOf<String>()
        for (item in items) {
            val text = cleanText(item)
            if (text.isEmpty() || !seen.add(text.lowercase())) continue
            result += text
            if (result.size == MAX_INGREDIENTS) break
        }
        return result
    }

    fun cleanText(raw: String): String =
        decodeEntities(raw.replace(Regex("<[^>]+>"), " "))
            .replace(Regex("\\s+"), " ")
            .trim()

    private val NAMED_ENTITIES = mapOf(
        "amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ",
        "eacute" to "é", "egrave" to "è", "ecirc" to "ê", "euml" to "ë", "agrave" to "à",
        "acirc" to "â", "ccedil" to "ç", "icirc" to "î", "iuml" to "ï", "ocirc" to "ô",
        "ucirc" to "û", "ugrave" to "ù", "oelig" to "œ", "deg" to "°", "frac12" to "½",
        "frac14" to "¼", "frac34" to "¾", "rsquo" to "’", "lsquo" to "‘", "hellip" to "…",
        "times" to "×"
    )
    private val ENTITY = Regex("&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z0-9]+);")

    fun decodeEntities(text: String): String {
        if (!text.contains('&')) return text
        return ENTITY.replace(text) { match ->
            val entity = match.groupValues[1]
            val code = when {
                entity.startsWith("#x") || entity.startsWith("#X") -> entity.drop(2).toIntOrNull(16)
                entity.startsWith("#") -> entity.drop(1).toIntOrNull()
                else -> null
            }
            when {
                code != null && Character.isValidCodePoint(code) -> String(Character.toChars(code))
                code != null -> match.value
                else -> NAMED_ENTITIES[entity.lowercase()] ?: match.value
            }
        }
    }
}
