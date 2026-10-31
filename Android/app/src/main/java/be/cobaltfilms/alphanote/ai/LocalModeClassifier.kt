package be.cobaltfilms.alphanote.ai

import android.content.Context
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.text.Normalizer

/**
 * Classe une demande dans un mode, sur le téléphone, sans serveur : petit
 * réseau TFLite entraîné sur ml/data/train.csv (ml/train_tflite.py), le même
 * jeu que le modèle Core ML du Mac et de l'iPhone. Rend JEV facultatif.
 */
class LocalModeClassifier(context: Context) {
    data class Decision(val mode: NoteMode, val confidence: Float)

    private val interpreter: Interpreter? = runCatching { Interpreter(load(context, ASSET)) }.getOrNull()

    val isAvailable: Boolean get() = interpreter != null

    @Synchronized
    fun classify(text: String): Decision? {
        val model = interpreter ?: return null
        val input = arrayOf(ModeTokenizer.tokens(text))
        val output = arrayOf(FloatArray(LABELS.size))
        model.run(input, output)
        val best = output[0].indices.maxByOrNull { output[0][it] } ?: return null
        val mode = NoteMode.fromRaw(LABELS[best]) ?: return null
        return Decision(mode, output[0][best])
    }

    private fun load(context: Context, name: String): MappedByteBuffer {
        val fd = context.assets.openFd(name)
        FileInputStream(fd.fileDescriptor).use { stream ->
            return stream.channel.map(FileChannel.MapMode.READ_ONLY, fd.startOffset, fd.declaredLength)
        }
    }

    companion object {
        const val ASSET = "alphanote_mode_classifier.tflite"
        /** En dessous, la décision est trop incertaine : les mots-clés tranchent. */
        const val MINIMUM_CONFIDENCE = 0.45f
        /** Ordre des sorties du modèle (ml/train_tflite.py, LABELS). */
        val LABELS = listOf("code", "list", "math", "plain", "timer")
    }
}

/**
 * Découpe en jetons identique à `tokens()` de ml/train_tflite.py : minuscules
 * sans accents, mots et symboles, chaque mot et ses trigrammes de caractères
 * hachés (FNV-1a 32 bits) dans BUCKETS cases ; 0 = remplissage.
 */
object ModeTokenizer {
    const val BUCKETS = 8192
    const val SEQ_LEN = 128
    private val WORD = Regex("[a-z0-9]+|[^\\sa-z0-9]")

    fun tokens(text: String): IntArray {
        val folded = Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "")
        val ids = ArrayList<Int>()
        for (match in WORD.findAll(folded)) {
            val word = match.value
            ids += bucket("w:$word")
            if (word.length > 1) {
                val padded = "<$word>"
                for (i in 0..padded.length - 3) ids += bucket("t:" + padded.substring(i, i + 3))
            }
        }
        val out = IntArray(SEQ_LEN)
        for (i in 0 until minOf(SEQ_LEN, ids.size)) out[i] = ids[i]
        return out
    }

    private fun bucket(text: String): Int = (fnv1a(text) % BUCKETS.toUInt()).toInt() + 1

    private fun fnv1a(text: String): UInt {
        var h = 0x811C9DC5u
        for (byte in text.toByteArray(Charsets.UTF_8)) {
            h = h xor (byte.toUByte().toUInt())
            h *= 0x01000193u
        }
        return h
    }
}
