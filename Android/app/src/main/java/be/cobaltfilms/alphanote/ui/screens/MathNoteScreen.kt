package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.theme.AlphaSpacing
import be.cobaltfilms.alphanote.ui.theme.MathColor

@Composable
fun MathNoteScreen(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    mathResults: Map<Int, String>,
    mathVariables: Map<String, String>,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier
) {
    val orderedResults = mathResults.entries.sortedBy { it.key }
    val variableNames = remember(value.text, mathVariables) {
        val extracted = extractDeclaredVariables(value.text)
        (mathVariables.keys + extracted).toSet()
    }
    val mathHighlight = remember(variableNames) {
        MathVariableHighlightTransformation(variableNames, MathColor)
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = AlphaSpacing.screenHorizontal, vertical = 12.dp)
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            visualTransformation = mathHighlight,
            keyboardOptions = KeyboardOptions(
                autoCorrect = false,
                capitalization = KeyboardCapitalization.None,
                keyboardType = KeyboardType.Ascii
            ),
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.72f)
                .focusRequester(focusRequester),
            textStyle = TextStyle(
                fontSize = 16.sp,
                lineHeight = 24.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurface
            ),
            decorationBox = { innerTextField ->
                Box {
                    if (value.text.isEmpty()) {
                        Text(
                            "Mode math\nExemples:\na:3\nb:4\na+b=", style = TextStyle(
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

        if (mathVariables.isNotEmpty()) {
            Spacer(modifier = Modifier.height(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                mathVariables.forEach { (name, valueText) ->
                    SuggestionChip(
                        onClick = {},
                        label = { Text("$name = $valueText", style = MaterialTheme.typography.labelSmall) },
                        colors = SuggestionChipDefaults.suggestionChipColors(
                            containerColor = MathColor.copy(alpha = 0.14f),
                            labelColor = MathColor
                        )
                    )
                }
            }
        }

        if (orderedResults.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            Card(colors = CardDefaults.cardColors(containerColor = MathColor.copy(alpha = 0.08f))) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text("Résultats", style = MaterialTheme.typography.titleSmall, color = MathColor)
                    orderedResults.forEach { (line, result) ->
                        Row {
                            Text(
                                text = "L${line + 1}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = result,
                                style = TextStyle(
                                    fontSize = 14.sp,
                                    fontFamily = FontFamily.Monospace,
                                    color = MathColor
                                )
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun extractDeclaredVariables(content: String): Set<String> {
    val assignmentRegex = Regex("^([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*.+$")
    return content
        .lineSequence()
        .map { it.trim() }
        .mapNotNull { line ->
            val match = assignmentRegex.matchEntire(line) ?: return@mapNotNull null
            val name = match.groupValues[1].trim()
            if (name.lowercase() in setOf("math", "list", "code", "timer")) null else name
        }
        .toSet()
}

private class MathVariableHighlightTransformation(
    private val variableNames: Set<String>,
    private val color: Color
) : VisualTransformation {
    private val identifierRegex = Regex("[A-Za-z_][A-Za-z0-9_]*")

    override fun filter(text: AnnotatedString): TransformedText {
        if (variableNames.isEmpty() || text.text.isEmpty()) {
            return TransformedText(text, OffsetMapping.Identity)
        }

        val lowerVariables = variableNames.map { it.lowercase() }.toSet()
        val builder = AnnotatedString.Builder(text)
        identifierRegex.findAll(text.text).forEach { match ->
            val token = match.value.lowercase()
            if (token in lowerVariables) {
                builder.addStyle(
                    style = SpanStyle(color = color),
                    start = match.range.first,
                    end = match.range.last + 1
                )
            }
        }

        return TransformedText(builder.toAnnotatedString(), OffsetMapping.Identity)
    }
}
