package be.cobaltfilms.alphanote.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import be.cobaltfilms.alphanote.domain.ReminderKind
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.temporal.ChronoUnit

/**
 * Création d'un rappel : une date, une heure, et une ou plusieurs alertes.
 * Saisie au clavier (AAAA-MM-JJ, HH:MM) : pas de sélecteur natif, donc pas
 * d'API expérimentale ; le sélecteur pourra venir plus tard.
 */
@Composable
fun ReminderDialog(onDismiss: () -> Unit, onConfirm: (LocalDateTime, Set<ReminderKind>) -> Unit) {
    val palette = LocalAlphaPalette.current
    val initial = remember { LocalDateTime.now().plusHours(1).truncatedTo(ChronoUnit.MINUTES) }
    var date by remember { mutableStateOf(initial.toLocalDate().toString()) }
    var time by remember { mutableStateOf(initial.toLocalTime().toString().take(5)) }
    var kinds by remember { mutableStateOf(setOf(ReminderKind.NOTIFICATION, ReminderKind.SONNERIE)) }

    val parsed = remember(date, time) {
        runCatching { LocalDateTime.of(LocalDate.parse(date), LocalTime.parse(time)) }.getOrNull()
    }
    val inFuture = parsed != null && parsed.isAfter(LocalDateTime.now())

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Rappel") },
        text = {
            Column {
                OutlinedTextField(
                    value = date, onValueChange = { date = it }, singleLine = true,
                    label = { Text("Date (AAAA-MM-JJ)") }, modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = time, onValueChange = { time = it }, singleLine = true,
                    label = { Text("Heure (HH:MM)") }, modifier = Modifier.fillMaxWidth().padding(top = 8.dp)
                )
                Text("Alertes", modifier = Modifier.padding(top = 12.dp), style = androidx.compose.material3.MaterialTheme.typography.titleSmall)
                ReminderKind.entries.forEach { kind ->
                    Row(
                        modifier = Modifier.fillMaxWidth()
                            .clickable { kinds = if (kind in kinds) kinds - kind else kinds + kind }
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(checked = kind in kinds, onCheckedChange = null)
                        Text(kindLabel(kind), modifier = Modifier.padding(start = 8.dp))
                    }
                }
                when {
                    parsed == null -> Text("Date ou heure invalide.", color = palette.timer)
                    !inFuture -> Text("Cette date est déjà passée.", color = palette.timer)
                    kinds.isEmpty() -> Text("Choisissez au moins une alerte.", color = palette.timer)
                }
            }
        },
        confirmButton = {
            TextButton(
                enabled = inFuture && kinds.isNotEmpty(),
                onClick = { parsed?.let { onConfirm(it, kinds) } }
            ) { Text("Ajouter") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Annuler") } }
    )
}

private fun kindLabel(kind: ReminderKind): String = when (kind) {
    ReminderKind.NOTIFICATION -> "Notification"
    ReminderKind.SONNERIE -> "Sonnerie"
    ReminderKind.VIBRATION -> "Vibration"
}
