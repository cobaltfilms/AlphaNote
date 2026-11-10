package be.cobaltfilms.alphanote.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.domain.NoteThemes
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette

/**
 * Choix du thème d'une note : un thème existant, un nouveau, ou aucun (le
 * thème redevient alors celui que le classement propose).
 */
@Composable
fun ThemeDialog(
    current: String?,
    isExplicit: Boolean,
    themes: List<String>,
    onPick: (String?) -> Unit,
    onDismiss: () -> Unit
) {
    val palette = LocalAlphaPalette.current
    var draft by remember { mutableStateOf("") }
    val commitDraft = { NoteThemes.normalized(draft).takeIf { it.isNotEmpty() }?.let(onPick) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Thème de la note") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (current != null) {
                    Text(
                        if (isExplicit) "Thème actuel : $current" else "Thème proposé : $current (non écrit dans la note)",
                        color = palette.secondary, fontSize = 13.sp
                    )
                }
                OutlinedTextField(
                    value = draft, onValueChange = { draft = it.take(NoteThemes.MAX_LENGTH) }, singleLine = true,
                    label = { Text("Nouveau thème") },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { commitDraft() }),
                    modifier = Modifier.fillMaxWidth()
                )
                if (themes.isNotEmpty()) {
                    Column(modifier = Modifier.heightIn(max = 220.dp).verticalScroll(rememberScrollState())) {
                        themes.forEach { theme ->
                            Row(
                                modifier = Modifier.fillMaxWidth().clickable { onPick(theme) }.padding(horizontal = 4.dp, vertical = 11.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(theme, color = palette.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
                                if (current != null && NoteThemes.key(current) == NoteThemes.key(theme)) {
                                    Icon(
                                        if (isExplicit) Icons.Default.Check else Icons.Default.AutoAwesome,
                                        contentDescription = if (isExplicit) "Thème actuel" else "Thème proposé",
                                        tint = palette.secondary, modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { commitDraft() }, enabled = NoteThemes.normalized(draft).isNotEmpty()) { Text("Créer") }
        },
        dismissButton = {
            Row {
                // Retire la ligne : le thème redevient celui que le classement propose.
                if (isExplicit) TextButton(onClick = { onPick(null) }) { Text("Aucun thème") }
                TextButton(onClick = onDismiss) { Text("Annuler") }
            }
        }
    )
}
