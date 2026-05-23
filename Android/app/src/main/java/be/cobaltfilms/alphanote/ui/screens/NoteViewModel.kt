package be.cobaltfilms.alphanote.ui.screens

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import be.cobaltfilms.alphanote.data.NoteRepository
import be.cobaltfilms.alphanote.domain.KeywordDetector
import be.cobaltfilms.alphanote.domain.MathEvaluator
import be.cobaltfilms.alphanote.model.Note
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ViewModel principal des notes.
 * Gère l'état de la liste, l'édition, et les opérations CRUD.
 */
class NoteViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = NoteRepository(application)

    /** Liste réactive des notes actives */
    private val _activeNotes = MutableStateFlow<List<Note>>(emptyList())
    val activeNotes: StateFlow<List<Note>> = _activeNotes.asStateFlow()

    /** Note en cours d'édition */
    private val _currentNote = MutableStateFlow<Note?>(null)
    val currentNote: StateFlow<Note?> = _currentNote.asStateFlow()

    /** Résultat d'évaluation mathématique */
    private val _mathResult = MutableStateFlow<Map<Int, String>>(emptyMap())
    val mathResult: StateFlow<Map<Int, String>> = _mathResult.asStateFlow()

    /** Évaluateur mathématique partagé */
    val mathEvaluator = MathEvaluator()

    init {
        // Observer les notes depuis Room
        viewModelScope.launch {
            repository.activeNotes.collect { notes ->
                _activeNotes.value = notes
            }
        }
    }

    fun createNote(content: String = "", keyword: String = "", title: String = "") {
        viewModelScope.launch {
            repository.createNote(content, keyword, title)
        }
    }

    fun loadNote(noteId: Long) {
        viewModelScope.launch {
            val note = repository.getNoteById(noteId)
            _currentNote.value = note
        }
    }

    fun updateNoteContent(content: String) {
        val current = _currentNote.value ?: return
        val keyword = KeywordDetector.detectKeyword(content)
        val updated = current.copy(content = content, keyword = keyword)
        _currentNote.value = updated
    }

    fun saveNote() {
        val current = _currentNote.value ?: return
        viewModelScope.launch {
            repository.updateNote(current)
        }
    }

    fun deleteNote(note: Note) {
        viewModelScope.launch {
            repository.deleteNote(note)
        }
    }

    /** Évalue les expressions mathématiques ligne par ligne */
    fun evaluateMathLines(content: String) {
        val results = mutableMapOf<Int, String>()
        content.lines().forEachIndexed { index, line ->
            val trimmed = line.trim()
            if (trimmed.endsWith("=")) {
                val expr = trimmed.dropLast(1).trim()
                mathEvaluator.evaluate(expr)?.let { result ->
                    results[index] = formatResult(result)
                }
            } else if (trimmed.contains("=") && !trimmed.startsWith("//")) {
                // Expression inline
                val expr = trimmed
                val cleaned = expr.replace("=", "").trim()
                mathEvaluator.evaluate(cleaned)?.let { result ->
                    results[index] = "$expr → ${formatResult(result)}"
                }
            }
        }
        _mathResult.value = results
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
}
