package be.cobaltfilms.alphanote.domain

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import java.io.File
import java.util.UUID
import kotlin.math.roundToInt

/**
 * Pièces jointes des notes (images et notes vocales), même format que la
 * version Apple (`Models/NoteAttachments.swift`).
 *
 * Les octets vivent dans `filesDir/attachments/<uuid de la note>/<nom>` ; le
 * texte de la note ne garde qu'une ligne `![image](att:<nom>.jpg)` ou
 * `![audio](att:<nom>.m4a)`. La synchro Nextcloud fait circuler les fichiers
 * à côté des notes (`sync/AttachmentSync.kt`) : envoyés s'ils manquent sur le
 * serveur, téléchargés s'ils manquent ici, jamais modifiés. La synchro Wi-Fi
 * directe ne transporte que le texte.
 */
object NoteAttachments {
    private val reference = Regex("""!\[[^\]]*\]\(att:([A-Za-z0-9._-]+)\)""")
    private const val MAX_SIDE = 1600

    /**
     * Augmente quand la synchro a téléchargé des fichiers : les vues qui ont
     * constaté une absence (note vocale, vignette) relisent le disque.
     */
    val revision = MutableStateFlow(0)

    /** Noms des pièces jointes référencées par le texte, dans l'ordre d'apparition. */
    fun names(content: String): List<String> = reference.findAll(content).map { it.groupValues[1] }.toList()

    /** Extensions des enregistrements (m4a sur Apple et Android, wav en repli). */
    val audioExtensions: Set<String> = setOf("m4a", "wav")

    fun isAudio(name: String): Boolean = name.substringAfterLast('.', "").lowercase() in audioExtensions

    /** Images seulement, dans l'ordre d'apparition (galeries). */
    fun imageNames(content: String): List<String> = names(content).filterNot(::isAudio)

    /** Notes vocales seulement, dans l'ordre d'apparition. */
    fun audioNames(content: String): List<String> = names(content).filter(::isAudio)

    fun markdown(name: String): String = if (isAudio(name)) "![audio](att:$name)" else "![image](att:$name)"

    /** Nom de fichier d'un nouvel enregistrement. */
    fun newAudioName(): String = "${UUID.randomUUID().toString().lowercase()}.m4a"

    /** Ligne faite d'une seule pièce jointe (image ou note vocale). */
    fun isImageLine(line: String): Boolean = reference.matches(NoteThemes.trimSpaces(line))

    /** Ligne faite d'une seule référence vers une note vocale. */
    fun isAudioLine(line: String): Boolean = isImageLine(line) && names(line).firstOrNull()?.let(::isAudio) == true

    /**
     * Ajoute une note vocale : la transcription rejoint le texte (paragraphe à
     * part), la référence du fichier va en fin de note avec les autres pièces
     * jointes. Le thème éventuel reste la dernière ligne de texte.
     */
    fun addingVoiceNote(content: String, audioName: String, transcript: String): String {
        val theme = NoteThemes.explicit(content)
        val lines = NoteThemes.removingTheme(content).split("\n")
        var body = lines.filterNot(::isImageLine).joinToString("\n").trimEnd('\n', ' ')
        val spoken = transcript.trim()
        if (spoken.isNotEmpty()) body += if (body.isEmpty()) spoken else "\n\n$spoken"
        body = NoteThemes.settingTheme(theme, body)
        val tail = (names(content) + audioName).joinToString("\n") { markdown(it) }
        return if (body.isEmpty()) tail else body + "\n" + tail
    }

    /** Retire la référence d'une pièce jointe (la ligne entière). */
    fun removingReference(name: String, content: String): String =
        content.split("\n").filterNot { it.contains("(att:$name)") && isImageLine(it) }.joinToString("\n")

    /**
     * Texte montré dans l'éditeur : la note sans ses lignes de pièces jointes
     * (images en galerie, notes vocales en rangées de lecture). Inverse exact de [withImages] tant que les
     * images sont en fin de note, ce que [withImages] garantit.
     */
    fun visibleText(content: String): String =
        content.split("\n").filterNot { reference.matches(it.trim()) }.joinToString("\n")

    /** Contenu stocké : le texte de l'éditeur, puis les références (images et audio) de [content]. */
    fun withImages(visible: String, content: String): String {
        val refs = names(content)
        if (refs.isEmpty()) return visible
        return visible + "\n" + refs.joinToString("\n") { markdown(it) }
    }

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

    /** Supprime tous les fichiers joints d'une note. */
    fun removeAll(context: Context, noteUuid: String) {
        File(context.filesDir, "attachments/$noteUuid").deleteRecursively()
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
