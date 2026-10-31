package be.cobaltfilms.alphanote.vault

import java.security.SecureRandom
import java.text.Normalizer
import java.util.Base64
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Note sécurisée telle qu'elle est stockée et synchronisée (même format que
 * VaultEnvelope.swift sur macOS/iOS) :
 *
 *     vault: Jetons Cloudflare                 ← en clair (titre, liste, recherche)
 *     ANVAULT1.<sel>.<itérations>.<scellé>     ← corps chiffré
 *
 * AES-256-GCM, clé dérivée du mot de passe maître par PBKDF2-HMAC-SHA256 ; le
 * sel et les itérations voyagent dans l'enveloppe. Base64 URL sans
 * remplissage ; scellé = nonce (12) ‖ chiffré ‖ tag (16).
 */
object VaultEnvelope {
    const val KEYWORD = "vault"
    const val PREFIX = "ANVAULT1."
    const val ITERATIONS = 600_000
    const val SALT_LENGTH = 16
    private val ASSOCIATED_DATA = "alphanote-vault-v1".toByteArray()
    private val random = SecureRandom()

    data class Parsed(val header: String, val salt: ByteArray, val iterations: Int, val sealed: ByteArray)

    class WrongKey : Exception("Mot de passe maître incorrect.")

    /** Première ligne et reste d'un contenu. */
    fun header(content: String): String = content.substringBefore('\n')

    fun isSealed(content: String): Boolean = parse(content) != null

    fun parse(content: String): Parsed? {
        val header = header(content)
        // L'en-tête peut être en cours de frappe (« vaul: … ») : seul le corps compte.
        val token = content.drop(header.length).trim()
        if (!token.startsWith(PREFIX)) return null
        val parts = token.removePrefix(PREFIX).split('.')
        if (parts.size != 3) return null
        val salt = decode(parts[0]) ?: return null
        val iterations = parts[1].toIntOrNull() ?: return null
        val sealed = decode(parts[2]) ?: return null
        if (salt.size != SALT_LENGTH || iterations < 100_000 || sealed.size < 12 + 16) return null
        return Parsed(header, salt, iterations, sealed)
    }

    fun deriveKey(password: String, salt: ByteArray, iterations: Int = ITERATIONS): ByteArray {
        // Même normalisation qu'Apple (precomposedStringWithCanonicalMapping = NFC).
        val normalized = Normalizer.normalize(password, Normalizer.Form.NFC)
        val spec = PBEKeySpec(normalized.toCharArray(), salt, iterations, 256)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }

    fun randomSalt(): ByteArray = ByteArray(SALT_LENGTH).also(random::nextBytes)

    /** Chiffre tout ce qui suit la première ligne (saut de ligne compris). */
    fun seal(content: String, key: ByteArray, salt: ByteArray, iterations: Int = ITERATIONS,
             nonce: ByteArray = ByteArray(12).also(random::nextBytes)): String {
        val header = header(content)
        val rest = content.drop(header.length)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(ASSOCIATED_DATA)
        val sealed = nonce + cipher.doFinal(rest.toByteArray(Charsets.UTF_8))
        return header + "\n" + PREFIX + encode(salt) + "." + iterations + "." + encode(sealed)
    }

    /** Contenu en clair (titre + corps) ; lève WrongKey si la clé ne convient pas. */
    fun open(parsed: Parsed, key: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, parsed.sealed, 0, 12))
        cipher.updateAAD(ASSOCIATED_DATA)
        val body = try {
            cipher.doFinal(parsed.sealed, 12, parsed.sealed.size - 12)
        } catch (_: AEADBadTagException) {
            throw WrongKey()
        }
        return parsed.header + String(body, Charsets.UTF_8)
    }

    fun open(content: String, key: ByteArray): String =
        open(parse(content) ?: throw IllegalArgumentException("Pas une note scellée"), key)

    private fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    private fun decode(text: String): ByteArray? = try { Base64.getUrlDecoder().decode(text) } catch (_: IllegalArgumentException) { null }
}
