package be.cobaltfilms.alphanote.ui.editor

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ai.NoteMode
import be.cobaltfilms.alphanote.ui.theme.AlphaPalette
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette

/**
 * L'éditeur unique d'AlphaNote (port de NoteEditorView.swift) : un seul champ
 * texte pour tous les modes ; le mode ne fait que *décorer* (couleurs,
 * police, cases à cocher en marge). Changer de mode ne détruit jamais le
 * champ, le focus ni le curseur.
 */
@Composable
fun NoteEditor(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    mode: NoteMode,
    fontSize: Float,
    checkTrigger: String,
    focusRequester: FocusRequester,
    modifier: Modifier = Modifier,
    /** Marge sous le texte (zone à toucher) ; réduite quand des images suivent. */
    bottomPadding: androidx.compose.ui.unit.Dp = 120.dp
) {
    val palette = LocalAlphaPalette.current
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    val isMono = mode == NoteMode.MATH || mode == NoteMode.CODE || mode == NoteMode.VAULT
    val lineHeight = fontSize * if (mode == NoteMode.CODE) 1.35f else 1.55f
    val gutterWidth = 40.dp
    val topPadding = 14.dp
    val items = remember(value.text, mode, checkTrigger) {
        if (mode == NoteMode.LIST) EditorDecorations.itemLines(value.text, checkTrigger) else emptyList()
    }
    val transformation = remember(value.text, mode, checkTrigger, palette) {
        DecorationTransformation(mode, checkTrigger, palette)
    }

    Row(modifier = modifier.fillMaxWidth().height(IntrinsicSize.Min)) {
        if (mode == NoteMode.LIST) {
            ListGutter(
                items = items, layout = layout, topPadding = topPadding, palette = palette,
                modifier = Modifier.width(gutterWidth).fillMaxHeight(),
                onToggle = { item -> onValueChange(EditorDecorations.toggleItem(value, item, checkTrigger)) }
            )
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .weight(1f)
                .padding(start = if (mode == NoteMode.LIST) 0.dp else 18.dp, end = 18.dp, top = topPadding, bottom = bottomPadding)
                .focusRequester(focusRequester),
            textStyle = TextStyle(
                fontSize = fontSize.sp,
                lineHeight = lineHeight.sp,
                fontFamily = if (isMono) FontFamily.Monospace else FontFamily.Default,
                color = palette.text
            ),
            cursorBrush = SolidColor(palette.accent),
            visualTransformation = transformation,
            keyboardOptions = KeyboardOptions(
                autoCorrect = mode == NoteMode.PLAIN || mode == NoteMode.LIST,
                capitalization = if (mode == NoteMode.MATH || mode == NoteMode.CODE) KeyboardCapitalization.None else KeyboardCapitalization.Sentences
            ),
            onTextLayout = { layout = it }
        )
    }
}

@Composable
private fun ListGutter(
    items: List<EditorDecorations.ItemLine>,
    layout: TextLayoutResult?,
    topPadding: androidx.compose.ui.unit.Dp,
    palette: AlphaPalette,
    onToggle: (EditorDecorations.ItemLine) -> Unit,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.pointerInput(items, layout) {
        detectTapGestures { offset ->
            val result = layout ?: return@detectTapGestures
            val y = offset.y - topPadding.toPx()
            if (y < 0) return@detectTapGestures
            val line = result.getLineForVerticalPosition(y)
            val start = result.getLineStart(line)
            items.firstOrNull { start >= it.start && start <= it.end }?.let(onToggle)
        }
    }) {
        Canvas(modifier = Modifier.fillMaxWidth().fillMaxHeight()) {
            val result = layout ?: return@Canvas
            val box = 17.dp.toPx()
            val x = size.width - box - 10.dp.toPx()
            for (item in items) {
                if (item.start > result.layoutInput.text.length) continue
                val line = result.getLineForOffset(item.start.coerceAtMost(result.layoutInput.text.length))
                val top = result.getLineTop(line) + topPadding.toPx()
                val height = result.getLineBottom(line) - result.getLineTop(line)
                val y = top + (height - box) / 2
                val rect = androidx.compose.ui.geometry.Rect(Offset(x, y), Size(box, box))
                if (item.checked) {
                    drawRoundRect(palette.list, rect.topLeft, rect.size, CornerRadius(5.dp.toPx()))
                    val path = Path().apply {
                        moveTo(rect.left + 4.dp.toPx(), rect.center.y)
                        lineTo(rect.left + 7.dp.toPx(), rect.bottom - 4.dp.toPx())
                        lineTo(rect.right - 4.dp.toPx(), rect.top + 4.dp.toPx())
                    }
                    drawPath(path, palette.content, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                } else {
                    drawRoundRect(palette.secondary, rect.topLeft, rect.size, CornerRadius(5.dp.toPx()), style = Stroke(width = 1.5.dp.toPx()))
                }
            }
        }
    }
}

/** Décoration par mode : mêmes règles que NoteEditorView.decorate() sur macOS. */
class DecorationTransformation(
    private val mode: NoteMode,
    private val checkTrigger: String,
    private val palette: AlphaPalette
) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val builder = AnnotatedString.Builder(text.text)
        EditorDecorations.decorate(text.text, mode, checkTrigger, palette) { style, start, end ->
            if (start < end && end <= text.text.length) builder.addStyle(style, start, end)
        }
        return TransformedText(builder.toAnnotatedString(), OffsetMapping.Identity)
    }
}

object EditorDecorations {
    data class ItemLine(val start: Int, val end: Int, val checked: Boolean)

    private val MARKER_REGEX = Regex("^\\s*[-*•]\\s")
    private val NUMBER_REGEX = Regex("(?<![\\p{L}_])[-+]?\\d+(?:[.,]\\d+)?")
    private val UNIT_REGEX = Regex("(?i)\\b(usd|eur|gbp|jpy|chf|cad|kg|g|mg|lb|oz|km|m|cm|mm|mi|yd|ft|in|sqm|sqft|ha|acre|l|ml|cl|gal|qt|pt|cup|°c|°f|k|min|h|s)\\b")
    private val URL_REGEX = Regex("(?i)\\b((?:https?://|www\\.)[^\\s<>\"']+)")
    private val VARIABLE_NAME_REGEX = Regex("^[\\p{L}_][\\p{L}\\p{N}_ ]*$")

    fun isModeHeader(trimmed: String): Boolean {
        val lower = trimmed.lowercase()
        return be.cobaltfilms.alphanote.model.Note.knownKeywords.contains(lower) ||
            be.cobaltfilms.alphanote.model.Note.knownKeywords.any { lower.startsWith("$it:") }
    }

    fun isChecked(trimmed: String, trigger: String): Boolean = trimmed.endsWith(trigger, ignoreCase = true)

    fun isHeading(trimmed: String) = trimmed.startsWith("#")
    fun isComment(trimmed: String) = trimmed.startsWith("//")

    /** Lignes « élément » du mode liste : positions dans le texte brut. */
    fun itemLines(text: String, trigger: String): List<ItemLine> {
        val items = mutableListOf<ItemLine>()
        var location = 0
        text.split("\n").forEachIndexed { index, line ->
            val trimmed = line.trim()
            val end = location + line.length
            val isHeader = index == 0 && isModeHeader(trimmed)
            if (trimmed.isNotEmpty() && !isHeader && !isHeading(trimmed) && !isComment(trimmed)) {
                items.add(ItemLine(location, end, isChecked(trimmed, trigger.ifEmpty { "/x" })))
            }
            location = end + 1
        }
        return items
    }

    /** Coche / décoche une ligne en ajoutant ou retirant le déclencheur. */
    fun toggleItem(value: TextFieldValue, item: ItemLine, trigger: String): TextFieldValue {
        val text = value.text
        if (item.end > text.length) return value
        val line = text.substring(item.start, item.end)
        val effectiveTrigger = trigger.ifEmpty { "/x" }
        val trimmedTrailing = line.trimEnd()
        val replacement = if (isChecked(trimmedTrailing.trim(), effectiveTrigger)) {
            trimmedTrailing.dropLast(effectiveTrigger.length).trimEnd()
        } else {
            if (trimmedTrailing.isEmpty()) effectiveTrigger else "$trimmedTrailing $effectiveTrigger"
        }
        val newText = text.replaceRange(item.start, item.end, replacement)
        val delta = replacement.length - line.length
        val cursor = value.selection.end
        val newCursor = if (cursor > item.start) (cursor + delta).coerceIn(item.start, newText.length) else cursor
        return value.copy(text = newText, selection = androidx.compose.ui.text.TextRange(newCursor.coerceIn(0, newText.length)))
    }

    /**
     * Entrée en mode liste : continue la puce « - » de la ligne précédente, ou
     * retire une puce vide. Retourne null si rien à faire.
     */
    fun continueBullet(previous: String, next: TextFieldValue): TextFieldValue? {
        val cursor = next.selection.end
        if (next.text.length != previous.length + 1 || cursor <= 0 || next.text[cursor - 1] != '\n') return null
        if (previous.substring(0, cursor - 1) != next.text.substring(0, cursor - 1)) return null
        val lineStart = next.text.lastIndexOf('\n', cursor - 2).let { if (it < 0) 0 else it + 1 }
        val previousLine = next.text.substring(lineStart, cursor - 1)
        val marker = MARKER_REGEX.find(previousLine)?.value ?: return null
        val rest = previousLine.substring(marker.length).trim()
        return if (rest.isEmpty()) {
            // Puce vide : on la retire au lieu d'en ajouter une.
            val text = next.text.removeRange(lineStart, cursor)
            next.copy(text = text, selection = androidx.compose.ui.text.TextRange(lineStart))
        } else {
            val text = next.text.substring(0, cursor) + marker + next.text.substring(cursor)
            next.copy(text = text, selection = androidx.compose.ui.text.TextRange(cursor + marker.length))
        }
    }

    fun decorate(text: String, mode: NoteMode, trigger: String, palette: AlphaPalette, add: (SpanStyle, Int, Int) -> Unit) {
        val secondary = SpanStyle(color = palette.secondary)
        var location = 0
        val lines = text.split("\n")
        lines.forEachIndexed { index, line ->
            val start = location
            val end = location + line.length
            location = end + 1
            val trimmed = line.trim()

            if (index == 0 && isModeHeader(trimmed)) {
                add(SpanStyle(color = palette.secondary, fontWeight = FontWeight.SemiBold), start, end)
                return@forEachIndexed
            }
            when (mode) {
                NoteMode.PLAIN, NoteMode.CODE, NoteMode.TIMER, NoteMode.VAULT -> Unit
                NoteMode.LIST -> {
                    if (trimmed.isEmpty()) return@forEachIndexed
                    when {
                        isHeading(trimmed) -> add(SpanStyle(fontWeight = FontWeight.Bold), start, end)
                        isComment(trimmed) -> add(secondary, start, end)
                        else -> {
                            val checked = isChecked(trimmed, trigger.ifEmpty { "/x" })
                            if (checked) add(SpanStyle(color = palette.secondary, textDecoration = TextDecoration.LineThrough), start, end)
                            MARKER_REGEX.find(line)?.let { add(SpanStyle(color = palette.line), start + it.range.first, start + it.range.last + 1) }
                            if (checked) {
                                val idx = line.lastIndexOf(trigger.ifEmpty { "/x" }, ignoreCase = true)
                                if (idx >= 0) add(SpanStyle(color = palette.line), start + idx, start + idx + trigger.ifEmpty { "/x" }.length)
                            }
                        }
                    }
                }
                NoteMode.MATH -> decorateMathLine(line, start, palette, add)
            }
        }
        if (mode == NoteMode.PLAIN) {
            URL_REGEX.findAll(text).forEach { add(SpanStyle(color = palette.accent2, textDecoration = TextDecoration.Underline), it.range.first, it.range.last + 1) }
        }
    }

    private fun decorateMathLine(line: String, start: Int, palette: AlphaPalette, add: (SpanStyle, Int, Int) -> Unit) {
        val trimmed = line.trim()
        if (trimmed.startsWith("//")) { add(SpanStyle(color = palette.secondary), start, start + line.length); return }

        val colon = line.indexOf(':')
        if (colon > 0) {
            val name = line.substring(0, colon).trim()
            if (name.isNotEmpty() && VARIABLE_NAME_REGEX.matches(name) && !be.cobaltfilms.alphanote.model.Note.knownKeywords.contains(name.lowercase())) {
                add(SpanStyle(color = palette.math, fontWeight = FontWeight.SemiBold), start, start + colon)
            }
        }
        NUMBER_REGEX.findAll(line).forEach { add(SpanStyle(color = palette.code), start + it.range.first, start + it.range.last + 1) }
        UNIT_REGEX.findAll(line).forEach { add(SpanStyle(color = palette.list), start + it.range.first, start + it.range.last + 1) }
        val equal = line.indexOf('=')
        if (equal >= 0) {
            add(SpanStyle(color = palette.secondary), start + equal, start + equal + 1)
            if (equal + 1 < line.length) add(SpanStyle(color = palette.accent2, fontWeight = FontWeight.SemiBold), start + equal + 1, start + line.length)
        }
    }
}
