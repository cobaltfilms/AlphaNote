package be.cobaltfilms.alphanote.vault

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

/** Coffre Android : mêmes cas que VaultTests.swift (macOS/iOS). */
class VaultKeyringTest {
    private class MemoryHolder : VaultKeyring.PasswordHolder {
        var value: String? = null
        override fun read() = value
        override fun save(password: String) { value = password }
        override fun clear() { value = null }
    }

    @Before
    fun reset() = VaultKeyring.initForTesting(MemoryHolder())

    @Test
    fun sealsOnlyWhenUnlocked() {
        assertNull(VaultKeyring.seal("vault\nx"))
        assertThrows(VaultKeyring.UnlockError::class.java) { VaultKeyring.setUp("court", emptyList()) }
        VaultKeyring.setUp("correct horse", emptyList())
        val sealed = VaultKeyring.seal("vault: A\nsecret")!!
        assertEquals("vault: A\nsecret", VaultKeyring.open(sealed))

        VaultKeyring.lock()
        assertNull(VaultKeyring.open(sealed))
        assertThrows(VaultKeyring.UnlockError::class.java) { VaultKeyring.unlock("wrong horse") }
        VaultKeyring.unlock("correct horse")
        assertEquals("vault: A\nsecret", VaultKeyring.open(sealed))
    }

    /** Note écrite sur le Mac (vecteur figé) : le téléphone l'ouvre avec le même mot de passe. */
    @Test
    fun secondDeviceMustUseTheSamePassword() {
        val fromMac = VaultEnvelopeTest.KNOWN_VECTOR
        assertThrows(VaultKeyring.UnlockError::class.java) { VaultKeyring.setUp("another one", listOf(fromMac)) }
        VaultKeyring.setUp("correct horse", listOf(fromMac))
        assertEquals("vault: Test\nmot de passe : é1", VaultKeyring.open(fromMac))
        // Les notes écrites ensuite reprennent le même sel.
        val next = VaultKeyring.seal("vault\ny")
        assertNotNull(next)
        assertEquals(VaultEnvelope.parse(fromMac)!!.salt.toList(), VaultEnvelope.parse(next!!)!!.salt.toList())
    }
}
