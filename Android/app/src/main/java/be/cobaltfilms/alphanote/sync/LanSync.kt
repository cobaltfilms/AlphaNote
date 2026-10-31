package be.cobaltfilms.alphanote.sync

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import be.cobaltfilms.alphanote.data.NoteRepository
import be.cobaltfilms.alphanote.services.DeviceIdentity
import be.cobaltfilms.alphanote.services.SecurePasswordStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Synchro directe avec le Mac sur le réseau local (0.3.0).
 * Protocole : docs/SYNC-LAN.md. Le Mac sert HTTP et s'annonce en Bonjour ; ce fichier
 * est le côté téléphone : découverte, appairage, échange des notes.
 */
const val LAN_SERVICE_TYPE = "_alphanote._tcp."

data class LanPeer(val name: String, val host: String, val port: Int) {
    val baseUrl: String get() = "http://$host:$port"
}

class LanSyncException(val status: Int, message: String) : Exception(message)

/** Activation, nom du Mac appairé et jeton (stocké chiffré, emplacement « lan »). */
class LanSyncStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("alphanote_lan_sync", Context.MODE_PRIVATE)
    private val tokens = SecurePasswordStore(context.applicationContext, slot = "lan")

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) { prefs.edit().putBoolean(KEY_ENABLED, value).apply() }

    val pairedName: String? get() = prefs.getString(KEY_PAIRED_NAME, null)

    fun token(): String? = tokens.readPassword()

    val isPaired: Boolean get() = pairedName != null && token() != null

    fun savePairing(serverName: String, token: String) {
        prefs.edit().putString(KEY_PAIRED_NAME, serverName).apply()
        tokens.savePassword(token)
    }

    fun forget() {
        prefs.edit().remove(KEY_PAIRED_NAME).apply()
        tokens.clearPassword()
    }

    private companion object {
        const val KEY_ENABLED = "enabled"
        const val KEY_PAIRED_NAME = "paired_name"
    }
}

/** Cherche les Macs AlphaNote annoncés sur le Wi-Fi. */
class LanDiscovery(context: Context) {
    private val nsd = context.applicationContext.getSystemService(Context.NSD_SERVICE) as NsdManager

    /** Chaque Mac trouvé est émis une fois résolu (adresse et port). Le flux se ferme à l'annulation. */
    fun discover(): Flow<LanPeer> = callbackFlow {
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) { close() }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (!serviceInfo.serviceType.contains("_alphanote._tcp")) return
                @Suppress("DEPRECATION") // resolveService : seule API disponible à partir d'Android 8 (minSdk 26)
                nsd.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        val host = serviceInfo.host?.hostAddress ?: return
                        trySend(LanPeer(serviceInfo.serviceName, host.substringBefore('%'), serviceInfo.port))
                    }
                })
            }
        }
        nsd.discoverServices(LAN_SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        awaitClose { runCatching { nsd.stopServiceDiscovery(listener) } }
    }

    /** Le Mac demandé (par nom si connu), ou null s'il ne répond pas dans le délai. */
    suspend fun findMac(name: String?, timeoutMs: Long = 6_000): LanPeer? =
        withTimeoutOrNull(timeoutMs) {
            discover().filter { name == null || it.name == name }.first()
        }
}

/** Client HTTP du protocole /v1 du Mac. */
class LanSyncClient(
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()
) {
    private val json = "application/json; charset=utf-8".toMediaType()

    data class Paired(val token: String, val serverName: String)

    suspend fun pair(peer: LanPeer, code: String, deviceId: String, deviceName: String): Paired {
        val body = JSONObject().put("code", code).put("deviceId", deviceId).put("deviceName", deviceName).toString()
        val response = JSONObject(send(peer, "POST", "/v1/pair", body, token = null))
        return Paired(response.getString("token"), response.optString("serverName", peer.name))
    }

    suspend fun fetchNotes(peer: LanPeer, token: String): List<CloudNoteDto> {
        val array = JSONArray(send(peer, "GET", "/v1/notes", null, token))
        return (0 until array.length()).map { CloudJsonCoder.decodeNote(array.getJSONObject(it).toString()) }
    }

    /** Envoie la note ; le Mac répond avec la version qui fait autorité. */
    suspend fun pushNote(peer: LanPeer, token: String, dto: CloudNoteDto): CloudNoteDto =
        CloudJsonCoder.decodeNote(send(peer, "PUT", "/v1/notes/${dto.uuid}", CloudJsonCoder.encodeNote(dto), token))

    private suspend fun send(peer: LanPeer, verb: String, path: String, body: String?, token: String?): String =
        withContext(Dispatchers.IO) {
            val request = Request.Builder().url(peer.baseUrl + path).apply {
                if (token != null) header("Authorization", "Bearer $token")
                method(verb, body?.toRequestBody(json) ?: if (verb == "GET") null else "".toRequestBody(json))
            }.build()
            http.newCall(request).execute().use { response ->
                val text = response.body?.string().orEmpty()
                if (!response.isSuccessful) throw LanSyncException(response.code, text.ifEmpty { "HTTP ${response.code}" })
                text
            }
        }
}

/**
 * Une passe de synchro : fusion avec la même politique que Nextcloud (SyncMergePolicy),
 * puis envoi des notes locales qui doivent partir.
 */
class LanSyncEngine(
    private val repository: NoteRepository,
    private val client: LanSyncClient,
    private val clock: () -> Long = System::currentTimeMillis
) {
    data class Report(val applied: Int, val pushed: Int)

    suspend fun sync(peer: LanPeer, token: String): Report {
        val now = clock()
        val remote = client.fetchNotes(peer, token).associateBy { it.uuid }

        val localBefore = repository.getAllIncludingDeleted().associateBy { it.uuid }
        var applied = 0
        for ((uuid, merged) in SyncMergePolicy.merge(localBefore, remote)) {
            val existing = localBefore[uuid]
            if (existing == null || CloudNoteDto.fromNote(existing) != merged) {
                repository.saveFromSync(merged.toNote(existing?.id, now))
                applied++
            }
        }

        // Relecture après fusion : ce qui vient d'arriver ne doit pas repartir.
        var pushed = 0
        for (note in repository.getAllIncludingDeleted()) {
            val local = CloudNoteDto.fromNote(note)
            val remoteCopy = remote[note.uuid]
            if (!SyncMergePolicy.shouldUploadLocal(local, remoteCopy, note.lastSyncedAt)) continue
            val winner = client.pushNote(peer, token, local)
            if (winner != local) repository.saveFromSync(winner.toNote(note.id, now))
            repository.markLastSynced(note.uuid, now)
            pushed++
        }
        return Report(applied, pushed)
    }
}

/** Point d'entrée de l'app : déclenchements, état affiché dans les réglages. */
class LanSyncCoordinator(context: Context, private val repository: NoteRepository) {
    sealed class State {
        object Idle : State()
        object Searching : State()
        object Syncing : State()
        data class Done(val at: Long, val applied: Int, val pushed: Int) : State()
        object NotFound : State()
        data class Failed(val message: String) : State()
    }

    private val appContext = context.applicationContext
    val store = LanSyncStore(appContext)
    private val discovery = LanDiscovery(appContext)
    private val client = LanSyncClient()
    private val engine = LanSyncEngine(repository, client)
    private val mutex = Mutex()
    private var scope: CoroutineScope? = null
    private var pending: Job? = null

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    private val _enabled = MutableStateFlow(store.enabled)
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    private val _pairedName = MutableStateFlow(store.pairedName)
    val pairedName: StateFlow<String?> = _pairedName.asStateFlow()

    fun attach(scope: CoroutineScope) {
        if (this.scope != null) return
        this.scope = scope
        // Filet de sécurité : une passe toutes les 2 min tant que c'est activé.
        scope.launch {
            while (isActive) {
                delay(TimeUnit.MINUTES.toMillis(2))
                requestSync(0)
            }
        }
    }

    /** Demande une passe après `delayMs` ; une demande plus récente remplace la précédente. */
    fun requestSync(delayMs: Long) {
        val scope = scope ?: return
        if (!store.enabled || !store.isPaired) return
        pending?.cancel()
        pending = scope.launch {
            delay(delayMs)
            syncNow()
        }
    }

    suspend fun syncNow() = mutex.withLock {
        if (!store.enabled || !store.isPaired) return@withLock
        _state.value = State.Searching
        val peer = discovery.findMac(store.pairedName)
        if (peer == null) {
            _state.value = State.NotFound
            return@withLock
        }
        _state.value = State.Syncing
        _state.value = try {
            val report = engine.sync(peer, store.token() ?: throw LanSyncException(401, "non appairé"))
            State.Done(System.currentTimeMillis(), report.applied, report.pushed)
        } catch (e: LanSyncException) {
            if (e.status == 401) State.Failed("Appairage expiré : appairez le téléphone de nouveau.")
            else State.Failed("Le Mac a répondu : ${e.message}")
        } catch (e: IOException) {
            State.Failed("Mac injoignable sur le réseau.")
        }
    }

    fun setEnabled(value: Boolean) {
        store.enabled = value
        _enabled.value = value
        if (value) requestSync(0) else _state.value = State.Idle
    }

    /** Appaire avec le code affiché sur le Mac. Retourne un message pour l'utilisateur. */
    suspend fun pair(code: String): String = mutex.withLock {
        val peer = discovery.findMac(null) ?: return@withLock "Mac introuvable sur ce Wi-Fi."
        try {
            val paired = client.pair(peer, code.trim(), DeviceIdentity.currentDeviceId(appContext), android.os.Build.MODEL)
            store.savePairing(paired.serverName, paired.token)
            _pairedName.value = paired.serverName
            _state.value = State.Idle
            "Appairé avec ${paired.serverName}."
        } catch (e: LanSyncException) {
            "Code refusé ou expiré. Générez un nouveau code sur le Mac."
        } catch (e: IOException) {
            "Mac injoignable sur le réseau."
        }
    }

    fun forget() {
        store.forget()
        _pairedName.value = null
        _state.value = State.Idle
    }
}
