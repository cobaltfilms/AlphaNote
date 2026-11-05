package be.cobaltfilms.alphanote.ui.editor

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.timer.TimerSession
import kotlin.math.roundToInt
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette

/** Vue du mode minuteur, liée à une [TimerSession] (port de TimerNoteView.swift). */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun TimerNoteView(
    session: TimerSession,
    title: String,
    modifier: Modifier = Modifier,
    onSettingsChange: (TimerSession.Mode, Int) -> Unit = { _, _ -> }
) {
    val palette = LocalAlphaPalette.current
    val snapshot by session.snapshot.collectAsState()
    val presets = listOf(5, 10, 15, 25, 45, 60)
    val isAlarm = snapshot.mode == TimerSession.Mode.ALARM
    var pickingTime by remember { mutableStateOf(false) }
    // App fermée, c'est une notification qui sonne : Android 13+ demande l'accord.
    val context = LocalContext.current
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(snapshot.state) {
        if (snapshot.state == TimerSession.State.RUNNING && snapshot.mode != TimerSession.Mode.STOPWATCH &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
    LaunchedEffect(snapshot.mode, snapshot.targetSeconds, snapshot.alarmTime) {
        onSettingsChange(snapshot.mode, if (isAlarm) snapshot.alarmTime else snapshot.targetSeconds.roundToInt())
    }
    if (pickingTime) {
        val pickerState = rememberTimePickerState(
            initialHour = snapshot.alarmTime / 3600, initialMinute = (snapshot.alarmTime % 3600) / 60, is24Hour = true
        )
        AlertDialog(
            onDismissRequest = { pickingTime = false },
            confirmButton = {
                TextButton(onClick = {
                    session.setAlarmTime(pickerState.hour * 3600 + pickerState.minute * 60)
                    pickingTime = false
                }) { Text("OK", color = palette.accent) }
            },
            dismissButton = { TextButton(onClick = { pickingTime = false }) { Text("Annuler", color = palette.secondary) } },
            text = { TimePicker(state = pickerState) }
        )
    }

    Column(
        modifier = modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Text(title.ifEmpty { session.mode.label }, color = palette.secondary, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TimerSession.Mode.entries.forEach { mode ->
                FilterChip(
                    selected = snapshot.mode == mode,
                    onClick = { session.setMode(mode) },
                    label = { Text(mode.label) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = palette.timer.copy(alpha = 0.22f),
                        selectedLabelColor = palette.timer,
                        labelColor = palette.secondary
                    )
                )
            }
        }

        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(220.dp)) {
            val progress = session.progress
            Canvas(modifier = Modifier.size(220.dp)) {
                val stroke = Stroke(width = 10.dp.toPx(), cap = StrokeCap.Round)
                drawArc(palette.line, -90f, 360f, false, style = stroke)
                if (snapshot.mode != TimerSession.Mode.STOPWATCH) {
                    drawArc(palette.timer, -90f, 360f * progress, false, style = stroke)
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    session.displayTime,
                    style = TextStyle(fontSize = 48.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Light),
                    color = if (snapshot.state == TimerSession.State.FINISHED) palette.timer else palette.text
                )
                Text(
                    if (isAlarm) when (snapshot.state) {
                        TimerSession.State.RUNNING -> "sonne dans ${TimerSession.format(session.remaining)}"
                        TimerSession.State.FINISHED -> "alarme"
                        else -> "désarmée"
                    } else when (snapshot.state) {
                        TimerSession.State.RUNNING -> "en cours"
                        TimerSession.State.PAUSED -> "en pause"
                        TimerSession.State.FINISHED -> "terminé"
                        TimerSession.State.STOPPED -> snapshot.mode.label.lowercase()
                    },
                    color = palette.secondary, fontSize = 12.sp
                )
            }
        }

        if (snapshot.soundPlaying) {
            Button(onClick = { session.stopSound() }, colors = ButtonDefaults.buttonColors(containerColor = palette.timer, contentColor = palette.content)) {
                Text("Arrêter la sonnerie")
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = { session.toggle() },
                colors = ButtonDefaults.buttonColors(containerColor = palette.accent, contentColor = palette.window)
            ) {
                Text(if (isAlarm) {
                    if (snapshot.state == TimerSession.State.RUNNING) "Désarmer" else "Armer"
                } else when (snapshot.state) {
                    TimerSession.State.RUNNING -> "Pause"
                    TimerSession.State.PAUSED -> "Reprendre"
                    TimerSession.State.FINISHED -> "Recommencer"
                    TimerSession.State.STOPPED -> "Démarrer"
                })
            }
            OutlinedButton(onClick = { session.reset() }) { Text("Réinitialiser", color = palette.secondary) }
        }

        if (isAlarm) {
            Spacer(Modifier.height(4.dp))
            Text("Heure de l'alarme — demain si elle est passée", color = palette.secondary, fontSize = 12.sp)
            OutlinedButton(onClick = { pickingTime = true }) {
                Text(TimerSession.clock(snapshot.alarmTime), color = palette.text, fontFamily = FontFamily.Monospace, fontSize = 18.sp)
            }
        } else if (snapshot.mode != TimerSession.Mode.STOPWATCH && snapshot.state != TimerSession.State.RUNNING) {
            Spacer(Modifier.height(4.dp))
            Text("Durée", color = palette.secondary, fontSize = 12.sp)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                presets.forEach { minutes ->
                    val selected = snapshot.targetSeconds.toInt() == minutes * 60
                    TextButton(onClick = { session.setTargetSeconds(minutes * 60.0) }, modifier = Modifier.weight(1f)) {
                        Text("$minutes", color = if (selected) palette.accent else palette.secondary, fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { session.setTargetSeconds(maxOf(5.0, snapshot.targetSeconds - 60)) }) { Text("−1 min", color = palette.secondary) }
                Text(TimerSession.format(snapshot.targetSeconds), color = palette.text, fontFamily = FontFamily.Monospace)
                OutlinedButton(onClick = { session.setTargetSeconds(snapshot.targetSeconds + 60) }) { Text("+1 min", color = palette.secondary) }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedButton(onClick = { session.setTargetSeconds(maxOf(5.0, snapshot.targetSeconds - 5)) }) { Text("−5 s", color = palette.secondary) }
                OutlinedButton(onClick = { session.setTargetSeconds(snapshot.targetSeconds + 5) }) { Text("+5 s", color = palette.secondary) }
            }
        }
    }
}
