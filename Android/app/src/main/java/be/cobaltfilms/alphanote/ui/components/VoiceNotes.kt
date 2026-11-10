package be.cobaltfilms.alphanote.ui.components

import android.os.SystemClock
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Divider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.domain.NoteAttachments
import be.cobaltfilms.alphanote.services.VoiceNotePlayer
import be.cobaltfilms.alphanote.services.VoiceNoteRecorder
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/**
 * Bandeau affiché pendant l'enregistrement d'une note vocale : durée, texte
 * transcrit au fil de la voix, arrêt et abandon (même bandeau que macOS / iOS).
 */
@Composable
fun VoiceRecordingBanner(recorder: VoiceNoteRecorder, onStop: () -> Unit, onCancel: () -> Unit) {
    val palette = LocalAlphaPalette.current
    val startedAt = recorder.startedAt
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(startedAt) {
        while (true) { now = SystemClock.elapsedRealtime(); delay(500) }
    }
    // L'écran qui s'éteint mettrait l'app en arrière-plan, donc fin de l'enregistrement.
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }

    Column(modifier = Modifier.fillMaxWidth().background(palette.field)) {
        Divider(color = palette.line)
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 8.dp, top = 4.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(Icons.Default.GraphicEq, contentDescription = null, tint = palette.timer, modifier = Modifier.size(18.dp))
            Text(
                VoiceNotePlayer.clock(startedAt?.let { (now - it).coerceAtLeast(0) / 1000.0 } ?: 0.0),
                color = palette.text, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            )
            Text("Note vocale en cours", color = palette.secondary, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            TextButton(onClick = onCancel) { Text("Annuler", color = palette.secondary, fontSize = 13.sp) }
            TextButton(onClick = onStop) {
                Icon(Icons.Default.Stop, contentDescription = null, tint = palette.timer, modifier = Modifier.size(16.dp))
                Text("Arrêter", color = palette.timer, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold))
            }
        }
        val issue = recorder.transcriptionIssue
        if (issue != null) {
            Row(
                modifier = Modifier.padding(start = 14.dp, end = 14.dp, bottom = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Icon(Icons.Default.Warning, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(13.dp))
                Text(issue, color = palette.secondary, fontSize = 12.sp)
            }
        } else {
            val transcript = recorder.transcript
            Text(
                // La fin du texte reste visible : c'est elle qui avance.
                if (transcript.isEmpty()) "Parle : le texte apparaît ici." else transcript.takeLast(160),
                color = if (transcript.isEmpty()) palette.secondary else palette.text,
                fontSize = 13.sp, maxLines = 3, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 10.dp)
            )
        }
    }
}

/**
 * Les notes vocales d'une note : une rangée par enregistrement (lecture,
 * durée, suppression). Un fichier absent a été enregistré sur un autre
 * appareil et n'est pas encore arrivé par la synchro Nextcloud.
 */
@Composable
fun VoiceNoteStrip(
    noteUuid: String,
    names: List<String>,
    player: VoiceNotePlayer,
    onDelete: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalAlphaPalette.current
    val context = LocalContext.current.applicationContext
    var pendingDelete by remember { mutableStateOf<String?>(null) }
    // Change quand la synchro a téléchargé des fichiers : les durées sont relues.
    val revision by NoteAttachments.revision.collectAsState()

    Column(modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        names.forEachIndexed { index, name ->
            val file = remember(noteUuid, name) { NoteAttachments.file(context, noteUuid, name) }
            // -1 : pas encore lue ; null : fichier absent ou illisible.
            val duration by produceState<Double?>(initialValue = -1.0, noteUuid, name, revision) {
                value = withContext(Dispatchers.IO) { VoiceNotePlayer.duration(file) }
            }
            val available = duration != null
            val loaded = player.loadedPath == file.path
            val playing = loaded && player.isPlaying
            Row(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.field).padding(start = 2.dp, end = 2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { player.toggle(file) }, enabled = available && duration != -1.0) {
                    Icon(
                        if (playing) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = if (playing) "Mettre en pause" else "Écouter la note vocale ${index + 1}",
                        tint = if (available) palette.accent else palette.secondary.copy(alpha = 0.4f)
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        if (names.size > 1) "Note vocale ${index + 1}" else "Note vocale",
                        color = if (available) palette.text else palette.secondary,
                        style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium)
                    )
                    Text(
                        when (val seconds = duration) {
                            null -> "Enregistrée sur un autre appareil"
                            -1.0 -> "…"
                            else -> VoiceNotePlayer.clock(seconds) + if (loaded && !playing) " · en pause" else ""
                        },
                        color = palette.secondary, fontSize = 12.sp
                    )
                }
                Spacer(Modifier.size(4.dp))
                IconButton(onClick = { pendingDelete = name }) {
                    Icon(Icons.Default.Delete, contentDescription = "Supprimer l'enregistrement", tint = palette.secondary, modifier = Modifier.size(18.dp))
                }
            }
        }
    }

    pendingDelete?.let { name ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Supprimer cet enregistrement ?") },
            text = { Text("Le texte transcrit reste dans la note.") },
            confirmButton = { TextButton(onClick = { pendingDelete = null; onDelete(name) }) { Text("Supprimer", color = palette.timer) } },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Annuler") } }
        )
    }
}
