package be.cobaltfilms.alphanote.ui.screens

import android.app.Application
import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import be.cobaltfilms.alphanote.data.NoteRepository
import be.cobaltfilms.alphanote.domain.KeywordDetector
import be.cobaltfilms.alphanote.domain.MathEvaluator
import be.cobaltfilms.alphanote.model.Note
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

private val Context.dataStore by preferencesDataStore(name = "alphanote_settings")

/**
 * ViewModel principal des notes.
 * Gère l'état de la liste, l'édition, et les opérations CRUD.
 */
class NoteViewModel(application: Application) : AndroidViewModel(application) {

    data class MathInputTransformResult(
        val content: String,
        val cursorPosition: Int,
        val transformed: Boolean
    )

    private val repository = NoteRepository(application)

    /** Liste réactive des notes actives */
    private val _activeNotes = MutableStateFlow<List<Note>>(emptyList())
    val activeNotes: StateFlow<List<Note>> = _activeNotes.asStateFlow()

    /** Liste réactive des notes archivées */
    private val _archivedNotes = MutableStateFlow<List<Note>>(emptyList())
    val archivedNotes: StateFlow<List<Note>> = _archivedNotes.asStateFlow()

    /** Note en cours d'édition */
    private val _currentNote = MutableStateFlow<Note?>(null)
    val currentNote: StateFlow<Note?> = _currentNote.asStateFlow()

    /** Résultat d'évaluation mathématique */
    private val _mathResult = MutableStateFlow<Map<Int, String>>(emptyMap())
    val mathResult: StateFlow<Map<Int, String>> = _mathResult.asStateFlow()
    private val _mathVariables = MutableStateFlow<Map<String, String>>(emptyMap())
    val mathVariables: StateFlow<Map<String, String>> = _mathVariables.asStateFlow()

    private val _confirmDelete = MutableStateFlow(true)
    val confirmDelete: StateFlow<Boolean> = _confirmDelete.asStateFlow()

    private val _autoDetectMode = MutableStateFlow(true)
    val autoDetectMode: StateFlow<Boolean> = _autoDetectMode.asStateFlow()

    /** Évaluateur mathématique partagé */
    val mathEvaluator = MathEvaluator()

    init {
        val prefs = application.dataStore

        viewModelScope.launch {
            repository.activeNotes.collectLatest { notes ->
                _activeNotes.value = notes
            }
        }

        viewModelScope.launch {
            repository.archivedNotes.collectLatest { notes ->
                _archivedNotes.value = notes
            }
        }

        viewModelScope.launch {
            prefs.data
                .map { it[SettingsKeys.CONFIRM_DELETE] ?: true }
                .collectLatest { _confirmDelete.value = it }
        }

        viewModelScope.launch {
            prefs.data
                .map { it[SettingsKeys.AUTO_DETECT_MODE] ?: true }
                .collectLatest { _autoDetectMode.value = it }
        }
    }

    suspend fun createNoteAndGetId(content: String = "", keyword: String = "", title: String = ""): Long {
        val note = repository.createNote(content, keyword, title)
        return note.id
    }

    fun loadNote(noteId: Long) {
        viewModelScope.launch {
            val note = repository.getNoteById(noteId)
            _currentNote.value = note
        }
    }

    fun updateNoteContent(content: String) {
        val current = _currentNote.value ?: return
        val resolvedKeyword = resolveKeyword(content = content, currentKeyword = current.keyword)
        val updated = current.copy(
            content = content,
            keyword = resolvedKeyword
        )
        _currentNote.value = updated
        if (resolvedKeyword == "math") {
            evaluateMathLines(content)
        } else {
            _mathResult.value = emptyMap()
        }
    }

    fun saveNote() {
        val current = _currentNote.value ?: return
        viewModelScope.launch {
            val saved = repository.updateNote(current)
            _currentNote.value = saved
        }
    }

    suspend fun saveCurrentText(content: String) {
        val current = _currentNote.value ?: return
        val resolvedKeyword = resolveKeyword(content = content, currentKeyword = current.keyword)
        val updated = current.copy(content = content, keyword = resolvedKeyword)
        val saved = repository.updateNote(updated)
        _currentNote.value = saved
    }

    fun deleteNote(note: Note) {
        viewModelScope.launch {
            repository.deleteNote(note)
        }
    }

    fun archiveNote(note: Note) {
        viewModelScope.launch {
            repository.archiveNote(note)
            if (_currentNote.value?.id == note.id) {
                _currentNote.value = _currentNote.value?.copy(archived = true)
            }
        }
    }

    fun unarchiveNote(note: Note) {
        viewModelScope.launch {
            repository.unarchiveNote(note)
            if (_currentNote.value?.id == note.id) {
                _currentNote.value = _currentNote.value?.copy(archived = false)
            }
        }
    }

    fun setConfirmDelete(enabled: Boolean) {
        viewModelScope.launch {
            getApplication<Application>().dataStore.edit { it[SettingsKeys.CONFIRM_DELETE] = enabled }
        }
    }

    fun setAutoDetectMode(enabled: Boolean) {
        viewModelScope.launch {
            getApplication<Application>().dataStore.edit { it[SettingsKeys.AUTO_DETECT_MODE] = enabled }
        }
    }

    /** Évalue les expressions mathématiques ligne par ligne */
    fun evaluateMathLines(content: String) {
        val results = mutableMapOf<Int, String>()
        val variables = mutableMapOf<String, Double>()
        val assignmentRegex = Regex("^([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*(.+)$")

        content.lines().forEachIndexed { index, line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("//")) return@forEachIndexed

            val assign = assignmentRegex.matchEntire(trimmed)
            if (assign != null) {
                val name = assign.groupValues[1]
                val expr = assign.groupValues[2].substringBefore("=").trim()
                if (expr.isBlank()) return@forEachIndexed
                mathEvaluator.evaluate(expr, variables)?.let { result ->
                    variables[name] = result
                    results[index] = "$name = ${formatResult(result)}"
                }
                return@forEachIndexed
            }

            if (trimmed.contains("=") && !trimmed.startsWith("//")) {
                val left = trimmed.substringBefore("=").trim()
                if (left.isNotEmpty()) {
                    mathEvaluator.evaluate(left, variables)?.let { result ->
                        results[index] = "$left = ${formatResult(result)}"
                    }
                }
            }
        }
        _mathResult.value = results
        _mathVariables.value = variables.mapValues { (_, value) -> formatResult(value) }
    }

    private fun formatResult(value: Double): String {
        if (value == value.toLong().toDouble()) {
            return value.toLong().toString()
        }
        var formatted = "%.6f".format(value)
        while (formatted.endsWith('0')) formatted = formatted.dropLast(1)
        if (formatted.endsWith('.')) formatted = formatted.dropLast(1)
        return formatted
    }

    private object SettingsKeys {
        val CONFIRM_DELETE = booleanPreferencesKey("confirm_delete")
        val AUTO_DETECT_MODE = booleanPreferencesKey("auto_detect_mode")
    }

    private fun resolveKeyword(content: String, currentKeyword: String): String {
        if (!_autoDetectMode.value) return currentKeyword

        val explicit = KeywordDetector.detectKeyword(content)
        if (explicit.isNotBlank()) return explicit

        if (looksLikeMathContent(content)) return "math"

        return ""
    }

    private fun looksLikeMathContent(content: String): Boolean {
        val lines = content.lines().map { it.trim() }.filter { it.isNotEmpty() }
        if (lines.isEmpty()) return false

        val hasEquationLine = lines.any { it.endsWith("=") }
        if (hasEquationLine) return true

        val operatorRegex = Regex("\\d\\s*[+\\-*/^]\\s*\\d")
        return lines.any { operatorRegex.containsMatchIn(it) }
    }

    fun applyMathInputTransform(
        previousContent: String,
        newContent: String,
        cursorPosition: Int
    ): MathInputTransformResult {
        if (newContent == previousContent) {
            return MathInputTransformResult(newContent, cursorPosition.coerceIn(0, newContent.length), false)
        }

        val safeCursor = cursorPosition.coerceIn(0, newContent.length)
        val previousChar = if (safeCursor > 0) newContent[safeCursor - 1] else null
        val triggeredBySpace = previousChar == ' '
        val triggeredByEquals = previousChar == '='
        if (!triggeredBySpace && !triggeredByEquals) {
            return MathInputTransformResult(newContent, safeCursor, false)
        }

        val cursorAnchor = if (safeCursor > 0) safeCursor - 1 else 0
        val lineStart = newContent.lastIndexOf('\n', cursorAnchor).let { if (it < 0) 0 else it + 1 }
        val lineEnd = newContent.indexOf('\n', lineStart).let { if (it < 0) newContent.length else it }
        val line = newContent.substring(lineStart, lineEnd)

        val eqIndex = line.indexOf('=')
        if (eqIndex <= 0) return MathInputTransformResult(newContent, safeCursor, false)

        val expressionRaw = line.substring(0, eqIndex).trim()
        if (expressionRaw.isBlank()) return MathInputTransformResult(newContent, safeCursor, false)

        val rhs = line.substring(eqIndex + 1).trim()

        if (triggeredByEquals && rhs.isNotEmpty()) {
            return MathInputTransformResult(newContent, safeCursor, false)
        }

        if (triggeredBySpace) {
            val charBeforeSpace = if (safeCursor > 1) newContent[safeCursor - 2] else null
            if (charBeforeSpace != '=') {
                return MathInputTransformResult(newContent, safeCursor, false)
            }
        }

        val prefix = newContent.substring(0, lineStart)
        val suffix = newContent.substring(lineEnd)
        val variables = extractVariables(prefix)
        val result = mathEvaluator.evaluate(expressionRaw, variables)
            ?: return MathInputTransformResult(newContent, safeCursor, false)
        val formatted = "$expressionRaw = ${formatResult(result)}"

        return if (triggeredBySpace) {
            val normalizedSuffix = if (suffix.startsWith("\n")) suffix.drop(1) else suffix
            val content = prefix + formatted + "\n" + normalizedSuffix
            val cursor = (prefix.length + formatted.length + 1).coerceIn(0, content.length)
            MathInputTransformResult(content, cursor, true)
        } else {
            val content = prefix + formatted + suffix
            val cursor = (prefix.length + formatted.length).coerceIn(0, content.length)
            MathInputTransformResult(content, cursor, true)
        }
    }

    private fun extractVariables(prefixContent: String): Map<String, Double> {
        val variables = mutableMapOf<String, Double>()
        val assignmentRegex = Regex("^([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*(.+)$")

        prefixContent.lines().forEach { raw ->
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("//")) return@forEach
            val match = assignmentRegex.matchEntire(line) ?: return@forEach
            val name = match.groupValues[1]
            val expr = match.groupValues[2].substringBefore("=").trim()
            if (expr.isBlank()) return@forEach
            val value = mathEvaluator.evaluate(expr, variables) ?: return@forEach
            variables[name] = value
        }

        return variables
    }
}
