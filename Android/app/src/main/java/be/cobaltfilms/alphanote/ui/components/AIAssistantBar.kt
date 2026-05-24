package be.cobaltfilms.alphanote.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import be.cobaltfilms.alphanote.domain.Converter
import be.cobaltfilms.alphanote.domain.MathEvaluator
import kotlinx.coroutines.launch

/**
 * Barre d'assistant IA — située au-dessus du clavier.
 * Portage de AI/UI/AIAssistantBar.swift (macOS).
 *
 * Propose des actions rapides : évaluer, convertir, mode list, etc.
 */
@Composable
fun AIAssistantBar(
    noteContent: String,
    onUpdateContent: (String) -> Unit,
    evaluator: MathEvaluator = MathEvaluator(),
    modifier: Modifier = Modifier
) {
    val scope = rememberCoroutineScope()
    var showConversionDialog by remember { mutableStateOf(false) }
    var conversionInput by remember { mutableStateOf("") }
    var conversionResult by remember { mutableStateOf<String?>(null) }

    Surface(
        modifier = modifier.fillMaxWidth(),
        tonalElevation = 2.dp,
        shadowElevation = 4.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            // Évaluer (math)
            AssistButton(
                icon = Icons.Default.Calculate,
                label = "Évaluer",
                onClick = {
                    val lines = noteContent.lines()
                    val lastLine = lines.lastOrNull()?.trim()?.trimEnd('=') ?: ""
                    if (lastLine.isNotEmpty()) {
                        evaluator.evaluate(lastLine)?.let { result ->
                            val formatted = if (result == result.toLong().toDouble()) {
                                result.toLong().toString()
                            } else {
                                "%.4f".format(result).trimEnd('0').trimEnd('.')
                            }
                            onUpdateContent("$noteContent = $formatted")
                        }
                    }
                }
            )

            // Convertir
            AssistButton(
                icon = Icons.Default.SwapHoriz,
                label = "Convertir",
                onClick = { showConversionDialog = true }
            )

            // Mode liste
            AssistButton(
                icon = Icons.Default.Checklist,
                label = "Liste",
                onClick = {
                    val firstLine = noteContent.lines().firstOrNull()?.trim()?.lowercase().orEmpty()
                    if (!firstLine.startsWith("list")) {
                        onUpdateContent("list\n$noteContent")
                    }
                }
            )
        }
    }

    // Dialogue de conversion
    if (showConversionDialog) {
        val converter = remember { Converter() }

        AlertDialog(
            onDismissRequest = { showConversionDialog = false },
            title = { Text("Conversion d'unités") },
            text = {
                Column {
                    Text(
                        "Entrez une expression à convertir.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    OutlinedTextField(
                        value = conversionInput,
                        onValueChange = { conversionInput = it },
                        label = { Text("Ex: 12 km to mi, 100 USD to EUR") },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true
                    )
                    if (conversionResult != null) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = conversionResult!!,
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        val result = converter.convert(conversionInput.trim())
                        conversionResult = result ?: "Conversion impossible."
                    }
                }) {
                    Text("Convertir")
                }
            },
            dismissButton = {
                TextButton(onClick = { showConversionDialog = false }) {
                    Text("Fermer")
                }
            }
        )
    }
}

/** Bouton de l'assistant IA */
@Composable
private fun AssistButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit
) {
    IconButton(onClick = onClick) {
        Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
            Icon(
                icon,
                contentDescription = label,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp)
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary
            )
        }
    }
}
