package be.cobaltfilms.alphanote.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ai.NoteMode
import be.cobaltfilms.alphanote.domain.CurrencyRateService
import be.cobaltfilms.alphanote.domain.MathDocumentEvaluator
import be.cobaltfilms.alphanote.domain.MathInlineApplier
import be.cobaltfilms.alphanote.timer.TimerRegistry
import be.cobaltfilms.alphanote.ui.components.CommandField
import be.cobaltfilms.alphanote.ui.components.ModeChip
import be.cobaltfilms.alphanote.ui.editor.EditorDecorations
import be.cobaltfilms.alphanote.ui.editor.NoteEditor
import be.cobaltfilms.alphanote.ui.editor.TimerNoteView
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette

/** Écran d'une note : barre fine (titre, pastille de mode, menu) + éditeur unique. */
@Composable
fun NoteEditScreen(noteId: Long, viewModel: NoteViewModel, onBack: () -> Unit) {
    val palette = LocalAlphaPalette.current
    val currentNote by viewModel.currentNote.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val isRouting by viewModel.isRouting.collectAsState()
    val clipboard = LocalClipboardManager.current
    val snackbarHostState = remember { SnackbarHostState() }
    val focusRequester = remember { FocusRequester() }
    val evaluator = remember { MathDocumentEvaluator() }

    var editorValue by remember { mutableStateOf(TextFieldValue("")) }
    var loadedNoteId by remember { mutableLongStateOf(-1L) }
    var lastEdited by remember { mutableStateOf<String?>(null) }
    var showCommand by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.toast.collect { snackbarHostState.showSnackbar(it, duration = SnackbarDuration.Long) } }
    var awaitingRoute by remember { mutableStateOf(false) }
    LaunchedEffect(isRouting, awaitingRoute) {
        if (awaitingRoute && !isRouting) { awaitingRoute = false; showCommand = false }
    }
    LaunchedEffect(noteId) { loadedNoteId = -1L; viewModel.open(noteId) }

    val note = currentNote
    val mode = NoteMode.fromKeyword(note?.keyword)

    // Chargement, et changements externes (mode, synchro, demande ⌘K).
    LaunchedEffect(note?.id, note?.content) {
        val n = note ?: return@LaunchedEffect
        if (loadedNoteId != n.id) {
            var text = n.content
            if (NoteMode.fromKeyword(n.keyword) == NoteMode.MATH) text = MathInlineApplier.apply(text, text.length, evaluator, respectCaret = false).text
            editorValue = TextFieldValue(text, TextRange(text.length))
            loadedNoteId = n.id
            lastEdited = text
            if (text != n.content) viewModel.edit(text)
        } else if (n.content != editorValue.text && n.content != lastEdited) {
            // Une formule écrite par une demande ⌘K ou la synchro arrive sans
            // ses résultats : on les calcule comme au chargement.
            var text = n.content
            if (NoteMode.fromKeyword(n.keyword) == NoteMode.MATH) text = MathInlineApplier.apply(text, text.length, evaluator, respectCaret = false).text
            editorValue = TextFieldValue(text, TextRange(text.length.coerceAtMost(editorValue.selection.end).coerceAtLeast(0)))
            lastEdited = text
            if (text != n.content) viewModel.edit(text)
        }
    }

    // Taux de change arrivés : on réévalue la note math.
    LaunchedEffect(mode) {
        if (mode != NoteMode.MATH) return@LaunchedEffect
        CurrencyRateService.shared.ratesUpdated.collect {
            val outcome = MathInlineApplier.apply(editorValue.text, editorValue.selection.end, evaluator, respectCaret = false)
            if (outcome.changed) { editorValue = editorValue.copy(text = outcome.text, selection = TextRange(outcome.cursor)); lastEdited = outcome.text; viewModel.edit(outcome.text) }
        }
    }

    fun processInput(newValue: TextFieldValue) {
        var processed = newValue
        val previous = editorValue.text
        if (processed.text != previous) {
            val detected = NoteMode.fromKeyword(be.cobaltfilms.alphanote.model.Note(content = processed.text).detectKeyword())
            if (detected == NoteMode.LIST) {
                EditorDecorations.continueBullet(previous, processed)?.let { processed = it }
            }
            if (detected == NoteMode.MATH) {
                val outcome = MathInlineApplier.apply(processed.text, processed.selection.end, evaluator, respectCaret = true)
                if (outcome.changed) processed = processed.copy(text = outcome.text, selection = TextRange(outcome.cursor))
            }
        }
        editorValue = processed
        if (processed.text != previous) { lastEdited = processed.text; viewModel.edit(processed.text) }
    }

    // Passage en arrière-plan (bouton accueil, appli tuée ensuite) : on écrit tout de suite.
    val lifecycleOwner = androidx.compose.ui.platform.LocalLifecycleOwner.current
    androidx.compose.runtime.DisposableEffect(lifecycleOwner) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_STOP) viewModel.close()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val leave: () -> Unit = { viewModel.close(); onBack() }
    BackHandler { if (showCommand) showCommand = false else leave() }

    Scaffold(
        containerColor = palette.content,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            Column(modifier = Modifier.imePadding().navigationBarsPadding()) {
                if (showCommand) {
                    CommandField(
                        currentKeyword = note?.keyword, isRouting = isRouting,
                        // La barre reste ouverte (indicateur visible) pendant la
                        // demande : une formule rédigée par l'IA prend ~10 s.
                        onSubmit = { viewModel.routeQuestion(it); awaitingRoute = true },
                        onClose = { showCommand = false }
                    )
                }
            }
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Row(
                modifier = Modifier.fillMaxWidth().background(palette.window).padding(start = 4.dp, end = 8.dp, top = 2.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                IconButton(onClick = leave) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Retour", tint = palette.secondary) }
                if (note?.isPinned == true) Icon(Icons.Default.PushPin, contentDescription = null, tint = palette.accent, modifier = Modifier.size(11.dp))
                Text(
                    note?.let { displayTitle(it) } ?: "",
                    color = palette.secondary, style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
                )
                if (note != null) {
                    ModeChip(mode = mode, onSelect = { viewModel.setMode(it) })
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreHoriz, contentDescription = "Actions", tint = palette.secondary) }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DropdownMenuItem(text = { Text("Demande en langage naturel…") }, leadingIcon = { Icon(Icons.Default.AutoAwesome, null, tint = palette.accent) }, onClick = { menu = false; showCommand = true })
                            DropdownMenuItem(text = { Text(if (note.isPinned) "Désépingler" else "Épingler") }, onClick = { menu = false; viewModel.togglePin(note) })
                            DropdownMenuItem(text = { Text("Renommer…") }, onClick = { menu = false; renaming = true })
                            DropdownMenuItem(text = { Text("Dupliquer") }, onClick = { menu = false; viewModel.duplicate(note) })
                            DropdownMenuItem(text = { Text("Copier le contenu") }, onClick = { menu = false; clipboard.setText(AnnotatedString(editorValue.text)); viewModel.showToast("Contenu copié") })
                            DropdownMenuItem(text = { Text(if (note.archived) "Désarchiver" else "Archiver") }, onClick = { menu = false; if (note.archived) viewModel.unarchive(note) else { viewModel.archive(note); leave() } })
                            DropdownMenuItem(text = { Text("Supprimer", color = palette.timer) }, onClick = { menu = false; if (editorValue.text.isBlank() || !settings.confirmDelete) { viewModel.delete(note); leave() } else confirmDelete = true })
                        }
                    }
                }
            }

            if (note == null) return@Column

            if (mode == NoteMode.TIMER) {
                val (defaultMode, seconds) = TimerRegistry.parameters(note.content)
                val session = remember(note.uuid) { TimerRegistry.shared.session(note.uuid, defaultMode, seconds) }
                TimerNoteView(session = session, title = displayTitle(note), modifier = Modifier.fillMaxSize())
            } else {
                Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    NoteEditor(
                        value = editorValue, onValueChange = ::processInput,
                        mode = mode, fontSize = settings.fontSize, checkTrigger = settings.listCheckTrigger,
                        focusRequester = focusRequester
                    )
                }
                LaunchedEffect(note.id) { if (note.content.isBlank()) runCatching { focusRequester.requestFocus() } }
            }
        }
    }

    if (renaming && note != null) RenameDialog(note, onDismiss = { renaming = false }, onRename = { viewModel.rename(note, it); renaming = false })

    if (confirmDelete && note != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Supprimer cette note ?") },
            text = { Text("« ${displayTitle(note)} » sera supprimée.") },
            confirmButton = { TextButton(onClick = { confirmDelete = false; viewModel.delete(note); leave() }) { Text("Supprimer", color = palette.timer) } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Annuler") } }
        )
    }
}
