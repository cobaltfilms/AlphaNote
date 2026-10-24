package be.cobaltfilms.alphanote.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import be.cobaltfilms.alphanote.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

data class AppUpdateInfo(val version: String, val versionCode: Int, val notes: String, val url: String)

/**
 * Mises à jour in-app : lit un appcast JSON ({version, versionCode, notes, url}),
 * télécharge l'APK dans le cache et lance l'installateur système.
 * Miroir Android de Services/Update/UpdateManager.swift.
 */
class UpdateManager(context: Context) {
    private val appContext = context.applicationContext

    sealed class Phase {
        data object Idle : Phase()
        data object Checking : Phase()
        data object UpToDate : Phase()
        data class Available(val info: AppUpdateInfo) : Phase()
        data class Downloading(val info: AppUpdateInfo, val progress: Float) : Phase()
        data class ReadyToInstall(val info: AppUpdateInfo, val file: File) : Phase()
        data class Failed(val message: String) : Phase()
    }

    private val _phase = MutableStateFlow<Phase>(Phase.Idle)
    val phase: StateFlow<Phase> = _phase.asStateFlow()

    val currentVersion: String get() = BuildConfig.VERSION_NAME
    val currentVersionCode: Int get() = BuildConfig.VERSION_CODE

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .followRedirects(true)
        .build()

    suspend fun check(appcastUrl: String) {
        val url = appcastUrl.trim()
        if (url.isEmpty()) { _phase.value = Phase.Failed("Aucun canal de mise à jour configuré."); return }
        _phase.value = Phase.Checking
        val info = try {
            withContext(Dispatchers.IO) {
                client.newCall(Request.Builder().url(url).get().build()).execute().use { response ->
                    if (!response.isSuccessful) throw IllegalStateException("Le serveur a répondu ${response.code}.")
                    val body = response.body?.string().orEmpty()
                    if (body.trimStart().startsWith("<")) throw IllegalStateException("Le canal renvoie une page web (dépôt privé ?), pas un appcast.")
                    parseAppcast(body)
                }
            }
        } catch (error: Exception) {
            _phase.value = Phase.Failed(error.message ?: "Vérification impossible.")
            return
        }
        _phase.value = if (info.versionCode > currentVersionCode) Phase.Available(info) else Phase.UpToDate
    }

    suspend fun download(info: AppUpdateInfo) {
        _phase.value = Phase.Downloading(info, 0f)
        try {
            val file = withContext(Dispatchers.IO) {
                val dir = File(appContext.cacheDir, "updates").apply { mkdirs() }
                dir.listFiles()?.forEach { it.delete() }
                val target = File(dir, "AlphaNote-${info.version}.apk")
                client.newCall(Request.Builder().url(info.url).get().build()).execute().use { response ->
                    if (!response.isSuccessful) throw IllegalStateException("Téléchargement refusé (${response.code}).")
                    val body = response.body ?: throw IllegalStateException("Réponse vide.")
                    val total = body.contentLength()
                    body.byteStream().use { input ->
                        target.outputStream().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            var read: Int
                            var done = 0L
                            while (input.read(buffer).also { read = it } >= 0) {
                                output.write(buffer, 0, read)
                                done += read
                                if (total > 0) _phase.value = Phase.Downloading(info, (done.toFloat() / total).coerceIn(0f, 1f))
                            }
                        }
                    }
                }
                target
            }
            _phase.value = Phase.ReadyToInstall(info, file)
        } catch (error: Exception) {
            _phase.value = Phase.Failed(error.message ?: "Téléchargement impossible.")
        }
    }

    /** Vrai si l'installation a pu être lancée ; faux si l'autorisation « sources inconnues » manque. */
    fun install(file: File): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !appContext.packageManager.canRequestPackageInstalls()) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${appContext.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(intent)
            return false
        }
        val uri = FileProvider.getUriForFile(appContext, "${appContext.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        appContext.startActivity(intent)
        return true
    }

    fun reset() { _phase.value = Phase.Idle }

    companion object {
        fun parseAppcast(body: String): AppUpdateInfo {
            val json = JSONObject(body)
            val version = json.optString("version").ifBlank { throw IllegalStateException("Appcast sans version.") }
            val code = json.optInt("versionCode", versionCodeFrom(version))
            val url = json.optString("url").ifBlank { throw IllegalStateException("Appcast sans URL de téléchargement.") }
            return AppUpdateInfo(version, code, json.optString("notes"), url)
        }

        /** 0.2.1 → 213 ? Non : code lisible « MMmmpp » = 0*10000 + 2*100 + 1 = 201. */
        fun versionCodeFrom(version: String): Int {
            val parts = version.split(".").map { it.filter(Char::isDigit).toIntOrNull() ?: 0 }
            val major = parts.getOrElse(0) { 0 }; val minor = parts.getOrElse(1) { 0 }; val patch = parts.getOrElse(2) { 0 }
            return major * 10_000 + minor * 100 + patch
        }
    }
}
