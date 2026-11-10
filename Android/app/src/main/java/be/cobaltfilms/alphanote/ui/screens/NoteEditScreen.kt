package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.height
import android.content.ClipData
import android.content.Intent
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.activity.result.PickVisualMediaRequest
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.FileProvider
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Notifications
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import be.cobaltfilms.alphanote.ui.components.ReminderDialog
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
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Label
import androidx.compose.material.icons.filled.Mic
import be.cobaltfilms.alphanote.domain.NoteThemes
import be.cobaltfilms.alphanote.ui.components.ThemeDialog
import be.cobaltfilms.alphanote.ui.components.VoiceNoteStrip
import be.cobaltfilms.alphanote.ui.components.VoiceRecordingBanner
import be.cobaltfilms.alphanote.ui.components.VaultLockScreen
import be.cobaltfilms.alphanote.vault.VaultKeyring
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.focus.onFocusChanged
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
import be.cobaltfilms.alphanote.domain.NoteAttachments
import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.domain.CurrencyRateService
import be.cobaltfilms.alphanote.domain.MathDocumentEvaluator
import be.cobaltfilms.alphanote.domain.MathInlineApplier
import be.cobaltfilms.alphanote.timer.TimerRegistry
import be.cobaltfilms.alphanote.ui.components.CommandField
import be.cobaltfilms.alphanote.ui.components.ModeChip
import be.cobaltfilms.alphanote.ui.components.NoteImageStrip
import be.cobaltfilms.alphanote.ui.editor.EditorDecorations
import be.cobaltfilms.alphanote.ui.editor.NoteEditor
import be.cobaltfilms.alphanote.ui.editor.TimerNoteView
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette

/** Écran d'une note : barre fine (titre, pastille de mode, menu) + éditeur unique. */
@Composable
fun NoteEditScreen(noteId: Long, viewModel: NoteViewModel, onBack: () -> Unit, onOpenNote: (Long) -> Unit = {}) {
    val palette = LocalAlphaPalette.current
    val currentNote by viewModel.currentNote.collectAsState()
    val vaultUnlocked by VaultKeyring.isUnlocked.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val isRouting by viewModel.isRouting.collectAsState()
    val clipboard = LocalClipboardManager.current
    val context = LocalContext.current
    var showReminder by remember { mutableStateOf(false) }
    val notificationPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) viewModel.showToast("Sans autorisation, les rappels arriveront sans notification. Activez-la dans Réglages.")
    }
    val themes by viewModel.themeByUuid.collectAsState()
    val recorder = viewModel.voiceRecorder
    var showTheme by remember { mutableStateOf(false) }
    val microphonePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) viewModel.startVoiceNote()
        else viewModel.showToast("Micro non autorisé. Autorise AlphaNote dans les réglages de l'appareil.")
    }
    val startVoiceNote = {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) viewModel.startVoiceNote()
        else microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
    }
    val pickImage = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> uri?.let(viewModel::addImage) }
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
    LaunchedEffect(Unit) { viewModel.openNote.collect { id -> if (id != noteId) onOpenNote(id) } }

    val note = currentNote
    val mode = NoteMode.fromKeyword(note?.keyword)

    // Chargement, et changements externes (mode, synchro, demande ⌘K).
    // L'éditeur montre le texte sans les lignes d'images (galerie en dessous).
    LaunchedEffect(note?.id, note?.content) {
        val n = note ?: return@LaunchedEffect
        val visible = NoteAttachments.visibleText(n.content)
        if (loadedNoteId != n.id) {
            var text = visible
            if (NoteMode.fromKeyword(n.keyword) == NoteMode.MATH) text = MathInlineApplier.apply(text, text.length, evaluator, respectCaret = false).text
            editorValue = TextFieldValue(text, TextRange(text.length))
            loadedNoteId = n.id
            lastEdited = text
            if (text != visible) viewModel.edit(NoteAttachments.withImages(text, n.content))
        } else if (visible != editorValue.text && visible != lastEdited) {
            // Une formule écrite par une demande ⌘K ou la synchro arrive sans
            // ses résultats : on les calcule comme au chargement.
            var text = visible
            if (NoteMode.fromKeyword(n.keyword) == NoteMode.MATH) text = MathInlineApplier.apply(text, text.length, evaluator, respectCaret = false).text
            editorValue = TextFieldValue(text, TextRange(text.length.coerceAtMost(editorValue.selection.end).coerceAtLeast(0)))
            lastEdited = text
            if (text != visible) viewModel.edit(NoteAttachments.withImages(text, n.content))
        }
    }

    /** Texte de l'éditeur → contenu stocké (références d'images remises en fin de note). */
    fun store(text: String) = viewModel.edit(NoteAttachments.withImages(text, viewModel.currentNote.value?.content.orEmpty()))

    // Taux de change arrivés : on réévalue la note math.
    LaunchedEffect(mode) {
        if (mode != NoteMode.MATH) return@LaunchedEffect
        CurrencyRateService.shared.ratesUpdated.collect {
            val outcome = MathInlineApplier.apply(editorValue.text, editorValue.selection.end, evaluator, respectCaret = false)
            if (outcome.changed) { editorValue = editorValue.copy(text = outcome.text, selection = TextRange(outcome.cursor)); lastEdited = outcome.text; store(outcome.text) }
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
        if (processed.text != previous) { lastEdited = processed.text; store(processed.text) }
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
                if (recorder.isRecording) {
                    VoiceRecordingBanner(recorder, onStop = { viewModel.stopVoiceNote() }, onCancel = { viewModel.cancelVoiceNote() })
                }
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
                // Titre modifiable sur place ; vide = titre automatique (première ligne).
                if (note != null) NoteTitleField(note, onRename = { viewModel.rename(note, it) }, modifier = Modifier.weight(1f))
                else Spacer(Modifier.weight(1f))
                // Note sécurisée fermée : ni IA, ni partage, ni copie.
                val locked = note != null && note.isVault && !vaultUnlocked
                if (note != null) {
                    if (!note.isVault) IconButton(onClick = { showCommand = true }) { Icon(Icons.Default.AutoAwesome, contentDescription = "Demande à l'IA", tint = palette.accent) }
                    // Note vocale : pas dans une note sécurisée (l'audio ne serait pas chiffré).
                    if (!note.isVault && mode != NoteMode.TIMER && !recorder.isRecording) {
                        IconButton(onClick = startVoiceNote) { Icon(Icons.Default.Mic, contentDescription = "Note vocale : enregistrer et transcrire", tint = palette.accent) }
                    }
                    if (note.isVault && vaultUnlocked) IconButton(onClick = { VaultKeyring.lockNow() }) { Icon(Icons.Default.Lock, contentDescription = "Verrouiller le coffre", tint = palette.mode(NoteMode.VAULT)) }
                    if (!locked) IconButton(onClick = { shareNote(context, note, note.content) }) { Icon(Icons.Default.Share, contentDescription = "Partager la note", tint = palette.accent) }
                    ModeChip(mode = mode, onSelect = { viewModel.setMode(it) })
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreHoriz, contentDescription = "Actions", tint = palette.secondary) }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            if (!note.isVault) DropdownMenuItem(text = { Text("Rappel…") }, leadingIcon = { Icon(Icons.Default.Notifications, null, tint = palette.accent) }, onClick = { menu = false; showReminder = true })
                            if (!note.isVault) DropdownMenuItem(text = { Text("Demande en langage naturel…") }, leadingIcon = { Icon(Icons.Default.AutoAwesome, null, tint = palette.accent) }, onClick = { menu = false; showCommand = true })
                            if (!note.isVault && mode != NoteMode.TIMER) DropdownMenuItem(
                                text = { Text("Ajouter une image") },
                                leadingIcon = { Icon(Icons.Default.AddPhotoAlternate, null, tint = palette.accent) },
                                onClick = { menu = false; pickImage.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly)) }
                            )
                            if (!note.isVault) DropdownMenuItem(text = { Text("Thème…") }, leadingIcon = { Icon(Icons.Default.Label, null, tint = palette.accent) }, onClick = { menu = false; showTheme = true })
                            DropdownMenuItem(text = { Text(if (note.isPinned) "Désépingler" else "Épingler") }, onClick = { menu = false; viewModel.togglePin(note) })
                            DropdownMenuItem(text = { Text("Renommer…") }, onClick = { menu = false; renaming = true })
                            DropdownMenuItem(text = { Text("Dupliquer") }, onClick = { menu = false; viewModel.duplicate(note) })
                            if (!locked) DropdownMenuItem(text = { Text("Copier le contenu") }, onClick = { menu = false; clipboard.setText(AnnotatedString(editorValue.text)); viewModel.showToast("Contenu copié") })
                            DropdownMenuItem(text = { Text(if (note.archived) "Désarchiver" else "Archiver") }, onClick = { menu = false; if (note.archived) viewModel.unarchive(note) else { viewModel.archive(note); leave() } })
                            DropdownMenuItem(text = { Text("Supprimer", color = palette.timer) }, onClick = { menu = false; if (editorValue.text.isBlank() || !settings.confirmDelete) { viewModel.delete(note); leave() } else confirmDelete = true })
                        }
                    }
                }
            }

            if (note == null) return@Column

            if (note.isVault && !vaultUnlocked) {
                VaultLockScreen(title = note.effectiveTitle, sealedContents = viewModel::sealedVaultContents)
            } else if (mode == NoteMode.TIMER) {
                val (defaultMode, seconds) = TimerRegistry.parameters(note.content)
                val session = remember(note.uuid) { TimerRegistry.shared.session(note.uuid, defaultMode, seconds) }
                TimerNoteView(
                    session = session, title = displayTitle(note), modifier = Modifier.fillMaxSize(),
                    // Mode ou durée changés : la note garde le réglage (aperçu de la liste, synchro).
                    onSettingsChange = { timerMode, seconds ->
                        viewModel.edit(TimerRegistry.contentWithTimerLine(note.content, timerMode, seconds))
                    }
                )
            } else {
                Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    // Les images restent en clair sur l'appareil : pas dans le coffre.
                    val images = if (note.isVault) emptyList() else NoteAttachments.imageNames(note.content)
                    val recordings = if (note.isVault) emptyList() else NoteAttachments.audioNames(note.content)
                    NoteEditor(
                        value = editorValue, onValueChange = ::processInput,
                        mode = mode, fontSize = settings.fontSize, checkTrigger = settings.listCheckTrigger,
                        focusRequester = focusRequester,
                        bottomPadding = if (images.isEmpty() && recordings.isEmpty()) 120.dp else 8.dp
                    )
                    if (recordings.isNotEmpty()) {
                        VoiceNoteStrip(noteUuid = note.uuid, names = recordings, player = viewModel.voicePlayer, onDelete = viewModel::removeVoiceNote)
                    }
                    if (images.isNotEmpty()) {
                        NoteImageStrip(noteUuid = note.uuid, names = images, onRemove = viewModel::removeImage)
                    }
                    if (images.isNotEmpty() || recordings.isNotEmpty()) Spacer(Modifier.height(120.dp))
                }
                LaunchedEffect(note.id) { if (note.content.isBlank()) runCatching { focusRequester.requestFocus() } }
            }
        }
    }

    if (showReminder && note != null) {
        ReminderDialog(
            onDismiss = { showReminder = false },
            onConfirm = { at, kinds ->
                viewModel.addReminder(at, kinds)
                showReminder = false
                if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
        )
    }

    if (showTheme && note != null) {
        ThemeDialog(
            current = themes[note.uuid] ?: NoteThemes.explicit(note.content),
            isExplicit = NoteThemes.explicit(note.content) != null,
            themes = remember(themes) { NoteThemes.distinctNames(themes.values) },
            onPick = { viewModel.setTheme(note, it); showTheme = false },
            onDismiss = { showTheme = false }
        )
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

/**
 * Partage la note : texte (titre et contenu sans les lignes d'images) et, s'il y en a,
 * les images jointes. La fiche de partage d'Android propose toutes les apps.
 */
private fun shareNote(context: android.content.Context, note: Note, content: String) {
    val text = listOf(displayTitle(note), NoteAttachments.textWithoutImages(content)).filter { it.isNotBlank() }.joinToString("\n\n")
    val uris = NoteAttachments.imageNames(content)
        .map { NoteAttachments.file(context, note.uuid, it) }
        .filter { it.exists() }
        .map { FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", it) }
    val intent = if (uris.isEmpty()) {
        Intent(Intent.ACTION_SEND).apply { type = "text/plain"; putExtra(Intent.EXTRA_TEXT, text) }
    } else {
        val clip = ClipData.newUri(context.contentResolver, "AlphaNote", uris.first())
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "image/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
            putExtra(Intent.EXTRA_TEXT, text)
            this.clipData = clip
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
    context.startActivity(Intent.createChooser(intent, "Partager la note"))
}

@Composable
private fun NoteTitleField(note: Note, onRename: (String) -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalAlphaPalette.current
    var draft by remember(note.id) { mutableStateOf(note.title) }
    var focused by remember { mutableStateOf(false) }
    LaunchedEffect(note.title) { if (!focused) draft = note.title }
    val commit = { if (draft.trim() != note.title) onRename(draft.trim()) }
    val style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium, color = palette.text)
    androidx.compose.foundation.text.BasicTextField(
        value = draft, onValueChange = { draft = it }, singleLine = true, textStyle = style,
        cursorBrush = androidx.compose.ui.graphics.SolidColor(palette.accent),
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(imeAction = androidx.compose.ui.text.input.ImeAction.Done),
        keyboardActions = androidx.compose.foundation.text.KeyboardActions(onDone = { commit() }),
        modifier = modifier.onFocusChanged { state -> if (focused && !state.isFocused) commit(); focused = state.isFocused },
        decorationBox = { inner ->
            if (draft.isEmpty()) Text(displayTitle(note), style = style.copy(color = palette.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
            inner()
        }
    )
}
