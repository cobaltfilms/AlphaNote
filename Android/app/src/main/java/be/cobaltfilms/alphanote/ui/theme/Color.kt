package be.cobaltfilms.alphanote.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import be.cobaltfilms.alphanote.ai.NoteMode

/**
 * Thème méta « Encre & or », mêmes teintes que macOS (AlphaNoteTheme.swift) :
 *   · Nuit  = encre chaude (bruns très sombres) + or + sauge.
 *   · Jour  = crème chaude + or profond + bleu paon.
 */
@Immutable
data class AlphaPalette(
    val window: Color,
    val sidebar: Color,
    val content: Color,
    val field: Color,
    val selection: Color,
    val line: Color,
    val text: Color,
    val secondary: Color,
    val accent: Color,
    val accent2: Color,
    val math: Color,
    val list: Color,
    val timer: Color,
    val code: Color,
    val plain: Color,
    val isDark: Boolean
) {
    fun mode(mode: NoteMode): Color = when (mode) {
        NoteMode.MATH -> math
        NoteMode.LIST -> list
        NoteMode.TIMER -> timer
        NoteMode.CODE -> code
        NoteMode.PLAIN -> plain
    }

    fun modeBackground(mode: NoteMode): Color = mode(mode).copy(alpha = if (mode == NoteMode.PLAIN) 0.14f else 0.20f)
}

private fun c(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())

val DayPalette = AlphaPalette(
    window = c(0.965, 0.945, 0.918),
    sidebar = c(0.937, 0.902, 0.847),
    content = c(1.000, 0.980, 0.953),
    field = c(1.000, 0.980, 0.953),
    selection = c(0.925, 0.878, 0.804),
    line = c(0.886, 0.839, 0.769),
    text = c(0.141, 0.114, 0.082),
    secondary = c(0.435, 0.380, 0.322),
    accent = c(0.604, 0.420, 0.122),
    accent2 = c(0.184, 0.435, 0.400),
    math = c(0.604, 0.420, 0.122),
    list = c(0.184, 0.435, 0.400),
    timer = c(0.706, 0.314, 0.180),
    code = c(0.227, 0.373, 0.659),
    plain = c(0.435, 0.380, 0.322),
    isDark = false
)

val NightPalette = AlphaPalette(
    window = c(0.078, 0.066, 0.051),
    sidebar = c(0.114, 0.094, 0.071),
    content = c(0.141, 0.122, 0.094),
    field = c(0.102, 0.086, 0.067),
    selection = c(0.165, 0.137, 0.094),
    line = c(0.204, 0.173, 0.129),
    text = c(0.953, 0.918, 0.851),
    secondary = c(0.663, 0.604, 0.502),
    accent = c(0.851, 0.643, 0.255),
    accent2 = c(0.498, 0.655, 0.627),
    math = c(0.851, 0.643, 0.255),
    list = c(0.498, 0.655, 0.627),
    timer = c(0.812, 0.420, 0.341),
    code = c(0.616, 0.706, 0.839),
    plain = c(0.663, 0.604, 0.502),
    isDark = true
)

val LocalAlphaPalette = staticCompositionLocalOf { NightPalette }
