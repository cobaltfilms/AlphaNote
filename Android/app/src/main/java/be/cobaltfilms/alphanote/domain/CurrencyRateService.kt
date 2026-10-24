package be.cobaltfilms.alphanote.domain

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Taux de change : cache synchrone (mémoire + SharedPreferences, 1 h) et
 * rafraîchissement asynchrone. Port de Evaluation/CurrencyRateService.swift.
 * Une conversion dont le taux manque retourne null et déclenche un
 * téléchargement en arrière-plan, puis émet sur [ratesUpdated].
 *
 * Sources (sans clé d'API) : Frankfurter (BCE) puis open.er-api.com en repli.
 */
class CurrencyRateService(private val persists: Boolean = true) {

    data class Snapshot(val base: String, val fetchedAt: Long, val rates: Map<String, Double>)

    private val lock = Any()
    private val snapshots = mutableMapOf<String, Snapshot>()
    private val inFlight = mutableSetOf<String>()
    private var prefs: SharedPreferences? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _ratesUpdated = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val ratesUpdated: SharedFlow<Unit> = _ratesUpdated

    /** Transport injectable pour les tests : URL → corps de réponse (ou null). */
    var fetcher: (String) -> String? = { url ->
        val client = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()
        client.newCall(Request.Builder().url(url).get().build()).execute().use { response ->
            if (response.isSuccessful) response.body?.string() else null
        }
    }

    /** Active la persistance (à appeler une fois, depuis l'Application). */
    fun attach(context: Context) {
        if (!persists) return
        prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        loadFromPrefs()
    }

    /** Taux `from → to` s'il est en cache ; sinon null et rafraîchissement lancé. */
    fun rate(from: String, to: String): Double? {
        val base = from.uppercase()
        val quote = to.uppercase()
        if (base == quote) return 1.0

        val snapshot = synchronized(lock) { snapshots[base] }
        if (snapshot != null && System.currentTimeMillis() - snapshot.fetchedAt < MAX_AGE_MS) {
            return snapshot.rates[quote]
        }
        requestRefresh(base)
        return snapshot?.rates?.get(quote) // un taux périmé vaut mieux que rien
    }

    fun knowsCurrency(code: String): Boolean {
        val upper = code.uppercase()
        return synchronized(lock) {
            snapshots.containsKey(upper) || snapshots.values.any { it.rates.containsKey(upper) }
        }
    }

    fun requestRefresh(base: String) {
        val upper = base.uppercase()
        val alreadyRunning = synchronized(lock) {
            if (inFlight.contains(upper)) true else { inFlight.add(upper); false }
        }
        if (alreadyRunning) return
        scope.launch { refresh(upper) }
    }

    /** Rafraîchit de façon synchrone (appelé depuis une coroutine IO ou un test). */
    fun refresh(base: String): Snapshot? {
        try {
            for (provider in PROVIDERS) {
                val body = try { fetcher(provider.url(base)) } catch (_: Exception) { null } ?: continue
                val rates = provider.parse(body) ?: continue
                if (rates.isEmpty()) continue
                val snapshot = Snapshot(base, System.currentTimeMillis(), rates)
                store(snapshot)
                _ratesUpdated.tryEmit(Unit)
                return snapshot
            }
            return null
        } finally {
            synchronized(lock) { inFlight.remove(base) }
        }
    }

    /** Pour les tests : injecte un instantané sans réseau. */
    fun seed(base: String, rates: Map<String, Double>, fetchedAt: Long = System.currentTimeMillis()) {
        store(Snapshot(base.uppercase(), fetchedAt, rates))
    }

    private fun store(snapshot: Snapshot) {
        val all = synchronized(lock) {
            snapshots[snapshot.base] = snapshot
            snapshots.toMap()
        }
        prefs?.edit()?.putString(KEY_CACHE, encode(all))?.apply()
    }

    private fun loadFromPrefs() {
        val raw = prefs?.getString(KEY_CACHE, null) ?: return
        val decoded = try { decode(raw) } catch (_: Exception) { return }
        synchronized(lock) { snapshots.putAll(decoded) }
    }

    private fun encode(all: Map<String, Snapshot>): String {
        val root = JSONObject()
        all.forEach { (base, snapshot) ->
            val rates = JSONObject()
            snapshot.rates.forEach { (code, rate) -> rates.put(code, rate) }
            root.put(base, JSONObject().put("fetchedAt", snapshot.fetchedAt).put("rates", rates))
        }
        return root.toString()
    }

    private fun decode(raw: String): Map<String, Snapshot> {
        val root = JSONObject(raw)
        val result = mutableMapOf<String, Snapshot>()
        root.keys().forEach { base ->
            val obj = root.getJSONObject(base)
            val ratesObj = obj.getJSONObject("rates")
            val rates = mutableMapOf<String, Double>()
            ratesObj.keys().forEach { code -> rates[code] = ratesObj.getDouble(code) }
            result[base] = Snapshot(base, obj.getLong("fetchedAt"), rates)
        }
        return result
    }

    class Provider(val url: (String) -> String, val parse: (String) -> Map<String, Double>?)

    companion object {
        val shared = CurrencyRateService()

        private const val PREFS_NAME = "alphanote_currency_rates"
        private const val KEY_CACHE = "currencyRatesCacheV2"
        private const val MAX_AGE_MS = 3_600_000L

        val PROVIDERS: List<Provider> = listOf(
            Provider(
                url = { "https://api.frankfurter.app/latest?from=$it" },
                parse = { body -> parseRates(body, requireSuccess = false) }
            ),
            Provider(
                url = { "https://open.er-api.com/v6/latest/$it" },
                parse = { body -> parseRates(body, requireSuccess = true) }
            )
        )

        private fun parseRates(body: String, requireSuccess: Boolean): Map<String, Double>? {
            return try {
                val json = JSONObject(body)
                if (requireSuccess && json.optString("result") != "success") return null
                val ratesObj = json.optJSONObject("rates") ?: return null
                val rates = mutableMapOf<String, Double>()
                ratesObj.keys().forEach { code -> rates[code] = ratesObj.getDouble(code) }
                rates
            } catch (_: Exception) {
                null
            }
        }
    }
}
