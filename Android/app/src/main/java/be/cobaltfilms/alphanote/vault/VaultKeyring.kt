package be.cobaltfilms.alphanote.vault

import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import be.cobaltfilms.alphanote.services.SecurePasswordStore
import java.security.MessageDigest
import java.util.Base64
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Le coffre des notes sécurisées (port de VaultKeyring.swift) : garde le mot
 * de passe maître (Keystore), met en cache les clés dérivées tant que le coffre
 * est ouvert, et le referme après quelques minutes sans usage ou quand l'app
 * passe en arrière-plan. Ouverture par empreinte (ou code de l'appareil), sinon
 * par le mot de passe maître.
 */
object VaultKeyring {
    const val AUTO_LOCK_DEFAULT_MINUTES = 5

    class UnlockError(message: String) : Exception(message)

    private val _isUnlocked = MutableStateFlow(false)
    val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()
    private val _isConfigured = MutableStateFlow(false)
    val isConfigured: StateFlow<Boolean> = _isConfigured.asStateFlow()

    private var store: PasswordHolder? = null
    private var prefs: android.content.SharedPreferences? = null
    private var password: String? = null
    private val keysBySalt = HashMap<String, ByteArray>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var lockJob: Job? = null
    private var lastManualLock = 0L
    var autoLockMinutes: Int = AUTO_LOCK_DEFAULT_MINUTES

    /** Stockage du mot de passe maître (interface pour les tests). */
    interface PasswordHolder {
        fun read(): String?
        fun save(password: String)
        fun clear()
    }

    fun init(context: Context) {
        if (store != null) return
        val secure = SecurePasswordStore(context, slot = "vault_master")
        store = object : PasswordHolder {
            override fun read() = secure.readPassword()
            override fun save(password: String) = secure.savePassword(password)
            override fun clear() = secure.clearPassword()
        }
        prefs = context.applicationContext.getSharedPreferences("alphanote_vault", Context.MODE_PRIVATE)
        autoLockMinutes = prefs?.getInt(AUTO_LOCK_KEY, AUTO_LOCK_DEFAULT_MINUTES) ?: AUTO_LOCK_DEFAULT_MINUTES
        _isConfigured.value = store?.read() != null
    }

    /** Tests : stockage en mémoire, sel tenu en mémoire. */
    internal fun initForTesting(holder: PasswordHolder) {
        lock()
        store = holder
        prefs = null
        memorySalt = null
        _isConfigured.value = holder.read() != null
    }

    // ---- Mise en place ----

    /** Définit le mot de passe maître ; s'il existe déjà des notes sécurisées
     *  (d'un autre appareil), il doit les ouvrir. */
    fun setUp(password: String, existingSealed: List<String>) {
        if (password.length < 8) throw UnlockError("Le mot de passe maître doit faire au moins 8 caractères.")
        val sample = existingSealed.firstNotNullOfOrNull(VaultEnvelope::parse)
        if (sample != null) {
            val key = VaultEnvelope.deriveKey(password, sample.salt, sample.iterations)
            try { VaultEnvelope.open(sample, key) } catch (_: Exception) { throw UnlockError("Mot de passe maître incorrect.") }
            primarySalt = sample.salt
        } else if (primarySalt == null) {
            primarySalt = VaultEnvelope.randomSalt()
        }
        store?.save(password)
        _isConfigured.value = true
        openWith(password)
    }

    /** Oublie le mot de passe maître sur cet appareil ; les notes restent chiffrées. */
    fun forget() {
        lock()
        store?.clear()
        _isConfigured.value = false
    }

    // ---- Ouvrir / fermer ----

    fun unlock(candidate: String) {
        val stored = store?.read() ?: throw UnlockError("Aucun mot de passe maître n'est défini sur cet appareil.")
        if (!MessageDigest.isEqual(candidate.toByteArray(), stored.toByteArray())) throw UnlockError("Mot de passe maître incorrect.")
        openWith(stored)
    }

    fun canUseBiometrics(context: Context): Boolean =
        BiometricManager.from(context).canAuthenticate(AUTHENTICATORS) == BiometricManager.BIOMETRIC_SUCCESS

    /** Empreinte / visage, ou code de l'appareil en secours. */
    fun unlockWithBiometrics(activity: FragmentActivity, onResult: (String?) -> Unit) {
        val stored = store?.read() ?: return onResult("Aucun mot de passe maître n'est défini sur cet appareil.")
        if (!canUseBiometrics(activity)) return onResult("Déverrouillage biométrique indisponible : utilise le mot de passe maître.")
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                openWith(stored); onResult(null)
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                onResult(if (errorCode == BiometricPrompt.ERROR_USER_CANCELED || errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON || errorCode == BiometricPrompt.ERROR_CANCELED) "" else errString.toString())
            }
        })
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle("Ouvrir le coffre")
                .setSubtitle("Notes sécurisées d'AlphaNote")
                .setAllowedAuthenticators(AUTHENTICATORS)
                .build()
        )
    }

    /** Verrouillage demandé (menu, réglages) : l'écran ne relance pas l'empreinte de lui-même. */
    fun lockNow() {
        lock()
        lastManualLock = System.currentTimeMillis()
    }

    val justLockedManually: Boolean get() = System.currentTimeMillis() - lastManualLock < 3_000

    fun lock() {
        lockJob?.cancel(); lockJob = null
        password = null
        synchronized(this) {
            keysBySalt.values.forEach { it.fill(0) }
            keysBySalt.clear()
        }
        _isUnlocked.value = false
    }

    fun setAutoLock(minutes: Int) {
        autoLockMinutes = minutes
        prefs?.edit()?.putInt(AUTO_LOCK_KEY, minutes)?.apply()
        if (_isUnlocked.value) touch()
    }

    // ---- Chiffrer / déchiffrer ----

    /** Contenu scellé ; null si le coffre est fermé. */
    fun seal(content: String): String? {
        if (!_isUnlocked.value) return null
        val salt = primarySalt ?: return null
        val key = key(salt, VaultEnvelope.ITERATIONS) ?: return null
        touch()
        return VaultEnvelope.seal(content, key, salt)
    }

    /** Texte en clair ; null si fermé ou si le mot de passe ne l'ouvre pas. */
    fun open(content: String): String? {
        if (!_isUnlocked.value) return null
        val parsed = VaultEnvelope.parse(content) ?: return null
        val key = key(parsed.salt, parsed.iterations) ?: return null
        touch()
        return try { VaultEnvelope.open(parsed, key) } catch (_: Exception) { null }
    }

    // ---- Interne ----

    private const val AUTO_LOCK_KEY = "auto_lock_minutes"
    private const val PRIMARY_SALT_KEY = "primary_salt"
    private const val AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_STRONG or BiometricManager.Authenticators.DEVICE_CREDENTIAL
    private var memorySalt: ByteArray? = null

    private var primarySalt: ByteArray?
        get() = prefs?.getString(PRIMARY_SALT_KEY, null)?.let { Base64.getUrlDecoder().decode(it) } ?: memorySalt
        set(value) {
            memorySalt = value
            prefs?.edit()?.putString(PRIMARY_SALT_KEY, value?.let { Base64.getUrlEncoder().withoutPadding().encodeToString(it) })?.apply()
        }

    private fun openWith(password: String) {
        this.password = password
        _isUnlocked.value = true
        touch()
        // Clé principale calculée hors du fil d'interface (PBKDF2, ~1 s sur téléphone).
        primarySalt?.let { salt -> scope.launch(Dispatchers.Default) { key(salt, VaultEnvelope.ITERATIONS) } }
    }

    @Synchronized
    private fun key(salt: ByteArray, iterations: Int): ByteArray? {
        val id = Base64.getEncoder().encodeToString(salt) + ":" + iterations
        keysBySalt[id]?.let { return it }
        val pw = password ?: return null
        return VaultEnvelope.deriveKey(pw, salt, iterations).also { keysBySalt[id] = it }
    }

    /** Refermeture automatique après N minutes sans lecture ni écriture. */
    private fun touch() {
        lockJob?.cancel()
        if (autoLockMinutes <= 0) return
        lockJob = scope.launch {
            delay(autoLockMinutes * 60_000L)
            lock()
        }
    }
}
