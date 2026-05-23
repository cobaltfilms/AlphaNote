package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.domain.ListModeFormatter
import be.cobaltfilms.alphanote.ui.theme.ListColor

/**
 * Écran note checklist — mode liste avec checkboxes.
 * Portage de UI/NoteViews/ListNoteView.swift (macOS).
 *
 * Parse le contenu avec ListModeFormatter et affiche chaque élément
 * avec une checkbox. Supporte les commentaires (//) et les headings (#).
 */
@Composable
fun ListNoteScreen(
    text: String,
    onTextChange: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    // Normaliser le contenu pour le parsing
    val normalizedContent = remember(text) {
        ListModeFormatter.normalizeForListMode(text)
    }

    val lines = remember(normalizedContent) {
        normalizedContent.lines().filter { it.isNotEmpty() }
    }

    // État des checkboxes (index → coché)
    val checkedState = remember { mutableStateMapOf<Int, Boolean>() }

    // Sauter le header "list"
    val displayLines = remember(lines) {
        if (lines.isNotEmpty() && ListModeFormatter.isListHeader(lines[0])) {
            lines.drop(1)
        } else {
            lines
        }
    }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        // Champ d'édition
        item {
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
                                "Mode liste — chaque ligne = un élément.\n// pour un commentaire, # pour un titre.\nSéparez par des virgules pour créer plusieurs éléments.",
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
        }

        item { Spacer(modifier = Modifier.height(16.dp)) }

        // Vue interactive avec checkboxes
        itemsIndexed(displayLines) { index, line ->
            val isComment = ListModeFormatter.isComment(line)
            val isHeading = ListModeFormatter.isHeading(line)

            when {
                isComment -> {
                    Text(
                        text = line,
                        style = MaterialTheme.typography.bodyMedium.copy(
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                            fontSize = 13.sp
                        ),
                        modifier = Modifier.padding(vertical = 2.dp)
                    )
                }
                isHeading -> {
                    Text(
                        text = line,
                        style = MaterialTheme.typography.titleMedium.copy(
                            color = MaterialTheme.colorScheme.primary,
                            fontSize = 16.sp
                        ),
                        modifier = Modifier.padding(vertical = 4.dp)
                    )
                }
                else -> {
                    val isChecked = checkedState[index] ?: false

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(
                            checked = isChecked,
                            onCheckedChange = { checkedState[index] = it },
                            colors = CheckboxDefaults.colors(
                                checkedColor = ListColor,
                                uncheckedColor = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = line,
                            style = MaterialTheme.typography.bodyLarge.copy(
                                textDecoration = if (isChecked) TextDecoration.LineThrough else TextDecoration.None,
                                color = if (isChecked) {
                                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                }
                            ),
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
        }
    }
}
