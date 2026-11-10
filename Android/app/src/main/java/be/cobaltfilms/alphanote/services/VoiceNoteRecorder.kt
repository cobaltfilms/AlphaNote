package be.cobaltfilms.alphanote.services

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.icu.util.ULocale
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.RequiresApi
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import be.cobaltfilms.alphanote.domain.NoteAttachments
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.io.IOException
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue
import kotlin.math.roundToInt

/** Résultat d'un enregistrement : le fichier est déjà dans les pièces jointes de la note. */
data class VoiceNoteResult(
    val noteUuid: String,
    val audioName: String,
    val transcript: String,
    val durationSeconds: Double
)

/**
 * Note vocale : enregistre le micro dans un fichier m4a **et** transcrit en
 * même temps — pendant Android de `Services/VoiceNoteRecorder.swift`.
 *
 * L'enregistrement est la référence : l'app capte elle-même le micro
 * (AudioRecord), encode en AAC et, sur Android 13+, donne **le même son** au
 * reconnaisseur vocal du système (`RecognizerIntent.EXTRA_AUDIO_SOURCE`).
 * Deux captures du micro en parallèle ne marchent pas sur Android (l'une des
 * deux reçoit du silence) : le reconnaisseur n'ouvre donc jamais le micro
 * lui-même. Si la transcription est indisponible ou s'interrompt, le fichier
 * est gardé et [transcriptionIssue] dit pourquoi le texte manque.
 *
 * Toutes les méthodes s'appellent depuis le fil principal.
 */
class VoiceNoteRecorder(context: Context) {
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    var isRecording by mutableStateOf(false)
        private set
    /** Début de l'enregistrement, en `SystemClock.elapsedRealtime()`. */
    var startedAt by mutableStateOf<Long?>(null)
        private set
    var transcript by mutableStateOf("")
        private set
    /** Pourquoi il n'y a pas (ou plus) de transcription. Null : tout va bien. */
    var transcriptionIssue by mutableStateOf<String?>(null)
        private set
    /** Pourquoi l'enregistrement n'a pas démarré, ou n'a rien donné. */
    var error by mutableStateOf<String?>(null)
        private set

    /** Le micro s'est arrêté tout seul (erreur de capture) : à l'appelant de terminer. */
    var onInterrupted: () -> Unit = {}

    private var capture: AudioCapture? = null
    private var transcriber: LiveTranscriber? = null
    /** Note de l'enregistrement en cours (ou du dernier). */
    var noteUuid = ""
        private set
    private var audioName = ""

    /** Démarre l'enregistrement pour la note. Faux : rien n'a démarré, voir [error]. */
    fun start(noteUuid: String): Boolean {
        if (isRecording) return false
        error = null
        transcriptionIssue = null
        transcript = ""

        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            error = "Micro non autorisé. Autorise AlphaNote dans les réglages de l'appareil."
            return false
        }
        val name = NoteAttachments.newAudioName()
        val file = NoteAttachments.file(context, noteUuid, name)
        val capture = try {
            AudioCapture.start(file) { main.post { if (isRecording) onInterrupted() } }
        } catch (failure: IOException) {
            file.delete()
            error = failure.message ?: "Impossible de démarrer le microphone."
            return false
        }

        this.capture = capture
        this.noteUuid = noteUuid
        audioName = name
        startedAt = SystemClock.elapsedRealtime()
        isRecording = true
        transcriber = LiveTranscriber(
            context, capture.sampleRate,
            onText = { transcript = it },
            onIssue = { transcriptionIssue = it },
            attach = { capture.sink = it }
        ).also { it.start() }
        return true
    }

    /**
     * Arrête, attend la fin de la transcription en cours et rend le résultat.
     * Null : rien n'était en cours, l'enregistrement est trop court, ou le
     * fichier n'a pas pu être écrit ([error] le dit).
     */
    suspend fun stop(): VoiceNoteResult? {
        if (!isRecording) return null
        isRecording = false
        startedAt = null
        val capture = capture ?: return null
        val transcriber = transcriber
        this.capture = null
        this.transcriber = null

        // Fin du micro et du m4a d'abord : le fichier ne dépend pas de la transcription.
        val written = withContext(Dispatchers.IO) { capture.finish() }
        val text = transcriber?.finish().orEmpty()
        transcript = text

        val file = NoteAttachments.file(context, noteUuid, audioName)
        if (!written || !file.exists() || file.length() == 0L) {
            file.delete()
            error = "L'enregistrement n'a pas pu être écrit : rien n'a été gardé."
            return null
        }
        if (capture.recordedSeconds < MIN_SECONDS) {
            file.delete()
            return null
        }
        return VoiceNoteResult(noteUuid, audioName, text.trim(), capture.recordedSeconds)
    }

    /** Abandonne : le fichier est supprimé, rien n'est ajouté à la note. */
    fun cancel() {
        if (!isRecording) return
        isRecording = false
        startedAt = null
        transcriber?.cancel()
        transcriber = null
        val capture = capture
        this.capture = null
        val file = NoteAttachments.file(context, noteUuid, audioName)
        // L'arrêt du micro attend le fil de capture : hors du fil principal.
        Thread { capture?.finish(); file.delete() }.start()
    }

    companion object {
        /** En dessous, c'est un appui par erreur : l'enregistrement est jeté. */
        const val MIN_SECONDS = 0.7
    }
}

// ---- Capture du micro et fichier m4a ----

/**
 * Lit le micro en PCM 16 bits mono sur son propre fil, l'encode dans le
 * fichier et en donne une copie à [sink] (la transcription du moment).
 */
private class AudioCapture private constructor(
    private val record: AudioRecord,
    private val writer: AacFileWriter,
    val sampleRate: Int,
    private val onLost: () -> Unit
) {
    @Volatile var sink: PcmPipe? = null
    @Volatile private var running = true
    @Volatile private var failed = false
    @Volatile private var frames = 0L

    val recordedSeconds: Double get() = frames.toDouble() / sampleRate

    private val thread = Thread({
        // 100 ms de son par lecture.
        val buffer = ByteArray(sampleRate / 10 * 2)
        try {
            while (running) {
                val read = record.read(buffer, 0, buffer.size)
                if (read < 0) break
                if (read == 0) continue
                writer.write(buffer, read)
                frames += read / 2
                sink?.offer(buffer.copyOf(read))
            }
        } catch (_: Exception) {
            failed = true
        } finally {
            runCatching { record.stop() }
            record.release()
            if (!writer.finish()) failed = true
            // Sorti de la boucle sans qu'on l'ait demandé : le micro est perdu.
            if (running) onLost()
        }
    }, "alphanote-voice-capture")

    /** Arrête le micro et ferme le m4a. Bloquant. Faux : le fichier est inutilisable. */
    fun finish(): Boolean {
        running = false
        runCatching { thread.join(3_000) }
        return !failed
    }

    companion object {
        /** @throws IOException avec un message à montrer tel quel. */
        @SuppressLint("MissingPermission") // vérifiée par VoiceNoteRecorder.start
        fun start(file: File, onLost: () -> Unit): AudioCapture {
            // 16 kHz : ce qu'attend un reconnaisseur vocal, et bien assez pour la
            // voix. 44,1 kHz en repli, seul taux garanti sur tout appareil.
            var record: AudioRecord? = null
            var rate = 0
            for (candidate in intArrayOf(16_000, 44_100)) {
                val minimum = AudioRecord.getMinBufferSize(candidate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                if (minimum <= 0) continue
                val opened = runCatching {
                    AudioRecord(MediaRecorder.AudioSource.MIC, candidate, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, maxOf(minimum * 2, candidate))
                }.getOrNull() ?: continue
                if (opened.state == AudioRecord.STATE_INITIALIZED) { record = opened; rate = candidate; break }
                opened.release()
            }
            if (record == null) throw IOException("Aucun microphone disponible.")

            file.parentFile?.mkdirs()
            val writer = try {
                AacFileWriter(file, rate)
            } catch (failure: Exception) {
                record.release()
                throw IOException("Impossible de créer le fichier audio.")
            }
            runCatching { record.startRecording() }
            if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                record.release()
                writer.finish()
                throw IOException("Impossible de démarrer le microphone.")
            }
            return AudioCapture(record, writer, rate, onLost).also { it.thread.start() }
        }
    }
}

/** Encode du PCM 16 bits mono en AAC dans un conteneur MPEG-4 (.m4a). */
private class AacFileWriter(file: File, private val sampleRate: Int) {
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
    private val muxer: MediaMuxer
    private val info = MediaCodec.BufferInfo()
    private var track = -1
    private var muxing = false
    private var frames = 0L

    init {
        try {
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, if (sampleRate <= 16_000) 48_000 else 96_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16_384)
            }
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            muxer = MediaMuxer(file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (failure: Exception) {
            codec.release()
            throw failure
        }
    }

    private val timestampUs: Long get() = frames * 1_000_000L / sampleRate

    fun write(pcm: ByteArray, length: Int) {
        var offset = 0
        var waits = 0
        while (offset < length) {
            val index = codec.dequeueInputBuffer(10_000)
            if (index < 0) {
                drain(end = false)
                if (++waits > 300) throw IOException("L'encodeur audio ne répond plus.")
                continue
            }
            val input = codec.getInputBuffer(index) ?: throw IOException("Encodeur audio sans tampon.")
            input.clear()
            // Toujours un nombre entier d'échantillons (2 octets).
            val size = minOf(input.remaining(), length - offset) and 1.inv()
            input.put(pcm, offset, size)
            codec.queueInputBuffer(index, 0, size, timestampUs, 0)
            frames += size / 2
            offset += size
        }
        drain(end = false)
    }

    /** Vide l'encodeur et ferme le fichier. Faux : rien d'utilisable n'a été écrit. */
    fun finish(): Boolean {
        val drained = runCatching {
            var waits = 0
            while (true) {
                val index = codec.dequeueInputBuffer(10_000)
                if (index >= 0) {
                    codec.queueInputBuffer(index, 0, 0, timestampUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
                drain(end = false)
                if (++waits > 300) break
            }
            drain(end = true)
        }.isSuccess
        runCatching { codec.stop() }
        codec.release()
        // stop() échoue si aucun échantillon n'a été écrit (enregistrement vide).
        val closed = runCatching { if (muxing) muxer.stop() }.isSuccess
        runCatching { muxer.release() }
        return drained && closed && muxing
    }

    private fun drain(end: Boolean) {
        var idle = 0
        while (true) {
            val index = codec.dequeueOutputBuffer(info, if (end) 10_000 else 0)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!end || ++idle > 300) return
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxing = true
                }
                index >= 0 -> {
                    val output = codec.getOutputBuffer(index)
                    // Les données de configuration sont déjà dans le format de la piste.
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && muxing && output != null) {
                        output.position(info.offset)
                        output.limit(info.offset + info.size)
                        muxer.writeSampleData(track, output, info)
                    }
                    codec.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }
}

/**
 * Tuyau vers le reconnaisseur vocal. L'écriture se fait sur un fil à part, avec
 * une file bornée : si le reconnaisseur ne lit pas (ou plus), le son en trop est
 * jeté et l'enregistrement du fichier n'est jamais ralenti.
 */
private class PcmPipe {
    val readSide: ParcelFileDescriptor
    private val output: ParcelFileDescriptor.AutoCloseOutputStream
    private val queue = LinkedBlockingQueue<ByteArray>(80) // ~8 s de son
    @Volatile private var closed = false

    init {
        val (read, write) = ParcelFileDescriptor.createPipe()
        readSide = read
        output = ParcelFileDescriptor.AutoCloseOutputStream(write)
        Thread({
            try {
                while (true) {
                    val chunk = queue.take()
                    if (chunk === END) break
                    output.write(chunk)
                }
            } catch (_: Exception) {
                // Lecteur parti ou tuyau fermé : plus rien à écrire.
            } finally {
                runCatching { output.close() }
            }
        }, "alphanote-voice-pipe").apply { isDaemon = true }.start()
    }

    fun offer(chunk: ByteArray) {
        if (!closed) queue.offer(chunk)
    }

    /** Fin du son : le reconnaisseur lit ce qui reste, puis voit la fin du flux. */
    fun end() {
        if (closed) return
        closed = true
        if (!queue.offer(END)) { queue.clear(); queue.offer(END) }
    }

    /** Ferme tout de suite, même si une écriture attend un lecteur absent. */
    fun release() {
        end()
        runCatching { output.close() }
        runCatching { readSide.close() }
    }

    private companion object {
        val END = ByteArray(0)
    }
}

// ---- Transcription en direct ----

/**
 * Transcrit le son reçu par tuyau, par sessions successives du reconnaisseur du
 * système : sur l'appareil d'abord (privé, sans limite de durée), sinon le
 * reconnaisseur par défaut ; langue du système, sinon la même langue dans son
 * pays principal (fr-BE → fr-FR). Une session qui se termine (silence, limite
 * du service) est relancée tant que l'enregistrement dure ; les morceaux sont
 * mis bout à bout.
 */
private class LiveTranscriber(
    private val context: Context,
    private val sampleRate: Int,
    private val onText: (String) -> Unit,
    private val onIssue: (String) -> Unit,
    private val attach: (PcmPipe?) -> Unit
) {
    private data class Attempt(val onDevice: Boolean, val language: String)

    private val main = Handler(Looper.getMainLooper())
    private var attempts: List<Attempt> = emptyList()
    private var attemptIndex = 0
    private var recognizer: SpeechRecognizer? = null
    private var pipe: PcmPipe? = null
    private var active = false
    private var sessionId = 0
    private var sessionRunning = false
    private var sessionHeard = false
    private var everHeard = false
    private var failuresInARow = 0
    private val committed = mutableListOf<String>()
    private var current = ""
    private var waiter: CompletableDeferred<Unit>? = null

    fun start() {
        active = true
        if (Build.VERSION.SDK_INT >= 33) attempts = buildAttempts()
        if (attempts.isEmpty()) {
            // Avant Android 13, le reconnaisseur ouvrirait le micro lui-même et
            // l'un des deux n'aurait que du silence : on garde l'enregistrement.
            onIssue(UNAVAILABLE)
            return
        }
        startSession()
    }

    /** Fin du son : attend le dernier résultat (2,5 s au plus) et rend le texte. */
    suspend fun finish(): String {
        active = false
        main.removeCallbacksAndMessages(null)
        val pipe = pipe
        if (pipe != null && sessionRunning) {
            val waiter = CompletableDeferred<Unit>().also { this.waiter = it }
            pipe.end()
            // Un service qui n'a pas vu la fin du flux rend ce qu'il a sur demande.
            main.postDelayed({ if (sessionRunning) runCatching { recognizer?.stopListening() } }, 700)
            withTimeoutOrNull(2_500) { waiter.await() }
        }
        // Délai dépassé : le texte partiel reste.
        commitCurrent()
        release()
        return transcript()
    }

    fun cancel() {
        active = false
        release()
    }

    private fun release() {
        sessionId += 1
        sessionRunning = false
        main.removeCallbacksAndMessages(null)
        closePipe()
        recognizer?.let { runCatching { it.cancel() }; runCatching { it.destroy() } }
        recognizer = null
    }

    private fun closePipe() {
        attach(null)
        pipe?.release()
        pipe = null
    }

    @RequiresApi(33)
    private fun buildAttempts(): List<Attempt> {
        val system = Locale.getDefault()
        val languages = buildList {
            add(system.toLanguageTag())
            val likely = runCatching { ULocale.addLikelySubtags(ULocale(system.language)) }.getOrNull()
            if (likely != null && likely.country.isNotEmpty()) add("${likely.language}-${likely.country}")
        }.distinct()
        return buildList {
            if (SpeechRecognizer.isOnDeviceRecognitionAvailable(context)) languages.forEach { add(Attempt(true, it)) }
            if (SpeechRecognizer.isRecognitionAvailable(context)) languages.forEach { add(Attempt(false, it)) }
        }
    }

    private fun startSession() {
        if (!active || Build.VERSION.SDK_INT < 33) return
        val attempt = attempts.getOrNull(attemptIndex) ?: return
        val recognizer = recognizer ?: runCatching {
            if (attempt.onDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            else SpeechRecognizer.createSpeechRecognizer(context)
        }.getOrNull()
        val pipe = runCatching { PcmPipe() }.getOrNull()
        if (recognizer == null || pipe == null) {
            pipe?.release()
            nextAttempt()
            return
        }
        this.recognizer = recognizer
        this.pipe = pipe

        sessionId += 1
        val id = sessionId
        sessionRunning = true
        sessionHeard = false
        recognizer.setRecognitionListener(Listener(id))
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, attempt.language)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // Le son vient de notre capture, pas d'une seconde ouverture du micro.
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe.readSide)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            .putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, sampleRate)
            // Session continue quand le service le permet : elle ne finit qu'à
            // la fermeture du son, sans trou entre deux phrases.
            .putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_AUDIO_SOURCE)
            .putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
        attach(pipe)
        runCatching { recognizer.startListening(intent) }.onFailure { sessionEnded(id, SpeechRecognizer.ERROR_CLIENT) }
    }

    private fun heard(id: Int, text: String?) {
        if (id != sessionId || text == null) return
        current = text
        sessionHeard = true
        everHeard = true
        onText(transcript())
    }

    /** [error] null : fin normale (résultat, ou fin d'une session continue). */
    private fun sessionEnded(id: Int, error: Int?) {
        if (id != sessionId) return
        sessionRunning = false
        val wasEmpty = !sessionHeard
        commitCurrent()
        closePipe()
        waiter?.complete(Unit)
        waiter = null
        if (!active) return

        if (error != null && error in FATAL) {
            nextAttempt()
            return
        }
        failuresInARow = if (wasEmpty) failuresInARow + 1 else 0
        if (failuresInARow >= MAX_EMPTY_SESSIONS) {
            // Huit sessions vides d'affilée : ce reconnaisseur ne répond pas.
            if (!everHeard && attemptIndex + 1 < attempts.size) nextAttempt() else giveUp()
            return
        }
        // Une session vide (silence) : courte pause avant de relancer.
        main.postDelayed({ startSession() }, if (wasEmpty) 400L else 0L)
    }

    private fun nextAttempt() {
        recognizer?.let { runCatching { it.destroy() } }
        recognizer = null
        attemptIndex += 1
        failuresInARow = 0
        if (attemptIndex >= attempts.size) giveUp() else main.post { startSession() }
    }

    private fun giveUp() {
        active = false
        release()
        onIssue(if (everHeard) INTERRUPTED else UNAVAILABLE)
    }

    private fun commitCurrent() {
        val text = current.trim()
        current = ""
        if (text.isNotEmpty()) committed.add(text)
        onText(transcript())
    }

    private fun transcript(): String =
        (committed + listOfNotNull(current.trim().takeIf { it.isNotEmpty() })).joinToString(" ")

    private inner class Listener(private val id: Int) : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onPartialResults(partialResults: Bundle?) = heard(id, best(partialResults))

        /** Session continue : un morceau est définitif, la session se poursuit. */
        override fun onSegmentResults(segmentResults: Bundle) {
            if (id != sessionId) return
            heard(id, best(segmentResults))
            failuresInARow = 0
            commitCurrent()
        }

        override fun onEndOfSegmentedSession() = sessionEnded(id, null)

        override fun onResults(results: Bundle?) {
            heard(id, best(results))
            sessionEnded(id, null)
        }

        override fun onError(error: Int) = sessionEnded(id, error)

        private fun best(bundle: Bundle?): String? =
            bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }
    }

    private companion object {
        const val MAX_EMPTY_SESSIONS = 8
        const val UNAVAILABLE = "Transcription indisponible sur cet appareil : l'audio est enregistré sans texte."
        const val INTERRUPTED = "La transcription s'est interrompue : l'audio continue d'être enregistré."

        /** Erreurs qui ne passeront pas en réessayant avec le même reconnaisseur. */
        val FATAL = setOf(
            SpeechRecognizer.ERROR_AUDIO,
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS,
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS,
            SpeechRecognizer.ERROR_SERVER_DISCONNECTED,
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE
        )
    }
}

// ---- Lecture ----

/** Lecture des notes vocales : une seule à la fois, avec pause. */
class VoiceNotePlayer {
    /** Chemin du fichier chargé (en lecture ou en pause), sinon null. */
    var loadedPath by mutableStateOf<String?>(null)
        private set
    var isPlaying by mutableStateOf(false)
        private set

    private var player: MediaPlayer? = null

    /** Lecture, pause ou reprise de ce fichier ; un autre fichier en cours s'arrête. */
    fun toggle(file: File) {
        val current = player
        if (current != null && loadedPath == file.path) {
            runCatching { if (isPlaying) current.pause() else current.start() }
                .onSuccess { isPlaying = !isPlaying }
                .onFailure { stop() }
            return
        }
        stop()
        val created = MediaPlayer()
        try {
            created.setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
            )
            created.setDataSource(file.path)
            created.setOnCompletionListener { stop() }
            created.setOnErrorListener { _, _, _ -> stop(); true }
            created.prepare()
            created.start()
        } catch (_: Exception) {
            created.release()
            return
        }
        player = created
        loadedPath = file.path
        isPlaying = true
    }

    fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        loadedPath = null
        isPlaying = false
    }

    companion object {
        /** Durée du fichier en secondes, null s'il est absent ou illisible. */
        fun duration(file: File): Double? {
            if (!file.exists()) return null
            val retriever = MediaMetadataRetriever()
            return try {
                retriever.setDataSource(file.path)
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()?.let { it / 1000.0 }
            } catch (_: Exception) {
                null
            } finally {
                runCatching { retriever.release() }
            }
        }

        fun clock(seconds: Double): String {
            val total = seconds.roundToInt().coerceAtLeast(0)
            return "${total / 60}:${"%02d".format(total % 60)}"
        }
    }
}
