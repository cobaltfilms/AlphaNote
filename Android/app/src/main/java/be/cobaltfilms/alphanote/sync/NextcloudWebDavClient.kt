package be.cobaltfilms.alphanote.sync

import android.util.Xml
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Credentials
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit
import kotlin.math.pow

data class RemoteFileEntry(
    val href: String,
    val etag: String?
)

data class RemoteNotePayload(
    val dto: CloudNoteDto,
    val etag: String?
)

sealed class NextcloudClientException(message: String) : Exception(message) {
    object InvalidServerUrl : NextcloudClientException("URL Nextcloud invalide.")
    object MissingBackup : NextcloudClientException("Aucun backup AlphaNote trouvé sur Nextcloud.")
    object Unauthorized : NextcloudClientException("Identifiants Nextcloud invalides (401).")
    object Forbidden : NextcloudClientException("Accès refusé par Nextcloud (403).")
    object InvalidResponse : NextcloudClientException("Réponse Nextcloud inattendue.")
    data class HttpStatus(val code: Int) : NextcloudClientException("Réponse Nextcloud inattendue ($code).")
}

class NextcloudWebDavClient(
    serverUrl: String,
    private val username: String,
    private val password: String
) {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .build()

    private val serverBaseUrl: HttpUrl = serverUrl.trim().removeSuffix("/").toHttpUrlOrNull()
        ?: throw NextcloudClientException.InvalidServerUrl
    private val webDavRootUrl: HttpUrl = serverBaseUrl.newBuilder()
        .addPathSegment("remote.php")
        .addPathSegment("dav")
        .addPathSegment("files")
        .addPathSegment(username)
        .build()
    private val alphaFolderUrl: HttpUrl = webDavRootUrl.newBuilder().addPathSegment("AlphaNote").build()
    private val notesFolderUrl: HttpUrl = alphaFolderUrl.newBuilder().addPathSegment("notes").build()
    private val backupsFolderUrl: HttpUrl = alphaFolderUrl.newBuilder().addPathSegment("backups").build()
    private val manifestUrl: HttpUrl = alphaFolderUrl.newBuilder().addPathSegment("manifest.json").build()

    suspend fun testConnection() {
        ensureDirectories()
        fetchManifest()
    }

    suspend fun ensureDirectories() {
        ensureDirectory(alphaFolderUrl)
        ensureDirectory(notesFolderUrl)
    }

    suspend fun ensureBackupDirectory() {
        ensureDirectory(alphaFolderUrl)
        ensureDirectory(backupsFolderUrl)
    }

    suspend fun listNotes(): List<RemoteFileEntry> {
        return propfind(notesFolderUrl, depth = 1).filter { it.href.endsWith(".json") }
    }

    suspend fun fetchManifest(): ManifestDto? {
        val result = sendRequest(manifestUrl, "GET", expectedStatusCodes = setOf(200, 404))
        if (result.statusCode == 404) return null
        return CloudJsonCoder.decodeManifest(result.body)
    }

    suspend fun uploadManifest(manifest: ManifestDto) {
        sendRequest(
            manifestUrl,
            "PUT",
            body = CloudJsonCoder.encodeManifest(manifest).toRequestBody(JSON_MEDIA_TYPE),
            expectedStatusCodes = setOf(200, 201, 204)
        )
    }

    suspend fun fetchNote(uuid: String): RemoteNotePayload? {
        val url = notesFolderUrl.newBuilder().addPathSegment("$uuid.json").build()
        val result = sendRequest(url, "GET", expectedStatusCodes = setOf(200, 404))
        if (result.statusCode == 404) return null
        return RemoteNotePayload(CloudJsonCoder.decodeNote(result.body), result.headers["etag"] ?: result.headers["ETag"])
    }

    suspend fun uploadNote(dto: CloudNoteDto, etag: String?) {
        val url = notesFolderUrl.newBuilder().addPathSegment("${dto.uuid}.json").build()
        val headers = if (etag.isNullOrBlank()) emptyMap() else mapOf("If-Match" to etag)
        val result = sendRequest(
            url,
            "PUT",
            headers = headers,
            body = CloudJsonCoder.encodeNote(dto).toRequestBody(JSON_MEDIA_TYPE),
            expectedStatusCodes = setOf(200, 201, 204, 412)
        )
        if (result.statusCode == 412) {
            throw NextcloudClientException.HttpStatus(412)
        }
    }

    suspend fun deleteNote(uuid: String) {
        val url = notesFolderUrl.newBuilder().addPathSegment("$uuid.json").build()
        sendRequest(url, "DELETE", expectedStatusCodes = setOf(200, 204, 404))
    }

    suspend fun uploadBackup(backup: BackupDto): String {
        ensureBackupDirectory()
        val filename = "alphanote-backup-${CloudJsonCoder.formatInstant(backup.exportedAt).replace(":", "-")}.json"
        val url = backupsFolderUrl.newBuilder().addPathSegment(filename).build()
        sendRequest(
            url,
            "PUT",
            body = CloudJsonCoder.encodeBackup(backup).toRequestBody(JSON_MEDIA_TYPE),
            expectedStatusCodes = setOf(200, 201, 204)
        )
        return filename
    }

    suspend fun fetchLatestBackup(): BackupDto {
        ensureBackupDirectory()
        val entries = propfind(backupsFolderUrl, depth = 1)
            .filter { it.href.substringAfterLast("/").startsWith("alphanote-backup-") && it.href.endsWith(".json") }
            .sortedBy { it.href }
        val latest = entries.lastOrNull() ?: throw NextcloudClientException.MissingBackup
        val filename = latest.href.substringAfterLast("/")
        val url = backupsFolderUrl.newBuilder().addPathSegment(filename).build()
        val result = sendRequest(url, "GET", expectedStatusCodes = setOf(200))
        return CloudJsonCoder.decodeBackup(result.body)
    }

    private suspend fun ensureDirectory(url: HttpUrl) {
        val result = sendRequest(url, "MKCOL", expectedStatusCodes = setOf(201, 405, 301))
        if (result.statusCode == 301) throw NextcloudClientException.HttpStatus(301)
    }

    private suspend fun propfind(url: HttpUrl, depth: Int): List<RemoteFileEntry> {
        val body = """
            <?xml version="1.0"?>
            <d:propfind xmlns:d="DAV:">
              <d:prop>
                <d:getetag/>
              </d:prop>
            </d:propfind>
        """.trimIndent().toRequestBody(XML_MEDIA_TYPE)

        val result = sendRequest(
            url,
            "PROPFIND",
            headers = mapOf("Depth" to "$depth", "Content-Type" to "application/xml"),
            body = body,
            expectedStatusCodes = setOf(207)
        )
        return parsePropfind(result.body)
    }

    private suspend fun sendRequest(
        url: HttpUrl,
        method: String,
        headers: Map<String, String> = emptyMap(),
        body: RequestBody? = null,
        expectedStatusCodes: Set<Int>
    ): WebDavResponse {
        var attempt = 0
        val maxAttempts = 3

        while (true) {
            try {
                return executeRequest(url, method, headers, body, expectedStatusCodes)
            } catch (error: Exception) {
                if (shouldRetry(error, attempt, maxAttempts)) {
                    attempt += 1
                    kotlinx.coroutines.delay(backoffMillis(attempt))
                    continue
                }
                throw error
            }
        }
    }

    private suspend fun executeRequest(
        url: HttpUrl,
        method: String,
        headers: Map<String, String> = emptyMap(),
        body: RequestBody? = null,
        expectedStatusCodes: Set<Int>
    ): WebDavResponse = withContext(Dispatchers.IO) {
        val requestBody = body ?: if (method == "PUT" || method == "PROPFIND") ByteArray(0).toRequestBody() else null
        val builder = Request.Builder()
            .url(url)
            .method(method, requestBody)
            .header("Authorization", Credentials.basic(username, password))

        headers.forEach { (key, value) -> builder.header(key, value) }

        val response = client.newCall(builder.build()).execute()
        try {
            if (response.code == 401) throw NextcloudClientException.Unauthorized
            if (response.code == 403) throw NextcloudClientException.Forbidden

            if (response.code in expectedStatusCodes) {
                return@withContext WebDavResponse(
                    body = response.body?.string().orEmpty(),
                    statusCode = response.code,
                    headers = response.headers.toMultimap().mapValues { (_, values) -> values.firstOrNull().orEmpty() }
                )
            }

            throw NextcloudClientException.HttpStatus(response.code)
        } finally {
            response.close()
        }
    }

    private fun parsePropfind(xml: String): List<RemoteFileEntry> {
        val parser = Xml.newPullParser()
        parser.setInput(StringReader(xml))
        val entries = mutableListOf<RemoteFileEntry>()
        var inResponse = false
        var currentElement = ""
        var currentHref = ""
        var currentEtag = ""

        var event = parser.eventType
        while (event != XmlPullParser.END_DOCUMENT) {
            when (event) {
                XmlPullParser.START_TAG -> {
                    currentElement = parser.name.localName()
                    if (currentElement == "response") {
                        inResponse = true
                        currentHref = ""
                        currentEtag = ""
                    }
                }
                XmlPullParser.TEXT -> {
                    if (inResponse) {
                        when (currentElement) {
                            "href" -> currentHref += parser.text
                            "getetag" -> currentEtag += parser.text
                        }
                    }
                }
                XmlPullParser.END_TAG -> {
                    if (parser.name.localName() == "response") {
                        val href = currentHref.trim()
                        if (href.isNotEmpty()) {
                            entries.add(RemoteFileEntry(href, currentEtag.trim().ifBlank { null }))
                        }
                        inResponse = false
                    }
                    currentElement = ""
                }
            }
            event = parser.next()
        }
        return entries
    }

    private fun String.localName(): String = substringAfter(":").lowercase()

    private fun shouldRetry(statusCode: Int, attempt: Int, maxAttempts: Int): Boolean {
        return attempt + 1 < maxAttempts && statusCode in 500..599
    }

    private fun shouldRetry(error: Exception, attempt: Int, maxAttempts: Int): Boolean {
        if (attempt + 1 >= maxAttempts) return false
        return error is SocketTimeoutException || error is java.io.IOException ||
            (error is NextcloudClientException.HttpStatus && error.code in 500..599)
    }

    private fun backoffMillis(attempt: Int): Long {
        return (400.0 * 2.0.pow((attempt - 1).toDouble())).toLong()
    }

    private data class WebDavResponse(
        val body: String,
        val statusCode: Int,
        val headers: Map<String, String>
    )

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        val XML_MEDIA_TYPE = "application/xml; charset=utf-8".toMediaType()
    }
}
