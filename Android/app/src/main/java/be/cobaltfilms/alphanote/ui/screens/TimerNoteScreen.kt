package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.theme.AlphaSpacing
import be.cobaltfilms.alphanote.ui.theme.TimerColor
import kotlinx.coroutines.delay

@Composable
fun TimerNoteScreen(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier
) {
    val (timerType, initialSeconds) = remember(value.text) { parseTimerConfig(value.text) }

    var elapsedSeconds by remember { mutableIntStateOf(0) }
    var isRunning by remember { mutableStateOf(false) }
    var isBreak by remember { mutableStateOf(false) }

    LaunchedEffect(isRunning, isBreak, timerType, initialSeconds) {
        if (isRunning) {
            while (true) {
                delay(1000L)
                elapsedSeconds++

                if (timerType == TimerType.COUNTDOWN && elapsedSeconds >= initialSeconds) {
                    isRunning = false
                    elapsedSeconds = initialSeconds
                }

                if (timerType == TimerType.POMODORO) {
                    val workDuration = 25 * 60
                    val breakDuration = 5 * 60
                    val period = if (!isBreak) workDuration else breakDuration

                    if (elapsedSeconds >= period) {
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

    val displayTime = remember(elapsedSeconds, timerType, initialSeconds) {
        formatTimer(elapsedSeconds, timerType, initialSeconds)
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = AlphaSpacing.screenHorizontal, vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focusRequester),
            textStyle = TextStyle(
                fontSize = 16.sp,
                lineHeight = 24.sp,
                color = MaterialTheme.colorScheme.onSurface
            ),
            decorationBox = { innerTextField ->
                Box {
                    if (value.text.isEmpty()) {
                        Text(
                            "Mode timer\n`timer` = chronomètre\n`timer: 25:00` = compte à rebours\n`timer: pomodoro` = 25/5",
                            style = TextStyle(
                                fontSize = 16.sp,
                                lineHeight = 24.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                            )
                        )
                    }
                    innerTextField()
                }
            }
        )

        LaunchedEffect(Unit) { focusRequester.requestFocus() }

        Spacer(modifier = Modifier.height(26.dp))

        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = TimerColor.copy(alpha = 0.1f))
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(22.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = displayTime,
                    style = TextStyle(
                        fontSize = 46.sp,
                        fontFamily = FontFamily.Monospace,
                        color = TimerColor
                    )
                )

                if (isBreak) {
                    Text(
                        "Pause",
                        style = MaterialTheme.typography.labelLarge,
                        color = TimerColor
                    )
                }

                Spacer(modifier = Modifier.height(14.dp))

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Button(
                        onClick = { isRunning = !isRunning },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (isRunning) MaterialTheme.colorScheme.error else TimerColor
                        )
                    ) {
                        Text(if (isRunning) "Pause" else "Démarrer")
                    }

                    OutlinedButton(
                        onClick = {
                            isRunning = false
                            elapsedSeconds = 0
                            isBreak = false
                        }
                    ) {
                        Text("Reset")
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(12.dp))

        Text(
            text = when (timerType) {
                TimerType.STOPWATCH -> "Chronomètre"
                TimerType.COUNTDOWN -> "Compte à rebours (${formatSeconds(initialSeconds)})"
                TimerType.POMODORO -> "Pomodoro (25 min / 5 min)"
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

enum class TimerType { STOPWATCH, COUNTDOWN, POMODORO }

private fun parseTimerConfig(text: String): Pair<TimerType, Int> {
    val firstLine = text.lines().firstOrNull()?.trim()?.lowercase() ?: return Pair(TimerType.STOPWATCH, 0)

    if (firstLine == "timer") return Pair(TimerType.STOPWATCH, 0)

    if (firstLine.startsWith("timer:")) {
        val config = firstLine.substringAfter("timer:").trim()

        if (config == "pomodoro" || config == "pomo") {
            return Pair(TimerType.POMODORO, 25 * 60)
        }

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

        config.toIntOrNull()?.let { secs ->
            if (secs > 0) return Pair(TimerType.COUNTDOWN, secs)
        }
    }

    return Pair(TimerType.STOPWATCH, 0)
}

private fun formatTimer(elapsed: Int, type: TimerType, initial: Int): String {
    return when (type) {
        TimerType.STOPWATCH -> formatSeconds(elapsed)
        TimerType.COUNTDOWN -> formatSeconds((initial - elapsed).coerceAtLeast(0))
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
