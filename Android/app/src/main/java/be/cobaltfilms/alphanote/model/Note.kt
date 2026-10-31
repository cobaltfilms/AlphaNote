package be.cobaltfilms.alphanote.model

import androidx.room.Entity
import be.cobaltfilms.alphanote.vault.VaultEnvelope
import androidx.room.PrimaryKey
import java.util.UUID

/**
 * Entité Room représentant une note AlphaNote.
 * Portage fidèle de Models/Note.swift (macOS).
 *
 * La note est stockée en SQLite via Room.
 * Le mot-clé (keyword) détermine le mode d'affichage : math, list, code, timer.
 */
@Entity(tableName = "note")
data class Note(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val uuid: String = UUID.randomUUID().toString().lowercase(),
    val content: String = "",
    val keyword: String = "",
    val title: String = "",
    val position: Int = 0,
    val isPinned: Boolean = false,
    val archived: Boolean = false,
    val isDeleted: Boolean = false,
    val deletedAt: Long? = null,
    val lastSyncedAt: Long? = null,
    val lastModifiedByDeviceId: String = "",
    val aiSummary: String = "",
    val aiLastProcessedAt: Long? = null,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
) {

    companion object {
        /** Mots-clés connus — correspondent aux modes d'affichage */
        val knownKeywords: Set<String> = setOf("math", "list", "code", "timer", VaultEnvelope.KEYWORD)
    }

    /** Note sécurisée (« vault » en première ligne, ou corps déjà chiffré). */
    val isVault: Boolean
        get() = keyword == VaultEnvelope.KEYWORD || VaultEnvelope.isSealed(content)

    /**
     * Détecte le mot-clé à partir du contenu.
     * - Première ligne = "math", "list", "code", "timer" → keyword
     * - Format "keyword: titre" → keyword extrait
     * - Sinon → keyword vide (mode plain)
     */
    fun detectKeyword(): String {
        val rawFirstLine = content.lines().firstOrNull()?.trim() ?: ""
        val firstLine = rawFirstLine.lowercase()

        if (knownKeywords.contains(firstLine)) {
            return firstLine
        }

        val colonIndex = rawFirstLine.indexOf(':')
        if (colonIndex >= 0) {
            val possibleKeyword = rawFirstLine.substring(0, colonIndex).trim().lowercase()
            if (knownKeywords.contains(possibleKeyword)) {
                return possibleKeyword
            }
        }

        return ""
    }

    /**
     * Titre effectif : utilise le champ `title` s'il est renseigné,
     * sinon extrait la première ligne significative du contenu.
     */
    val effectiveTitle: String
        get() {
            val explicitTitle = title.trim()
            if (explicitTitle.isNotEmpty()) {
                return explicitTitle
            }

            val lines = content.lines()
            val firstNonEmpty = lines.firstOrNull { it.trim().isNotEmpty() }?.trim() ?: return ""

            val colonIndex = firstNonEmpty.indexOf(':')
            if (colonIndex >= 0) {
                val possibleKeyword = firstNonEmpty.substring(0, colonIndex).trim().lowercase()
                if (knownKeywords.contains(possibleKeyword)) {
                    val customTitle = firstNonEmpty.substring(colonIndex + 1).trim()
                    return customTitle.ifEmpty { possibleKeyword }
                }
            }

            return firstNonEmpty
        }
}
