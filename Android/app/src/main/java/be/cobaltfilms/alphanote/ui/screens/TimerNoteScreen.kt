package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.theme.TimerColor
import kotlinx.coroutines.delay

/**
 * Écran note timer — chronomètre / compte à rebours / pomodoro.
 * Portage de UI/NoteViews/TimerNoteView.swift (macOS).
 *
 * Parse la première ligne pour le type de timer :
 * - "timer" : chronomètre simple (compte vers le haut)
 * - "timer: 25:00" : compte à rebours (minutes:secondes)
 * - "timer: pomodoro" : 25 min travail + 5 min pause
 */
@Composable
fun TimerNoteScreen(
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    // Parser la configuration du timer
    val (timerType, initialSeconds) = remember(text) { parseTimerConfig(text) }

    // État du timer
    var elapsedSeconds by remember { mutableIntStateOf(0) }
    var isRunning by remember { mutableStateOf(false) }
    var isBreak by remember { mutableStateOf(false) } // pour pomodoro

    // Lancer le timer
    LaunchedEffect(isRunning, isBreak) {
        if (isRunning) {
            while (true) {
                delay(1000L)
                elapsedSeconds++

                if (timerType == TimerType.COUNTDOWN) {
                    if (elapsedSeconds >= initialSeconds) {
                        isRunning = false
                        elapsedSeconds = initialSeconds
                    }
                } else if (timerType == TimerType.POMODORO) {
                    val workDuration = 25 * 60
                    val breakDuration = 5 * 60
                    val totalPeriod = if (!isBreak) workDuration else breakDuration

                    if (elapsedSeconds >= totalPeriod) {
                        if (!isBreak) {
                            isBreak = true
                            elapsedSeconds = 0
                        } else {
                            isRunning = false
                            isBreak = false
                            elapsedSeconds = 0
                        }
                    }
                }
            }
        }
    }

    // Formatage du temps
    val displayTime = remember(elapsedSeconds) {
        formatTimer(elapsedSeconds, timerType, initialSeconds)
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Champ d'édition
        BasicTextField(
            value = text,
            onValueChange = onTextChange,
            modifier = Modifier.fillMaxWidth(),
            textStyle = TextStyle(
                fontSize = 16.sp,
                lineHeight = 24.sp,
                color = MaterialTheme.colorScheme.onSurface
            ),
            decorationBox = { innerTextField ->
                Box {
                    if (text.isEmpty()) {
                        Text(
                            "Mode timer — tapez timer en première ligne.\ntimer: 25:00 pour un compte à rebours\ntimer: pomodoro pour la méthode Pomodoro\n(25 min travail, 5 min pause)",
                            style = TextStyle(
                                fontSize = 16.sp,
                                lineHeight = 24.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                            )
                        )
                    }
                    innerTextField()
                }
            }
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Affichage du timer
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 32.dp),
            colors = CardDefaults.cardColors(
                containerColor = TimerColor.copy(alpha = 0.1f)
            )
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = displayTime,
                    style = TextStyle(
                        fontSize = 48.sp,
                        fontFamily = FontFamily.Monospace,
                        color = TimerColor
                    )
                )

                if (isBreak) {
                    Text(
                        "PAUSE",
                        style = MaterialTheme.typography.labelLarge,
                        color = TimerColor
                    )
                }

                Spacer(modifier = Modifier.height(16.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = { isRunning = !isRunning },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (isRunning) {
                                MaterialTheme.colorScheme.error
                            } else {
                                TimerColor
                            }
                        )
                    ) {
                        Text(if (isRunning) "⏸ Pause" else "▶ Démarrer")
                    }

                    OutlinedButton(
                        onClick = {
                            isRunning = false
                            elapsedSeconds = 0
                            isBreak = false
                        }
                    ) {
                        Text("↺ Reset")
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Type de timer
        Text(
            text = when (timerType) {
                TimerType.STOPWATCH -> "⏱ Chronomètre"
                TimerType.COUNTDOWN -> "⏲ Compte à rebours (${formatSeconds(initialSeconds)})"
                TimerType.POMODORO -> "🍅 Pomodoro (25 min / 5 min)"
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

// ---- Modèle du timer ----

enum class TimerType { STOPWATCH, COUNTDOWN, POMODORO }

/**
 * Parse la configuration du timer depuis le contenu.
 * Format : "timer" ou "timer: 25:00" ou "timer: pomodoro"
 */
private fun parseTimerConfig(text: String): Pair<TimerType, Int> {
    val firstLine = text.lines().firstOrNull()?.trim()?.lowercase() ?: return Pair(TimerType.STOPWATCH, 0)

    if (firstLine == "timer") return Pair(TimerType.STOPWATCH, 0)

    if (firstLine.startsWith("timer:")) {
        val config = firstLine.substringAfter("timer:").trim()

        if (config == "pomodoro" || config == "pomo") {
            return Pair(TimerType.POMODORO, 25 * 60)
        }

        // Essayer le format MM:SS
        val timeRegex = Regex("(\\d+):(\\d+)")
        val match = timeRegex.find(config)
        if (match != null) {
            val minutes = match.groupValues[1].toIntOrNull() ?: 0
            val seconds = match.groupValues[2].toIntOrNull() ?: 0
            val totalSeconds = minutes * 60 + seconds
            if (totalSeconds > 0) {
                return Pair(TimerType.COUNTDOWN, totalSeconds)
            }
        }

        // Essayer format secondes
        config.toIntOrNull()?.let { secs ->
            if (secs > 0) return Pair(TimerType.COUNTDOWN, secs)
        }
    }

    return Pair(TimerType.STOPWATCH, 0)
}

/**
 * Formate le temps du timer pour l'affichage.
 */
private fun formatTimer(elapsed: Int, type: TimerType, initial: Int): String {
    return when (type) {
        TimerType.STOPWATCH -> formatSeconds(elapsed)
        TimerType.COUNTDOWN -> {
            val remaining = (initial - elapsed).coerceAtLeast(0)
            formatSeconds(remaining)
        }
        TimerType.POMODORO -> formatSeconds(elapsed)
    }
}

private fun formatSeconds(totalSeconds: Int): String {
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60

    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%02d:%02d".format(minutes, seconds)
    }
}
