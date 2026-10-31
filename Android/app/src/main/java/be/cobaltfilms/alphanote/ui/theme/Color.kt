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
        // Prune, comme Palette.vault sur macOS/iOS.
        NoteMode.VAULT -> if (isDark) Color(0xFFC394C1) else Color(0xFF7A3F78)
    }

    fun modeBackground(mode: NoteMode): Color = mode(mode).copy(alpha = if (mode == NoteMode.PLAIN) 0.14f else 0.20f)
}

/**
 * Thèmes coordonnés — mêmes valeurs que ColorTheme sur macOS (AlphaNoteTheme.swift) :
 * chacun fixe l'accent et une teinte des fonds assortie, de nuit et de jour.
 * L'icône de lancement suit le thème (LauncherIcons).
 */
enum class ColorTheme(val raw: String, val label: String, val night: Swatch, val day: Swatch) {
    OR("or", "Encre & or",
        Swatch(0x14110D, 0x1D1812, 0x241F18, 0x1A1611, 0x2A2318, 0x342C21, 0xF3EAD9, 0xA99A80, 0xD9A441),
        Swatch(0xF6F1EA, 0xEFE6D8, 0xFFFAF3, 0xFFFAF3, 0xECE0CD, 0xE2D6C4, 0x241D15, 0x6F6152, 0x9A6B1F)),
    CORAIL("corail", "Corail",
        Swatch(0x1B1F25, 0x1F242B, 0x22272E, 0x1D2127, 0x2D333B, 0x343B45, 0xEEF0F2, 0x9AA3AD, 0xEF7B5F),
        Swatch(0xF5F3F1, 0xECE8E4, 0xFFFDFB, 0xFFFDFB, 0xF2DFD8, 0xE2DCD6, 0x22272E, 0x626B75, 0xC4553A)),
    SAUGE("sauge", "Sauge",
        Swatch(0x141A18, 0x18201D, 0x1B2320, 0x161D1A, 0x24302B, 0x2B3832, 0xE8EFEC, 0x93A59E, 0x7FBFA8),
        Swatch(0xF1F5F2, 0xE4EBE6, 0xFBFDFB, 0xFBFDFB, 0xD8E8E1, 0xD3DDD7, 0x1B2320, 0x5A6B64, 0x2F6F66)),
    LAVANDE("lavande", "Lavande",
        Swatch(0x17151F, 0x1B1924, 0x1F1C29, 0x191722, 0x2A2638, 0x312C40, 0xEEEBF5, 0xA29CB5, 0xA78BFA),
        Swatch(0xF4F2F8, 0xE9E5F1, 0xFDFCFF, 0xFDFCFF, 0xE3DBF7, 0xDDD8E8, 0x1F1C29, 0x665F7A, 0x6D4FD1)),
    FRAMBOISE("framboise", "Framboise",
        Swatch(0x1C1418, 0x21181D, 0x251B20, 0x1E161A, 0x33242C, 0x3A2A32, 0xF5EBEF, 0xB39AA4, 0xE86A8E),
        Swatch(0xF8F1F3, 0xF0E4E8, 0xFFFBFC, 0xFFFBFC, 0xF3D9E1, 0xE8D8DD, 0x251B20, 0x76606A, 0xB83E63)),
    BLEU("bleu", "Bleu nuit",
        Swatch(0x121821, 0x161D28, 0x19212D, 0x141B25, 0x223047, 0x283548, 0xE9EEF5, 0x97A4B6, 0x5B9CF0),
        Swatch(0xF1F4F8, 0xE4EAF2, 0xFBFCFF, 0xFBFCFF, 0xD9E5F6, 0xD6DEE9, 0x19212D, 0x5C6A7D, 0x2F62B8));

    data class Swatch(
        val window: Int, val sidebar: Int, val content: Int, val field: Int, val selection: Int,
        val line: Int, val text: Int, val secondary: Int, val accent: Int
    )

    companion object {
        fun fromRaw(raw: String?): ColorTheme = entries.firstOrNull { it.raw == raw } ?: OR
    }
}

private fun c(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())
private fun hex(rgb: Int) = Color(0xFF000000.toInt() or rgb)

/** Palette d'un thème ; les couleurs des modes et l'accent secondaire ne changent pas. */
fun alphaPalette(theme: ColorTheme, dark: Boolean): AlphaPalette {
    val s = if (dark) theme.night else theme.day
    return AlphaPalette(
        window = hex(s.window),
        sidebar = hex(s.sidebar),
        content = hex(s.content),
        field = hex(s.field),
        selection = hex(s.selection),
        line = hex(s.line),
        text = hex(s.text),
        secondary = hex(s.secondary),
        accent = hex(s.accent),
        accent2 = if (dark) c(0.498, 0.655, 0.627) else c(0.184, 0.435, 0.400),
        math = if (dark) c(0.851, 0.643, 0.255) else c(0.604, 0.420, 0.122),
        list = if (dark) c(0.498, 0.655, 0.627) else c(0.184, 0.435, 0.400),
        timer = if (dark) c(0.812, 0.420, 0.341) else c(0.706, 0.314, 0.180),
        code = if (dark) c(0.616, 0.706, 0.839) else c(0.227, 0.373, 0.659),
        plain = hex(s.secondary),
        isDark = dark
    )
}

val DayPalette = alphaPalette(ColorTheme.OR, dark = false)
val NightPalette = alphaPalette(ColorTheme.OR, dark = true)

val LocalAlphaPalette = staticCompositionLocalOf { NightPalette }
