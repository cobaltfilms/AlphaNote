package be.cobaltfilms.alphanote.ui.components

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import be.cobaltfilms.alphanote.domain.NoteAttachments
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Images de la note, sous le texte : vignettes, aperçu plein écran avec
 * suppression, et bouton d'ajout. Les images sont lues dans le stockage de l'app.
 */
@Composable
fun NoteImageStrip(
    noteUuid: String,
    names: List<String>,
    onRemove: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalAlphaPalette.current
    var opened by remember { mutableStateOf<String?>(null) }
    // Une image : en grand, à ses proportions. Plusieurs : grille de deux.
    Column(modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (names.size == 1) {
            NoteImageTile(noteUuid, names[0], single = true) { opened = names[0] }
        } else {
            names.chunked(2).forEach { pair ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    pair.forEach { name ->
                        Box(modifier = Modifier.weight(1f)) { NoteImageTile(noteUuid, name, single = false) { opened = name } }
                    }
                    if (pair.size == 1) Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }

    opened?.let { name ->
        NoteImageViewer(
            noteUuid = noteUuid,
            name = name,
            onClose = { opened = null },
            onDelete = { onRemove(name); opened = null }
        )
    }
}

@Composable
private fun NoteImageTile(noteUuid: String, name: String, single: Boolean, onClick: () -> Unit) {
    val palette = LocalAlphaPalette.current
    val bitmap by loadNoteImage(noteUuid, name)
    val loaded = bitmap
    // Seule : proportions de la photo (bornées) ; en grille : carrée, recadrée.
    val ratio = if (single && loaded != null) (loaded.width.toFloat() / loaded.height).coerceIn(0.75f, 2f) else 1f
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(ratio)
            .clip(RoundedCornerShape(14.dp))
            .background(palette.field)
            .clickable(onClickLabel = "Agrandir l'image", onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (loaded != null) {
            Image(bitmap = loaded, contentDescription = "Image de la note", contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Text("Image introuvable", color = palette.secondary, modifier = Modifier.padding(8.dp))
        }
    }
}

@Composable
private fun NoteImageViewer(noteUuid: String, name: String, onClose: () -> Unit, onDelete: () -> Unit) {
    val bitmap by loadNoteImage(noteUuid, name)
    var confirmDelete by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            Row(modifier = Modifier.fillMaxWidth().padding(4.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onClose) { Icon(Icons.Default.Close, contentDescription = "Fermer", tint = Color.White) }
                IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Default.Delete, contentDescription = "Supprimer l'image", tint = Color.White) }
            }
            Box(modifier = Modifier.fillMaxSize().padding(8.dp), contentAlignment = Alignment.Center) {
                bitmap?.let { Image(bitmap = it, contentDescription = "Image de la note", contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize()) }
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Supprimer cette image ?") },
            text = { Text("Elle sera retirée de la note.") },
            confirmButton = { TextButton(onClick = { confirmDelete = false; onDelete() }) { Text("Supprimer") } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Annuler") } }
        )
    }
}

/** Décode l'image hors du thread principal ; null si le fichier n'existe pas (ou plus). */
@Composable
private fun loadNoteImage(noteUuid: String, name: String): State<ImageBitmap?> {
    val appContext = LocalContext.current.applicationContext
    // Change quand la synchro a téléchargé des fichiers : une image absente est relue.
    val revision by NoteAttachments.revision.collectAsState()
    return produceState<ImageBitmap?>(initialValue = null, noteUuid, name, revision) {
    val file = NoteAttachments.file(appContext, noteUuid, name)
    value = withContext(Dispatchers.IO) { BitmapFactory.decodeFile(file.path)?.asImageBitmap() }
    }
}
