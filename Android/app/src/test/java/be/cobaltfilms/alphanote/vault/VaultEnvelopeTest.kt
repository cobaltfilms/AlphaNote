package be.cobaltfilms.alphanote.vault

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

/** Format partagé avec macOS/iOS : VaultTests.swift attend le même vecteur. */
class VaultEnvelopeTest {
    private val salt = ByteArray(16) { (it + 1).toByte() }
    private val key by lazy { VaultEnvelope.deriveKey("correct horse", salt) }

    @Test
    fun knownVectorMatchesApple() {
        val nonce = ByteArray(12) { 0xA0.toByte() }
        val sealed = VaultEnvelope.seal("vault: Test\nmot de passe : é1", key, salt, nonce = nonce)
        assertEquals(KNOWN_VECTOR, sealed)
        assertEquals("vault: Test\nmot de passe : é1", VaultEnvelope.open(KNOWN_VECTOR, key))
    }

    @Test
    fun roundTripKeepsTextExactly() {
        for (content in listOf("vault: Jetons\nCF: abc\n", "vault", "vault: X\n", "vault: Clés\n\n  indenté\nfin")) {
            val sealed = VaultEnvelope.seal(content, key, salt)
            assertFalse(sealed.contains("abc"))
            assertTrue(VaultEnvelope.isSealed(sealed))
            assertEquals(content, VaultEnvelope.open(sealed, key))
        }
    }

    @Test
    fun wrongPasswordIsRejected() {
        val sealed = VaultEnvelope.seal("vault: A\nsecret", key, salt)
        assertThrows(VaultEnvelope.WrongKey::class.java) {
            VaultEnvelope.open(sealed, VaultEnvelope.deriveKey("wrong horse", salt))
        }
    }

    @Test
    fun plainNotesAreNotSealed() {
        assertNull(VaultEnvelope.parse("vault: A\nsecret"))
        assertNull(VaultEnvelope.parse("vaul: A\n${VaultEnvelope.PREFIX}x.600000.y"))
    }

    companion object {
        const val KNOWN_VECTOR = "vault: Test\nANVAULT1.AQIDBAUGBwgJCgsMDQ4PEA.600000.oKCgoKCgoKCgoKCgcVqJJRyNtY6SrGhcHrIrn-vtCtYcRbzau0G83lB4PPgOyZc"
    }
}
