package be.cobaltfilms.alphanote.ui.theme

import be.cobaltfilms.alphanote.services.LauncherIcons
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.pow

class ColorThemeTest {

    @Test
    fun inkAndGoldIsTheDefaultAndKeepsLegacyAccent() {
        assertEquals(ColorTheme.OR, ColorTheme.fromRaw(null))
        assertEquals(ColorTheme.OR, ColorTheme.fromRaw("inconnu"))
        assertEquals(0xD9A441, ColorTheme.OR.night.accent)
        assertEquals(0x9A6B1F, ColorTheme.OR.day.accent)
    }

    /** Texte lisible (WCAG ≥ 7) et accent visible (≥ 3) sur le fond des notes, jour et nuit. */
    @Test
    fun everyThemeIsReadable() {
        for (theme in ColorTheme.entries) {
            for ((name, s) in listOf("nuit" to theme.night, "jour" to theme.day)) {
                assertTrue("${theme.label} $name : texte", contrast(s.text, s.content) >= 7)
                assertTrue("${theme.label} $name : secondaire", contrast(s.secondary, s.content) >= 4.5)
                assertTrue("${theme.label} $name : accent", contrast(s.accent, s.content) >= 3)
            }
        }
    }

    @Test
    fun launcherAliasMatchesManifest() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        for (theme in ColorTheme.entries) {
            val alias = LauncherIcons.aliasName(theme).removePrefix("be.cobaltfilms.alphanote")
            assertTrue("alias $alias absent du manifeste", manifest.contains("android:name=\"$alias\""))
            assertTrue(manifest.contains("@mipmap/ic_launcher_${theme.raw}\""))
        }
    }

    /** Mêmes valeurs que ColorTheme sur macOS (parité). */
    @Test
    fun matchesMacOSThemes() {
        val swift = File("../../Sources/AlphaNote/UI/Theme/AlphaNoteTheme.swift").readText()
        for (theme in ColorTheme.entries) {
            for ((field, s) in listOf("night" to theme.night, "day" to theme.day)) {
                val section = swift.substringAfter("var $field: Swatch {")
                val line = section.lines().first { it.trim().startsWith("case .${theme.raw}:") }
                val values = Regex("0x([0-9A-F]{6})").findAll(line).map { it.groupValues[1].toInt(16) }.toList()
                val expected = listOf(s.window, s.sidebar, s.content, s.field, s.selection, s.line, s.text, s.secondary, s.accent)
                assertEquals("${theme.raw} $field", expected, values)
            }
        }
    }

    private fun luminance(rgb: Int): Double {
        fun lin(v: Double) = if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        val r = lin(((rgb shr 16) and 0xFF) / 255.0)
        val g = lin(((rgb shr 8) and 0xFF) / 255.0)
        val b = lin((rgb and 0xFF) / 255.0)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private fun contrast(a: Int, b: Int): Double {
        val (l1, l2) = luminance(a) to luminance(b)
        return (maxOf(l1, l2) + 0.05) / (minOf(l1, l2) + 0.05)
    }
}
