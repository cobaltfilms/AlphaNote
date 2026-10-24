package be.cobaltfilms.alphanote.search

import be.cobaltfilms.alphanote.model.Note
import kotlin.math.sqrt

/** Embedding « sac de mots haché » 64 dimensions, FNV-1a stable (port de HashEmbedding.swift). */
object HashEmbedding {
    const val DIMENSIONS = 64
    const val MODEL_ID = "fnv64-v2"

    fun embed(text: String): DoubleArray {
        val vector = DoubleArray(DIMENSIONS)
        val tokens = text.lowercase().split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return vector
        for (token in tokens) {
            val bucket = java.lang.Long.remainderUnsigned(fnv1a64(token), DIMENSIONS.toLong()).toInt()
            vector[bucket] += 1.0
        }
        val norm = sqrt(vector.sumOf { it * it })
        if (norm <= 0) return vector
        for (i in vector.indices) vector[i] /= norm
        return vector
    }

    fun fnv1a64(string: String): Long {
        var hash = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        for (byte in string.toByteArray(Charsets.UTF_8)) {
            hash = hash xor (byte.toLong() and 0xff)
            hash *= 0x100000001b3L
        }
        return hash
    }

    fun cosineSimilarity(lhs: DoubleArray, rhs: DoubleArray): Double {
        if (lhs.size != rhs.size || lhs.isEmpty()) return 0.0
        var dot = 0.0; var l = 0.0; var r = 0.0
        for (i in lhs.indices) { dot += lhs[i] * rhs[i]; l += lhs[i] * lhs[i]; r += rhs[i] * rhs[i] }
        if (l <= 0 || r <= 0) return 0.0
        return dot / (sqrt(l) * sqrt(r))
    }
}

data class SemanticSearchHit(val note: Note, val score: Double)

/** Recherche sémantique locale : cosinus + score lexical, sans réseau. */
class SemanticSearch {
    private val cache = mutableMapOf<String, Pair<Long, DoubleArray>>()

    fun search(query: String, notes: List<Note>, topK: Int = 6): List<SemanticSearchHit> {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return emptyList()
        val queryVector = HashEmbedding.embed(trimmed)
        val scored = notes.mapNotNull { note ->
            val vector = embedding(note)
            val semantic = HashEmbedding.cosineSimilarity(queryVector, vector)
            val lexical = lexicalScore(trimmed, note)
            val score = 0.65 * semantic + 0.35 * lexical
            if (score > 0.05) SemanticSearchHit(note, score) else null
        }
        return scored.sortedByDescending { it.score }.take(maxOf(1, topK))
    }

    private fun embedding(note: Note): DoubleArray {
        val cached = cache[note.uuid]
        if (cached != null && cached.first == note.updatedAt) return cached.second
        val vector = HashEmbedding.embed(note.effectiveTitle + "\n" + note.content)
        cache[note.uuid] = note.updatedAt to vector
        return vector
    }

    private fun lexicalScore(query: String, note: Note): Double {
        val q = query.lowercase()
        val text = (note.effectiveTitle + "\n" + note.content).lowercase()
        if (text.contains(q)) return 1.0
        val tokens = q.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        if (tokens.isEmpty()) return 0.0
        return tokens.count { text.contains(it) }.toDouble() / tokens.size
    }
}
