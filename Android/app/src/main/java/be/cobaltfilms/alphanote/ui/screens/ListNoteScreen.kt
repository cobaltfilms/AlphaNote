package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.domain.ListModeFormatter
import be.cobaltfilms.alphanote.ui.theme.AlphaSpacing

@Composable
fun ListNoteScreen(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier
) {
    val normalized = remember(value.text) {
        ListModeFormatter.normalizeForListMode(value.text)
    }

    val headerLine = remember(normalized) {
        normalized.lines().firstOrNull()?.takeIf { ListModeFormatter.isListHeader(it) } ?: "list"
    }

    val initialBody = remember(normalized) {
        val lines = normalized.lines()
        if (lines.isNotEmpty() && ListModeFormatter.isListHeader(lines.first())) {
            lines.drop(1).joinToString("\n")
        } else {
            lines.joinToString("\n")
        }
    }

    var body by remember { mutableStateOf(initialBody) }

    LaunchedEffect(initialBody) {
        if (initialBody != body) {
            body = initialBody
        }
    }

    fun rebuildNoteContent(nextBody: String): String {
        val trimmedTrailing = nextBody.trimEnd()
        return if (trimmedTrailing.isBlank()) {
            headerLine
        } else {
            "$headerLine\n$trimmedTrailing"
        }
    }

    BasicTextField(
        value = body,
        onValueChange = { updated ->
            body = updated
            val newContent = rebuildNoteContent(updated)
            onValueChange(TextFieldValue(newContent, TextRange(newContent.length)))
        },
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = AlphaSpacing.screenHorizontal, vertical = 12.dp)
            .focusRequester(focusRequester),
        textStyle = TextStyle(
            fontSize = 16.sp,
            lineHeight = 24.sp,
            color = MaterialTheme.colorScheme.onSurface
        ),
        decorationBox = { innerTextField ->
            Box(modifier = Modifier.fillMaxSize()) {
                if (body.isBlank()) {
                    Text(
                        text = "Nouvelle liste\n\nUtilise Entree pour ajouter une nouvelle ligne.",
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
}
