package be.cobaltfilms.alphanote.ui.components

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * Dictée de la barre de commande — pendant Android de Services/SpeechRecognizer.swift :
 * texte partiel au fil de la parole, arrêt sur silence (géré par le système),
 * puis [onFinished] avec la transcription finale.
 */
class VoiceDictation(private val context: Context) {
    var transcript by mutableStateOf("")
        private set
    var isListening by mutableStateOf(false)
        private set
    var error by mutableStateOf<String?>(null)
        private set

    private var recognizer: SpeechRecognizer? = null
    var onFinished: (String) -> Unit = {}

    val isAvailable: Boolean get() = SpeechRecognizer.isRecognitionAvailable(context)

    fun start() {
        if (isListening) return
        error = null
        transcript = ""
        if (!isAvailable) {
            error = "La reconnaissance vocale n'est pas disponible sur cet appareil."
            return
        }
        val sr = recognizer ?: SpeechRecognizer.createSpeechRecognizer(context).also { recognizer = it }
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onPartialResults(partialResults: Bundle?) {
                best(partialResults)?.let { transcript = it }
            }

            override fun onResults(results: Bundle?) {
                best(results)?.let { transcript = it }
                isListening = false
                if (transcript.isNotBlank()) onFinished(transcript)
            }

            override fun onError(code: Int) {
                isListening = false
                error = when (code) {
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "AlphaNote n'a pas accès au microphone."
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Rien entendu."
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Reconnaissance vocale : pas de réseau."
                    else -> "Erreur de reconnaissance vocale ($code)."
                }
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, java.util.Locale.getDefault().toLanguageTag())
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 3_000L)
        isListening = true
        sr.startListening(intent)
    }

    /** Arrêt manuel : le système rend quand même ce qu'il a entendu (onResults). */
    fun stop() {
        if (isListening) recognizer?.stopListening()
    }

    fun release() {
        recognizer?.destroy()
        recognizer = null
        isListening = false
    }

    private fun best(bundle: Bundle?): String? =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }
}
