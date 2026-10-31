package be.cobaltfilms.alphanote.ui.screens

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import be.cobaltfilms.alphanote.ai.AISettings
import be.cobaltfilms.alphanote.ai.AISettingsRepository
import be.cobaltfilms.alphanote.ai.FormulaDraftFeature
import be.cobaltfilms.alphanote.ai.JEVClient
import be.cobaltfilms.alphanote.ai.JEVOutcome
import be.cobaltfilms.alphanote.ai.KeywordIntentRouter
import be.cobaltfilms.alphanote.ai.ModeDecision
import be.cobaltfilms.alphanote.ai.ModeRoutingFeature
import be.cobaltfilms.alphanote.ai.NoteMode
import be.cobaltfilms.alphanote.ai.RouteSource
import be.cobaltfilms.alphanote.data.AppSettings
import be.cobaltfilms.alphanote.data.AppSettingsRepository
import be.cobaltfilms.alphanote.data.NoteRepository
import be.cobaltfilms.alphanote.data.ThemeMode
import be.cobaltfilms.alphanote.services.LauncherIcons
import be.cobaltfilms.alphanote.vault.VaultEnvelope
import be.cobaltfilms.alphanote.vault.VaultKeyring
import be.cobaltfilms.alphanote.timer.AlarmPlayer
import be.cobaltfilms.alphanote.timer.AlarmSound
import be.cobaltfilms.alphanote.ui.theme.ColorTheme
import be.cobaltfilms.alphanote.domain.Converter
import be.cobaltfilms.alphanote.domain.ListModeFormatter
import be.cobaltfilms.alphanote.domain.MathEvaluator
import be.cobaltfilms.alphanote.domain.NoteAttachments
import be.cobaltfilms.alphanote.domain.RecipeIngredientExtractor
import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.search.SemanticSearch
import be.cobaltfilms.alphanote.sync.CloudJsonCoder
import be.cobaltfilms.alphanote.sync.CloudNoteDto
import be.cobaltfilms.alphanote.sync.LanSyncCoordinator
import be.cobaltfilms.alphanote.sync.SyncEngine
import be.cobaltfilms.alphanote.sync.SyncRunState
import be.cobaltfilms.alphanote.sync.SyncSettings
import be.cobaltfilms.alphanote.sync.SyncSettingsRepository
import be.cobaltfilms.alphanote.timer.TimerRegistry
import be.cobaltfilms.alphanote.update.AppUpdateInfo
import be.cobaltfilms.alphanote.update.UpdateManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.json.JSONArray
import java.io.File

/**
 * ViewModel principal — miroir de NoteStore + AIStore (macOS) : notes,
 * édition avec sauvegarde groupée (400 ms), modes, routage de mode, réglages,
 * synchro, mises à jour.
 */
class NoteViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = NoteRepository(application)
    private val appSettingsRepository = AppSettingsRepository(application)
    private val aiSettingsRepository = AISettingsRepository(application)
    private val syncSettingsRepository = SyncSettingsRepository(application)
    private val syncEngine = SyncEngine(application, repository, syncSettingsRepository)
    val lanSync = LanSyncCoordinator(application, repository)
    private val updateManager = UpdateManager(application)
    private val semanticSearchEngine = SemanticSearch()
    private val converter = Converter()
    private val mathEvaluator = MathEvaluator()

    private val _activeNotes = MutableStateFlow<List<Note>>(emptyList())
    val activeNotes: StateFlow<List<Note>> = _activeNotes.asStateFlow()

    private val _archivedNotes = MutableStateFlow<List<Note>>(emptyList())
    val archivedNotes: StateFlow<List<Note>> = _archivedNotes.asStateFlow()

    private val _currentNote = MutableStateFlow<Note?>(null)
    val currentNote: StateFlow<Note?> = _currentNote.asStateFlow()

    private val _settings = MutableStateFlow(AppSettings())
    val settings: StateFlow<AppSettings> = _settings.asStateFlow()

    private val _aiSettings = MutableStateFlow(AISettings())
    val aiSettings: StateFlow<AISettings> = _aiSettings.asStateFlow()

    private val _syncSettings = MutableStateFlow(SyncSettings())
    val syncSettings: StateFlow<SyncSettings> = _syncSettings.asStateFlow()

    private val _syncStatus = MutableStateFlow<SyncRunState>(SyncRunState.Idle)
    val syncStatus: StateFlow<SyncRunState> = _syncStatus.asStateFlow()

    private val _syncMessage = MutableStateFlow("")
    val syncMessage: StateFlow<String> = _syncMessage.asStateFlow()

    private val _aiTestResult = MutableStateFlow("")
    val aiTestResult: StateFlow<String> = _aiTestResult.asStateFlow()

    private val _toast = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val toast: SharedFlow<String> = _toast.asSharedFlow()

    private val _isRouting = MutableStateFlow(false)
    val isRouting: StateFlow<Boolean> = _isRouting.asStateFlow()

    private val _lastRoute = MutableStateFlow<ModeDecision?>(null)
    val lastRoute: StateFlow<ModeDecision?> = _lastRoute.asStateFlow()

    /** Une demande a créé une autre note : l'écran d'édition l'ouvre (sa route
     *  change), sinon une recomposition rouvrirait l'ancienne note. */
    private val _openNote = MutableSharedFlow<Long>(extraBufferCapacity = 1)
    val openNote: SharedFlow<Long> = _openNote.asSharedFlow()

    private val _semanticResults = MutableStateFlow<List<Note>>(emptyList())
    val semanticResults: StateFlow<List<Note>> = _semanticResults.asStateFlow()

    val updatePhase: StateFlow<UpdateManager.Phase> = updateManager.phase
    val currentVersion: String get() = updateManager.currentVersion

    private var pendingSave: Job? = null
    private var dirtyNote: Note? = null

    init {
        VaultKeyring.init(application)
        viewModelScope.launch {
            VaultKeyring.isUnlocked.collectLatest { unlocked -> if (unlocked) onVaultOpened() else onVaultClosed() }
        }
        syncEngine.start(viewModelScope)
        lanSync.attach(viewModelScope)
        lanSync.requestSync(0)
        viewModelScope.launch { repository.activeNotes.collectLatest { _activeNotes.value = it } }
        viewModelScope.launch { repository.archivedNotes.collectLatest { _archivedNotes.value = it } }
        viewModelScope.launch {
            appSettingsRepository.settings.collectLatest {
                _settings.value = it
                TimerRegistry.shared.alarmSound = it.alarmSound
            }
        }
        viewModelScope.launch { aiSettingsRepository.settings.collectLatest { _aiSettings.value = it } }
        viewModelScope.launch { syncSettingsRepository.settings.collectLatest { _syncSettings.value = it } }
        viewModelScope.launch {
            syncEngine.state.collectLatest {
                // Une nouvelle synchro efface l'ancien message (« Synchronisation terminée »
                // restait affiché sous une erreur plus récente).
                if (it == SyncRunState.Syncing) _syncMessage.value = ""
                _syncStatus.value = it
            }
        }
    }

    // ---- Notes ----

    suspend fun createNoteAndGetId(content: String = "", keyword: String = ""): Long {
        flush()
        return repository.createNote(content, keyword).id
    }

    fun open(noteId: Long) {
        viewModelScope.launch {
            flush()
            _currentNote.value = repository.getNoteById(noteId)?.let(::displayable)
        }
    }

    fun close() {
        viewModelScope.launch { flush() }
    }

    /** Modification en mémoire, persistée au plus toutes les 400 ms. */
    /** Copie une image choisie dans la note courante et ajoute sa ligne au texte. */
    fun addImage(source: Uri) {
        val current = _currentNote.value ?: return
        viewModelScope.launch {
            val name = withContext(Dispatchers.IO) { NoteAttachments.import(getApplication(), current.uuid, source) }
            if (name == null) { showToast("Cette image ne peut pas être lue."); return@launch }
            val text = _currentNote.value?.content ?: current.content
            val separator = if (text.isEmpty() || text.endsWith("\n")) "" else "\n"
            edit(text + separator + NoteAttachments.markdown(name) + "\n")
        }
    }

    /** Retire la ligne d'une image et son fichier. */
    fun removeImage(name: String) {
        val current = _currentNote.value ?: return
        NoteAttachments.remove(getApplication(), current.uuid, name)
        val text = current.content.lines().filterNot { line -> NoteAttachments.names(line).contains(name) }.joinToString("\n")
        edit(text)
    }

    fun edit(content: String) {
        val current = _currentNote.value ?: return
        if (current.content == content) return
        val updated = current.copy(content = content, keyword = current.copy(content = content).detectKeyword())
        _currentNote.value = updated
        dirtyNote = updated
        pendingSave?.cancel()
        pendingSave = viewModelScope.launch {
            delay(SAVE_DEBOUNCE_MS)
            pendingSave = null
            persistDirty() // ne passe pas par flush() : il annulerait ce job, donc l'écriture
        }
    }

    /** Écrit tout de suite la modification en attente (changement d'écran, arrière-plan). */
    suspend fun flush() {
        pendingSave?.cancel(); pendingSave = null
        persistDirty()
    }

    private suspend fun persistDirty() {
        val dirty = dirtyNote ?: return
        // Note sécurisée et coffre fermé : elle attend en mémoire, jamais écrite en clair.
        val toStore = storable(dirty) ?: return
        dirtyNote = null
        // L'écriture ne doit jamais être interrompue à mi-chemin : une frappe
        // ou un retour arrière qui annule la coroutine ne perd pas la note.
        val saved = withContext(NonCancellable) { repository.updateNote(toStore) }
        purgeJournalIfNeeded()
        if (_currentNote.value?.id == saved.id) {
            _currentNote.value = _currentNote.value?.copy(updatedAt = saved.updatedAt, keyword = saved.keyword)
        }
        noteChanged()
    }

    private fun persistNow(note: Note, unseal: Boolean = false) {
        viewModelScope.launch {
            pendingSave?.cancel()
            val toStore = storable(note, unseal) ?: run { dirtyNote = note; return@launch }
            dirtyNote = null
            val saved = repository.updateNote(toStore)
            purgeJournalIfNeeded()
            // À l'écran, le texte en clair (pas l'enveloppe stockée).
            if (_currentNote.value?.id == saved.id) _currentNote.value = saved.copy(content = note.content)
            noteChanged()
        }
    }

    fun togglePin(note: Note) {
        viewModelScope.launch {
            repository.setPinned(note, !note.isPinned)
            if (_currentNote.value?.id == note.id) _currentNote.value = repository.getNoteById(note.id)?.let(::displayable)
            showToast(if (note.isPinned) "Note désépinglée" else "Note épinglée")
        }
    }

    fun archive(note: Note) {
        viewModelScope.launch {
            flush()
            repository.archiveNote(note)
            if (_currentNote.value?.id == note.id) _currentNote.value = _currentNote.value?.copy(archived = true)
            showToast("Note archivée")
            noteChanged()
        }
    }

    fun unarchive(note: Note) {
        viewModelScope.launch {
            repository.unarchiveNote(note)
            if (_currentNote.value?.id == note.id) _currentNote.value = _currentNote.value?.copy(archived = false)
            noteChanged()
        }
    }

    fun duplicate(note: Note) {
        viewModelScope.launch { repository.duplicateNote(note); showToast("Note dupliquée") }
    }

    fun rename(note: Note, title: String) {
        viewModelScope.launch {
            val saved = repository.renameNote(note, title)
            if (_currentNote.value?.id == note.id) _currentNote.value = _currentNote.value?.copy(title = saved.title)
        }
    }

    fun delete(note: Note) {
        viewModelScope.launch {
            if (_currentNote.value?.id == note.id) { dirtyNote = null; pendingSave?.cancel(); _currentNote.value = null }
            repository.deleteNote(note)
            TimerRegistry.shared.discard(note.uuid)
            noteChanged()
        }
    }

    fun deleteEmptyNotes() {
        viewModelScope.launch { flush(); repository.deleteEmpty() }
    }

    // ---- Notes sécurisées ----

    private var purgeJournal = false

    /** Version écrivable sur disque et synchronisable : le corps d'une note
     *  sécurisée y est toujours chiffré. Null quand il faudrait chiffrer mais
     *  que le coffre est fermé. */
    private suspend fun storable(note: Note, unseal: Boolean = false): Note? {
        val previous = repository.getNoteById(note.id)
        // Une note déjà au coffre y reste pendant la frappe, même si son
        // en-tête « vault » est momentanément effacé.
        val wasVault = previous?.isVault == true
        val wantsVault = note.keyword == VaultEnvelope.KEYWORD || (wasVault && !unseal)
        if (!wantsVault || VaultEnvelope.isSealed(note.content)) return note
        val sealed = VaultKeyring.seal(note.content) ?: return null
        // Première version chiffrée sur disque : l'ancienne était en clair.
        if (previous != null && !VaultEnvelope.isSealed(previous.content)) purgeJournal = true
        return note.copy(content = sealed, keyword = note.copy(content = sealed).detectKeyword())
    }

    private suspend fun purgeJournalIfNeeded() {
        if (!purgeJournal) return
        purgeJournal = false
        repository.purgeJournal()
    }

    /** Note telle qu'on l'affiche : déchiffrée si le coffre est ouvert. */
    private fun displayable(note: Note): Note {
        if (!VaultEnvelope.isSealed(note.content)) return note
        return VaultKeyring.open(note.content)?.let { note.copy(content = it) } ?: note
    }

    /** Contenus scellés connus (vérifier le mot de passe saisi sur un nouvel appareil). */
    fun sealedVaultContents(): List<String> =
        (_activeNotes.value + _archivedNotes.value).map { it.content }.filter(VaultEnvelope::isSealed)

    private fun onVaultOpened() {
        _currentNote.value?.let { _currentNote.value = displayable(it) }
        // Une note retenue (coffre fermé) est chiffrée et écrite maintenant.
        if (dirtyNote != null) viewModelScope.launch { flush() }
    }

    /** Coffre refermé : le texte en clair quitte la mémoire de l'écran. */
    private suspend fun onVaultClosed() {
        val current = _currentNote.value ?: return
        if (current.isVault && dirtyNote == null) {
            _currentNote.value = repository.getNoteById(current.id) ?: current
        }
    }

    /** Arrière-plan : on écrit ce qui attend, puis le coffre se referme. */
    fun onAppBackground() {
        viewModelScope.launch {
            flush()
            VaultKeyring.lock()
        }
    }

    // ---- Modes ----

    /** Change le mode de la note courante en réécrivant sa première ligne (port de NoteStore.setMode). */
    fun setMode(mode: NoteMode) {
        val note = _currentNote.value ?: return
        if (VaultEnvelope.isSealed(note.content)) { showToast("Ouvre le coffre pour changer le mode de cette note."); return }
        val lines = note.content.split("\n").toMutableList()
        val firstTrimmed = lines.firstOrNull()?.trim().orEmpty()
        val headKeyword = firstTrimmed.substringBefore(":").trim().lowercase()
        val hasHeader = Note.knownKeywords.contains(firstTrimmed.lowercase()) || Note.knownKeywords.contains(headKeyword)
        var suffix = ""
        if (hasHeader && firstTrimmed.contains(":")) suffix = firstTrimmed.substringAfter(":").trim()
        if (hasHeader && lines.isNotEmpty()) lines.removeAt(0)

        if (mode != NoteMode.PLAIN) {
            lines.add(0, if (suffix.isEmpty()) mode.keyword else "${mode.keyword}: $suffix")
        }
        var content = lines.joinToString("\n")
        if (mode == NoteMode.LIST) content = ListModeFormatter.normalizeForListMode(content, forceListHeader = true)
        if (mode == NoteMode.TIMER && lines.size == 1) content += "\ncountdown 10:00"
        val updated = note.copy(content = content, keyword = note.copy(content = content).detectKeyword())
        _currentNote.value = updated
        persistNow(updated, unseal = mode != NoteMode.VAULT)
    }

    // ---- Demande en langage naturel (⌘K) ----

    fun routeQuestion(question: String) {
        val trimmed = question.trim()
        if (trimmed.isEmpty()) return
        val note = _currentNote.value
        // Une note sécurisée ne sort jamais de l'appareil, même la demande.
        if (note?.isVault == true) { showToast("Note sécurisée : la barre de commande et l'IA n'y ont pas accès."); return }
        // Levé tout de suite (pas dans la coroutine) : l'écran garde la barre
        // de demande ouverte, avec son indicateur, jusqu'à la réponse.
        _isRouting.value = true
        viewModelScope.launch {
            try {
                flush()
                val decision = ModeRoutingFeature.route(trimmed, note?.keyword, _aiSettings.value.config)
                _lastRoute.value = decision
                val detail = apply(decision, trimmed, note)
                var message = "Mode ${decision.mode.label} via ${decision.source.label} — $detail"
                if (decision.source == RouteSource.MOTS_CLES && decision.echec != null) message += " (JEV : ${decision.echec})"
                showToast(message)
            } finally {
                _isRouting.value = false
            }
        }
    }

    private suspend fun apply(decision: ModeDecision, question: String, note: Note?): String = when (decision.mode) {
        NoteMode.MATH -> applyMath(question, note)
        NoteMode.LIST -> applyList(question, note)
        NoteMode.TIMER -> applyTimer(question)
        NoteMode.CODE -> applyCode(note)
        NoteMode.PLAIN, NoteMode.VAULT -> "Aucun mode appliqué."
    }

    /**
     * Ordre : expression déjà écrite → conversion → formule rédigée par l'IA
     * (seule exception au contrat JEV) → dernier recours déterministe.
     */
    private suspend fun applyMath(question: String, note: Note?): String {
        strictExpression(question)?.let {
            writeMathBlock("$it =", note)
            return "Expression notée, résultat calculé par la note."
        }
        if (converter.convert(question) != null || CURRENCY_LIKE.matches(question.trim())) {
            writeMathBlock(question.trim().trimEnd('=').trim() + " =", note)
            return "Conversion notée."
        }

        var draftFailure: String? = null
        val ai = _aiSettings.value
        val config = ai.config
        if (config != null && ai.formulaDraftEnabled) {
            when (val outcome = FormulaDraftFeature.draft(question, config)) {
                is JEVOutcome.Ok -> {
                    val origin = outcome.value.model?.let { "IA ($it)" } ?: "IA"
                    val header = "// ${question.take(80)} — formule proposée par l'$origin, à vérifier"
                    writeMathBlock((listOf(header) + outcome.value.lines).joinToString("\n"), note)
                    return "Formule rédigée par l'$origin et calculée par la note — vérifie-la."
                }
                is JEVOutcome.Erreur -> draftFailure = outcome.message
            }
        }

        val suffix = draftFailure?.let { " ($it)" }.orEmpty()
        numericFragment(question)?.let {
            writeMathBlock("$it =", note)
            return "Expression notée, résultat calculé par la note.$suffix"
        }
        return "Aucune expression évaluable trouvée — note inchangée.$suffix"
    }

    private suspend fun writeMathBlock(block: String, note: Note?) {
        val trimmed = block.trim()
        if (trimmed.isEmpty()) return
        if (note == null) { repository.createNote("math: Calcul\n$trimmed", "math"); return }
        val content = when {
            note.keyword == "math" -> note.content + "\n" + trimmed
            note.content.isBlank() -> "math: Calcul\n$trimmed"
            else -> "math: Calcul\n$trimmed\n\n${note.content}"
        }
        replaceCurrent(note, content)
    }

    private suspend fun applyList(question: String, note: Note?): String {
        RecipeIngredientExtractor.firstUrl(question)?.let { return applyRecipe(it, note) }
        val items = listItems(question)
        if (note == null) {
            repository.createNote("list: ${listTitle(question)}\n" + items.joinToString("\n") { "* $it" }, "list")
            return "Liste créée."
        }
        if (items.isNotEmpty()) {
            val body = items.joinToString("\n") { "* $it" }
            var content = if (note.keyword == "list" && existingListBody(note).isNotEmpty()) ensureListHeader(note) + "\n" + body
            else "list: ${listTitle(question)}\n$body"
            content = ListModeFormatter.normalizeForListMode(content, forceListHeader = true)
            replaceCurrent(note, content)
            return "Liste écrite dans la note."
        }
        if (note.keyword == "list") return "La note est déjà en liste."
        val normalized = ListModeFormatter.normalizeForListMode(note.content, forceListHeader = true)
        if (normalized == note.content) return "Rien à mettre en liste — note inchangée."
        replaceCurrent(note, normalized)
        return "Note convertie en liste."
    }

    /** Ingrédients lus dans les données structurées de la page (schema.org), sans IA. */
    private suspend fun applyRecipe(url: String, note: Note?): String {
        val host = url.substringAfter("://").substringBefore('/').removePrefix("www.")
        return when (val outcome = RecipeIngredientExtractor.fetch(url)) {
            is RecipeIngredientExtractor.Outcome.Ok -> {
                val recipe = outcome.recipe
                val body = recipe.ingredients.joinToString("\n") { "* $it" }
                // Source en fin de liste : l'aperçu de la note montre les ingrédients.
                val block = "list: ${recipe.title ?: "Recette"}\n$body\n// $url"
                val content = ListModeFormatter.normalizeForListMode(
                    if (note == null || note.content.isBlank() || note.keyword == "list") block else "$block\n\n${note.content}",
                    forceListHeader = true
                )
                if (note == null) repository.createNote(content, "list") else replaceCurrent(note, content)
                "${recipe.ingredients.size} ingrédient(s) lus sur $host."
            }
            is RecipeIngredientExtractor.Outcome.Ko -> "Recette illisible sur $host : ${outcome.failure.message} — note inchangée."
        }
    }

    private suspend fun applyTimer(question: String): String {
        val (type, totalSeconds) = KeywordIntentRouter.parseTimerRequest(question)
        val content: String
        val label: String
        when (type) {
            KeywordIntentRouter.TimerType.COUNTDOWN -> {
                val min = totalSeconds / 60; val sec = totalSeconds % 60
                content = "timer\ncountdown $min:${"%02d".format(sec)}"
                label = if (sec == 0) "Minuteur $min min" else "Minuteur $min min $sec sec"
            }
            KeywordIntentRouter.TimerType.STOPWATCH -> { content = "timer\nstopwatch"; label = "Chronomètre" }
            KeywordIntentRouter.TimerType.POMODORO -> {
                val min = totalSeconds / 60
                content = "timer\npomodoro $min:00"; label = "Pomodoro $min min"
            }
        }
        // Note vide (on vient de l'ouvrir pour la demande) : elle devient le minuteur.
        val current = _currentNote.value
        if (current != null && current.content.isBlank()) {
            dirtyNote = null; pendingSave?.cancel()
            replaceCurrent(current, content)
            return "$label créé."
        }
        flush()
        val created = repository.createNote(content, "timer")
        _currentNote.value = created
        _openNote.tryEmit(created.id)
        return "$label créé."
    }

    private suspend fun applyCode(note: Note?): String {
        if (note == null) { repository.createNote("code", "code"); return "Note code créée." }
        if (note.keyword == "code") return "La note est déjà en code."
        replaceCurrent(note, if (note.content.isBlank()) "code" else "code\n${note.content}")
        return "Note convertie en code."
    }

    private suspend fun replaceCurrent(note: Note, content: String) {
        val updated = note.copy(content = content, keyword = note.copy(content = content).detectKeyword())
        val saved = repository.updateNote(updated)
        if (_currentNote.value?.id == note.id) _currentNote.value = saved
        noteChanged()
    }

    /**
     * La demande, débarrassée des mots d'appel, est déjà une expression
     * complète : aucun mot inconnu (l'évaluateur les ignorerait en silence,
     * « aire d'un cercle de rayon 3 » donnerait 3).
     */
    private fun strictExpression(question: String): String? {
        val stripped = question
            .replace(Regex("(?i)\\b(calcule|calcul|combien|resultat|résultat|donne|fait|font)\\b"), "")
            .replace("?", "").trim().trimEnd('=').trim()
        if (stripped.isEmpty() || stripped.none(Char::isDigit) || mathEvaluator.evaluate(stripped) == null) return null
        // « of » fait partie de la syntaxe de l'évaluateur (« 50% of 200 »).
        val words = Regex("[\\p{L}_][\\p{L}\\p{N}_]*").findAll(stripped).map { it.value }
        return if (words.all { MathEvaluator.isKnownName(it) || it.lowercase() == "of" }) stripped else null
    }

    /** Dernier recours sans IA : le premier fragment numérique qui contient un opérateur (« 12*8 stp » → « 12*8 »). */
    private fun numericFragment(question: String): String? {
        val expression = Regex("[0-9(][0-9()+\\-*/^.,\\s]*[0-9)]").find(question)?.value?.trim() ?: return null
        if (expression.none { it in "+-*/^" } || mathEvaluator.evaluate(expression) == null) return null
        return expression
    }

    private fun listTitle(question: String): String {
        val lower = KeywordIntentRouter.normalized(question)
        return when {
            lower.contains("course") -> "Courses"
            lower.contains("ingredient") -> "Ingrédients"
            lower.contains("tache") || lower.contains("todo") -> "Tâches"
            else -> "Liste"
        }
    }

    private fun existingListBody(note: Note): String = note.content.split("\n").drop(1).joinToString("\n").trim()

    private fun ensureListHeader(note: Note): String {
        val first = note.content.split("\n").firstOrNull()?.trim().orEmpty()
        return if (ListModeFormatter.isListHeader(first)) note.content.trimEnd() else "list\n${note.content.trimEnd()}"
    }

    // ---- Recherche ----

    fun semanticSearch(query: String) {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) { _semanticResults.value = emptyList(); return }
        viewModelScope.launch {
            val hits = semanticSearchEngine.search(trimmed, (_activeNotes.value + _archivedNotes.value).filter { !it.isVault })
            _semanticResults.value = hits.map { it.note }
        }
    }

    // ---- Réglages ----

    fun setTheme(mode: ThemeMode) = viewModelScope.launch { appSettingsRepository.setTheme(mode) }
    private val alarmPreview = AlarmPlayer()

    /** Choix de la sonnerie, joué une fois pour l'entendre. */
    fun setAlarmSound(sound: AlarmSound) {
        viewModelScope.launch { appSettingsRepository.setAlarmSound(sound) }
        previewAlarm(sound)
    }

    fun previewAlarm(sound: AlarmSound) = alarmPreview.play(getApplication(), sound, loop = false)

    override fun onCleared() {
        alarmPreview.stop()
        super.onCleared()
    }

    fun setColorTheme(theme: ColorTheme) = viewModelScope.launch {
        appSettingsRepository.setColorTheme(theme)
        LauncherIcons.apply(getApplication(), theme)
    }
    fun setFontSize(size: Float) = viewModelScope.launch { appSettingsRepository.setFontSize(size) }
    fun setListCheckTrigger(trigger: String) = viewModelScope.launch { appSettingsRepository.setListCheckTrigger(trigger) }
    fun setAutoCleanup(enabled: Boolean) = viewModelScope.launch { appSettingsRepository.setAutoCleanup(enabled) }
    fun setConfirmDelete(enabled: Boolean) = viewModelScope.launch { appSettingsRepository.setConfirmDelete(enabled) }
    fun setAppcastUrl(url: String) = viewModelScope.launch { appSettingsRepository.setAppcastUrl(url) }

    fun setAiEnabled(enabled: Boolean) = viewModelScope.launch { aiSettingsRepository.setEnabled(enabled) }
    fun setFormulaDraftEnabled(enabled: Boolean) = viewModelScope.launch { aiSettingsRepository.setFormulaDraftEnabled(enabled) }
    fun setJevUrl(url: String) = viewModelScope.launch { aiSettingsRepository.setJevUrl(url) }
    fun setJevAccessToken(clientId: String, secret: String) = viewModelScope.launch { aiSettingsRepository.setAccessToken(clientId, secret) }
    fun setJevDelaiMs(ms: Int) = viewModelScope.launch { aiSettingsRepository.setJevDelaiMs(ms) }

    fun testJev() {
        viewModelScope.launch {
            val config = _aiSettings.value.copy(enabled = true).config
            if (config == null) { _aiTestResult.value = "Aucune URL de serveur."; return@launch }
            _aiTestResult.value = "Test en cours…"
            val outcome = JEVClient.decider(config, ModeRoutingFeature.instructions, ModeRoutingFeature.schema, listOf("minuteur 25 minutes"))
            _aiTestResult.value = when (outcome) {
                is JEVOutcome.Ok -> {
                    val mode = (outcome.value.firstOrNull()?.get("mode") as? be.cobaltfilms.alphanote.ai.JEVValue.Str)?.value
                    if (mode != null) "Serveur joignable — « minuteur 25 minutes » → $mode." else "Serveur joignable mais aucun mode désigné."
                }
                is JEVOutcome.Erreur -> outcome.message
            }
        }
    }

    // ---- Synchro Nextcloud ----

    fun setNextcloudServerUrl(url: String) = viewModelScope.launch { syncSettingsRepository.setServerUrl(url) }
    fun setNextcloudUsername(username: String) = viewModelScope.launch { syncSettingsRepository.setUsername(username) }
    fun setNextcloudPassword(password: String) {
        viewModelScope.launch {
            runCatching { syncSettingsRepository.savePassword(password) }
                .onSuccess { _syncMessage.value = if (password.isBlank()) "Mot de passe supprimé." else "Mot de passe enregistré." }
                .onFailure { _syncMessage.value = it.message ?: "Impossible d'enregistrer le mot de passe." }
        }
    }
    /** L'app revient au premier plan : synchro de rattrapage. */
    fun onAppForeground() {
        syncEngine.onForeground()
        lanSync.requestSync(0)
    }

    /** Une modification : synchro Nextcloud (30 s) et, si appairé, passe sur le réseau local (3 s). */
    private fun noteChanged() {
        syncEngine.notifyLocalChange()
        lanSync.requestSync(LAN_CHANGE_DELAY_MS)
    }

    fun setLanEnabled(enabled: Boolean) = lanSync.setEnabled(enabled)
    fun syncLanNow() = viewModelScope.launch { lanSync.syncNow() }
    fun forgetLan() = lanSync.forget()
    fun pairLan(code: String, onResult: (String) -> Unit) = viewModelScope.launch { onResult(lanSync.pair(code)) }

    fun setSyncEnabled(enabled: Boolean) = viewModelScope.launch { syncSettingsRepository.setSyncEnabled(enabled) }
    fun setSyncIntervalMinutes(minutes: Int) = viewModelScope.launch { syncSettingsRepository.setSyncIntervalMinutes(minutes) }

    fun testNextcloudConnection() {
        viewModelScope.launch {
            runCatching { syncEngine.testConnection() }
                .onSuccess { _syncMessage.value = "Connexion Nextcloud validée." }
                .onFailure { _syncMessage.value = it.message ?: "Connexion Nextcloud impossible." }
        }
    }

    fun runNextcloudSync() {
        viewModelScope.launch {
            flush()
            runCatching { syncEngine.runManualSync() }
                .onSuccess { _syncMessage.value = "Synchronisation terminée."; _currentNote.value?.let { _currentNote.value = repository.getNoteById(it.id)?.let(::displayable) } }
                .onFailure { _syncMessage.value = it.message ?: "Synchronisation impossible." }
        }
    }

    fun createNextcloudBackup() {
        viewModelScope.launch {
            runCatching { syncEngine.createBackup() }
                .onSuccess { _syncMessage.value = "Backup créé : $it" }
                .onFailure { _syncMessage.value = it.message ?: "Backup Nextcloud impossible." }
        }
    }

    fun restoreLatestNextcloudBackup() {
        viewModelScope.launch {
            runCatching { syncEngine.restoreLatestBackup() }
                .onSuccess { _syncMessage.value = "Restauration terminée : $it note(s)." }
                .onFailure { _syncMessage.value = it.message ?: "Restauration Nextcloud impossible." }
        }
    }

    // ---- Mises à jour ----

    fun checkForUpdates() = viewModelScope.launch { updateManager.check(_settings.value.appcastUrl) }
    fun downloadUpdate(info: AppUpdateInfo) = viewModelScope.launch { updateManager.download(info) }
    fun installUpdate(file: File) {
        if (!updateManager.install(file)) showToast("Autorise l'installation depuis AlphaNote, puis réessaie.")
    }
    fun resetUpdate() = updateManager.reset()

    // ---- Export ----

    suspend fun exportJson(): String {
        flush()
        val notes = repository.getAllNotDeleted().map { CloudNoteDto.fromNote(it) }
        val array = JSONArray()
        notes.forEach { array.put(org.json.JSONObject(CloudJsonCoder.encodeNote(it))) }
        return array.toString(2)
    }

    suspend fun exportMarkdown(): String {
        flush()
        return repository.getAllNotDeleted().joinToString("\n\n---\n\n") { note ->
            "# ${note.effectiveTitle.ifEmpty { "Note sans titre" }}\n\n${note.content}"
        }
    }

    // ---- Divers ----

    fun showToast(message: String) { _toast.tryEmit(message) }

    companion object {
        /** Éléments d'une demande de liste, sans IA (même règle que macOS). */
        internal fun listItems(text: String): List<String> {
            val raw = text
                // « … à mes courses », « … dans la liste » : la destination, pas un élément.
                .replace(Regex("""\s+(à|a|dans|sur|pour)\s+(ma|mes|la|le|les|notre|nos|une?)\s+(liste|checklist|todo|to-do|courses)\b.*$""", RegexOption.IGNORE_CASE), "")
                .replace(Regex("[;|]+"), ",")
                .replace(Regex("\\s+et\\s+", RegexOption.IGNORE_CASE), ", ")
                .replace(Regex("\\b(fais|cree|crée|donne|genere|génère|ajoute)\\b", RegexOption.IGNORE_CASE), "")
                .replace(Regex("\\b(liste|checklist|todo|to-do|courses)\\b", RegexOption.IGNORE_CASE), "")
                .replace(":", " ")
                .trim()
            return raw.split(",")
                .map { it.trim().replace(Regex("\\s+"), " ") }
                .filter { part ->
                    if (part.length < 2) return@filter false
                    val folded = KeywordIntentRouter.normalized(part)
                    !(folded.startsWith("je veux") || folded.startsWith("stp") || folded.startsWith("svp"))
                }
                .distinct()
        }

        private const val SAVE_DEBOUNCE_MS = 400L
        private const val LAN_CHANGE_DELAY_MS = 3_000L
        private val CURRENCY_LIKE = Regex("(?i)^\\s*[-+]?\\d+(?:[.,]\\d+)?\\s*[A-Za-z]{3}\\s+(to|in|en)\\s+[A-Za-z]{3}\\s*=?\\s*$")
    }
}
