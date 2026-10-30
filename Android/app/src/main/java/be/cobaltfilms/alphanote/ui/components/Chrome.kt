package be.cobaltfilms.alphanote.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.compose.ui.unit.sp
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material.icons.filled.Notes
import androidx.compose.material.icons.filled.Timer
import be.cobaltfilms.alphanote.ai.KeywordIntentRouter
import be.cobaltfilms.alphanote.ai.NoteMode
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette

fun NoteMode.icon(): ImageVector = when (this) {
    NoteMode.MATH -> Icons.Default.Functions
    NoteMode.LIST -> Icons.Default.Checklist
    NoteMode.TIMER -> Icons.Default.Timer
    NoteMode.CODE -> Icons.Default.Code
    NoteMode.PLAIN -> Icons.Default.Notes
}

/** Pastille de mode (menu déroulant pour changer de mode), comme sur macOS. */
@Composable
fun ModeChip(mode: NoteMode, onSelect: (NoteMode) -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalAlphaPalette.current
    var expanded by remember { mutableStateOf(false) }
    Row(
        modifier = modifier
            .background(palette.modeBackground(mode), RoundedCornerShape(50))
            .clickable { expanded = true }
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Icon(mode.icon(), contentDescription = null, tint = palette.mode(mode), modifier = Modifier.size(13.dp))
        Text(mode.label, color = palette.mode(mode), style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
    }
    DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
        NoteMode.entries.forEach { candidate ->
            DropdownMenuItem(
                text = { Text(candidate.title) },
                leadingIcon = { Icon(candidate.icon(), contentDescription = null, tint = palette.mode(candidate)) },
                enabled = candidate != mode,
                onClick = { expanded = false; onSelect(candidate) }
            )
        }
    }
}

/** Demande en langage naturel (équivalent du champ ⌘K). */
@Composable
fun CommandField(
    currentKeyword: String?,
    isRouting: Boolean,
    onSubmit: (String) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier
) {
    val palette = LocalAlphaPalette.current
    var draft by remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val preview = remember(draft, currentKeyword) { KeywordIntentRouter.classify(draft, currentKeyword) }

    LaunchedEffect(Unit) { focusRequester.requestFocus() }

    // Dictée : le texte remplit le champ au fil de la parole, puis la demande
    // part toute seule après le silence (comme sur Mac).
    val context = LocalContext.current
    val dictation = remember { VoiceDictation(context) }
    dictation.onFinished = { text -> if (!isRouting) { onSubmit(text); draft = "" } }
    DisposableEffect(Unit) { onDispose { dictation.release() } }
    LaunchedEffect(dictation.transcript) { if (dictation.transcript.isNotEmpty()) draft = dictation.transcript }
    LaunchedEffect(dictation.error) { dictation.error?.let { Toast.makeText(context, it, Toast.LENGTH_SHORT).show() } }
    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) dictation.start()
        else Toast.makeText(context, "AlphaNote a besoin du microphone pour la dictée. Autorisez-le dans Réglages › Applis › AlphaNote.", Toast.LENGTH_LONG).show()
    }
    val toggleDictation = {
        when {
            dictation.isListening -> dictation.stop()
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED -> dictation.start()
            else -> micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .background(palette.field, RoundedCornerShape(14.dp))
            .border(1.dp, palette.accent.copy(alpha = 0.6f), RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = palette.accent, modifier = Modifier.size(16.dp))
        BasicTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier.weight(1f).focusRequester(focusRequester),
            singleLine = true,
            enabled = !isRouting,
            textStyle = TextStyle(color = palette.text, fontSize = 14.sp),
            cursorBrush = SolidColor(palette.accent),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (draft.isNotBlank()) { onSubmit(draft); draft = "" } }),
            decorationBox = { inner ->
                if (draft.isEmpty()) Text("« minuteur 25 min », « courses : pain, lait », « 12 km to mi »", color = palette.secondary.copy(alpha = 0.7f), fontSize = 13.sp, maxLines = 1)
                inner()
            }
        )
        if (draft.isNotBlank() && preview != NoteMode.PLAIN) {
            Text(
                "${preview.label} ?",
                color = palette.mode(preview),
                style = TextStyle(fontSize = 9.sp, fontWeight = FontWeight.Bold),
                modifier = Modifier.background(palette.modeBackground(preview), RoundedCornerShape(50)).padding(horizontal = 7.dp, vertical = 3.dp)
            )
        }
        if (!isRouting) {
            IconButton(onClick = toggleDictation, modifier = Modifier.size(40.dp)) {
                Icon(
                    if (dictation.isListening) Icons.Default.GraphicEq else Icons.Default.Mic,
                    contentDescription = if (dictation.isListening) "Arrêter l'écoute" else "Dicter",
                    tint = if (dictation.isListening) palette.timer else palette.accent,
                    modifier = Modifier.size(22.dp)
                )
            }
        }
        if (isRouting) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = palette.accent)
        } else {
            IconButton(onClick = { if (draft.isNotBlank()) { onSubmit(draft); draft = "" } }, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Default.Send, contentDescription = "Envoyer", tint = palette.accent, modifier = Modifier.size(16.dp))
            }
        }
        IconButton(onClick = onClose, modifier = Modifier.size(28.dp)) {
            Icon(Icons.Default.Close, contentDescription = "Fermer", tint = palette.secondary, modifier = Modifier.size(16.dp))
        }
    }
}

/** Point coloré d'un mode (liste des notes). */
@Composable
fun ModeDot(mode: NoteMode) {
    val palette = LocalAlphaPalette.current
    Spacer(
        Modifier.size(8.dp).background(palette.mode(mode).copy(alpha = if (mode == NoteMode.PLAIN) 0.35f else 1f), CircleShape)
    )
}

object NoteDates {
    /** Date courte façon liste de notes : heure si aujourd'hui, « hier », jour dans les 7 jours, sinon « 23 oct. ». */
    fun shortDate(millis: Long, now: Long = System.currentTimeMillis()): String {
        val locale = java.util.Locale.FRANCE
        val cal = java.util.Calendar.getInstance()
        val nowCal = java.util.Calendar.getInstance().apply { timeInMillis = now }
        cal.timeInMillis = millis
        fun sameDay(a: java.util.Calendar, b: java.util.Calendar) =
            a.get(java.util.Calendar.YEAR) == b.get(java.util.Calendar.YEAR) && a.get(java.util.Calendar.DAY_OF_YEAR) == b.get(java.util.Calendar.DAY_OF_YEAR)
        if (sameDay(cal, nowCal)) return java.text.SimpleDateFormat("HH:mm", locale).format(java.util.Date(millis))
        val yesterday = (nowCal.clone() as java.util.Calendar).apply { add(java.util.Calendar.DAY_OF_YEAR, -1) }
        if (sameDay(cal, yesterday)) return "hier"
        val weekAgo = (nowCal.clone() as java.util.Calendar).apply { add(java.util.Calendar.DAY_OF_YEAR, -6) }
        if (millis > weekAgo.timeInMillis) return java.text.SimpleDateFormat("EEE", locale).format(java.util.Date(millis))
        if (cal.get(java.util.Calendar.YEAR) == nowCal.get(java.util.Calendar.YEAR)) return java.text.SimpleDateFormat("d MMM", locale).format(java.util.Date(millis))
        return java.text.SimpleDateFormat("MMM yyyy", locale).format(java.util.Date(millis))
    }
}
