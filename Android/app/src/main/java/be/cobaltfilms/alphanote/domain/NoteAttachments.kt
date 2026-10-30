package be.cobaltfilms.alphanote.domain

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import java.io.File
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Images attachées aux notes.
 *
 * Les octets vivent dans `filesDir/attachments/<uuid de la note>/<nom>.jpg` ;
 * le texte de la note ne garde qu'une ligne `![image](att:<nom>)`.
 * Pas encore synchronisées vers Nextcloud ni affichées sur macOS : voir la
 * section « Images » de la documentation des fonctions.
 */
object NoteAttachments {
    private val reference = Regex("""!\[[^\]]*\]\(att:([A-Za-z0-9._-]+)\)""")
    private const val MAX_SIDE = 1600

    /** Noms des images référencées par le texte, dans l'ordre d'apparition. */
    fun names(content: String): List<String> = reference.findAll(content).map { it.groupValues[1] }.toList()

    fun markdown(name: String): String = "![image](att:$name)"

    /** Texte sans les lignes d'images (pour le partage et l'aperçu). */
    fun textWithoutImages(content: String): String =
        content.lines().filterNot { reference.matches(it.trim()) }.joinToString("\n").trim()

    fun file(context: Context, noteUuid: String, name: String): File =
        File(File(context.filesDir, "attachments/$noteUuid"), name)

    /**
     * Copie l'image dans le stockage de l'app, réduite à [MAX_SIDE] px et
     * réencodée en JPEG (orientation EXIF appliquée). Retourne le nom, ou null
     * si le fichier n'est pas une image lisible.
     */
    fun import(context: Context, noteUuid: String, source: Uri): String? {
        val bitmap = decode(context, source) ?: return null
        val name = "${UUID.randomUUID().toString().lowercase()}.jpg"
        val target = file(context, noteUuid, name)
        target.parentFile?.mkdirs()
        val written = runCatching {
            target.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        }.isSuccess
        bitmap.recycle()
        if (!written) { target.delete(); return null }
        return name
    }

    fun remove(context: Context, noteUuid: String, name: String) {
        file(context, noteUuid, name).delete()
    }

    private fun decode(context: Context, source: Uri): Bitmap? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return runCatching {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, source)) { decoder, info, _ ->
                    // Software : indispensable pour compresser en JPEG.
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    val largest = maxOf(info.size.width, info.size.height)
                    if (largest > MAX_SIDE) {
                        val scale = MAX_SIDE.toFloat() / largest
                        decoder.setTargetSize((info.size.width * scale).roundToInt(), (info.size.height * scale).roundToInt())
                    }
                }
            }.getOrNull()
        }
        // Android 8–9 : pas d'ImageDecoder ; orientation EXIF non appliquée.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(source)?.use { BitmapFactory.decodeStream(it, null, bounds) } ?: return null
        val largest = maxOf(bounds.outWidth, bounds.outHeight)
        if (largest <= 0) return null
        var sample = 1
        while (largest / (sample * 2) >= MAX_SIDE) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return context.contentResolver.openInputStream(source)?.use { BitmapFactory.decodeStream(it, null, options) }
    }
}
