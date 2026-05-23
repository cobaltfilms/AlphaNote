package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.theme.MathColor

/**
 * Écran note mathématique — évaluation inline.
 * Portage de UI/NoteViews/MathNoteView.swift (macOS).
 *
 * Chaque ligne terminée par "=" est évaluée automatiquement.
 * Le résultat s'affiche en ligne, en dessous.
 */
@Composable
fun MathNoteScreen(
    text: String,
    onTextChange: (String) -> Unit,
    mathResults: Map<Int, String>,
    modifier: Modifier = Modifier
) {
    val lines = text.lines()

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        // Champ de texte unique pour l'édition
        item {
            BasicTextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.fillMaxWidth(),
                textStyle = TextStyle(
                    fontSize = 16.sp,
                    lineHeight = 24.sp,
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.onSurface
                ),
                decorationBox = { innerTextField ->
                    Box {
                        if (text.isEmpty()) {
                            Text(
                                "Mode math — écrivez des expressions.\nTerminez une ligne par = pour évaluer.\nEx: 2+2=\n50% of 200=",
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

        // Résultats des évaluations
        if (mathResults.isNotEmpty()) {
            item {
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    "Résultats :",
                    style = MaterialTheme.typography.labelLarge,
                    color = MathColor
                )
            }

            itemsIndexed(lines.toList()) { index, line ->
                val result = mathResults[index]
                if (result != null && line.trim().isNotEmpty()) {
                    Row(modifier = Modifier.padding(vertical = 2.dp)) {
                        Text(
                            text = result,
                            style = TextStyle(
                                fontSize = 14.sp,
                                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                                color = MathColor
                            )
                        )
                    }
                }
            }
        }
    }
}
