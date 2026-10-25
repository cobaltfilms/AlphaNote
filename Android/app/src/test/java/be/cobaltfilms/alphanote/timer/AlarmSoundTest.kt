package be.cobaltfilms.alphanote.timer

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class AlarmSoundTest {

    @Test
    fun defaultIsMinuterie() {
        assertEquals(AlarmSound.MINUTERIE, AlarmSound.fromRaw(null))
        assertEquals(AlarmSound.MINUTERIE, AlarmSound.fromRaw("inconnue"))
    }

    /** Mêmes sonneries (identifiants) que macOS, et chaque fichier est embarqué. */
    @Test
    fun matchesMacOSAndFilesExist() {
        val swift = File("../../Sources/AlphaNote/Models/AlarmSound.swift").readText()
        val macCases = Regex("case ([a-z, ]+)\\n").find(swift)!!.groupValues[1].split(",").map { it.trim() }
        assertEquals(macCases, AlarmSound.entries.map { it.raw })
        AlarmSound.entries.filter { it.resId != null }.forEach { sound ->
            assertTrue("${sound.raw} manquant", File("src/main/res/raw/alarm_${sound.raw}.m4a").length() > 1000)
        }
    }
}
