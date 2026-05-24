package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.theme.AlphaSpacing
import be.cobaltfilms.alphanote.ui.theme.CodeColor

@Composable
fun CodeNoteScreen(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier
) {
    val lines = value.text.lines()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = AlphaSpacing.screenHorizontal, vertical = 12.dp)
    ) {
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight(0.82f)
                .focusRequester(focusRequester),
            textStyle = TextStyle(
                fontSize = 14.sp,
                lineHeight = 21.sp,
                fontFamily = FontFamily.Monospace,
                color = MaterialTheme.colorScheme.onSurface
            ),
            cursorBrush = SolidColor(CodeColor),
            decorationBox = { innerTextField ->
                if (value.text.isEmpty()) {
                    Text(
                        "Mode code\nPolice monospace pour snippets et blocs techniques.",
                        style = TextStyle(
                            fontSize = 14.sp,
                            lineHeight = 21.sp,
                            fontFamily = FontFamily.Monospace,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        )
                    )
                }
                innerTextField()
            }
        )

        LaunchedEffect(Unit) { focusRequester.requestFocus() }

        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "${lines.size} ligne${if (lines.size > 1) "s" else ""}",
            style = MaterialTheme.typography.labelSmall,
            color = CodeColor
        )
    }
}
