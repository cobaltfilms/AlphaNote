package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.PushPin
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ai.NoteMode
import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.ui.components.ModeDot
import be.cobaltfilms.alphanote.ui.components.NoteDates
import be.cobaltfilms.alphanote.ui.editor.EditorDecorations
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette
import kotlinx.coroutines.launch

/**
 * Liste des notes — même structure que le volet macOS : recherche (texte +
 * sémantique), Épinglées / Notes / Archives, titre + date + aperçu.
 */
@Composable
fun NoteListScreen(
    viewModel: NoteViewModel,
    onCreateNote: suspend (String) -> Unit,
    onNoteClick: (Long) -> Unit,
    onSettingsClick: () -> Unit
) {
    val palette = LocalAlphaPalette.current
    val activeNotes by viewModel.activeNotes.collectAsState()
    val archivedNotes by viewModel.archivedNotes.collectAsState()
    val semanticResults by viewModel.semanticResults.collectAsState()
    val settings by viewModel.settings.collectAsState()
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }

    var query by remember { mutableStateOf("") }
    var showArchived by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<Note?>(null) }
    var renaming by remember { mutableStateOf<Note?>(null) }

    LaunchedEffect(Unit) { viewModel.toast.collect { snackbarHostState.showSnackbar(it) } }
    LaunchedEffect(query) { viewModel.semanticSearch(query) }
    LaunchedEffect(Unit) { if (settings.autoCleanup) viewModel.deleteEmptyNotes() }

    val filtered = remember(activeNotes, query, semanticResults) {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) activeNotes else {
            val lower = trimmed.lowercase()
            val textMatches = activeNotes.filter {
                // Note sécurisée : seul son titre est cherchable.
                (if (it.isVault) it.effectiveTitle else it.content).lowercase().contains(lower) || it.title.lowercase().contains(lower)
            }
            val textIDs = textMatches.map { it.uuid }.toSet()
            textMatches + semanticResults.filter { !it.archived && it.uuid !in textIDs }
        }
    }
    val pinned = filtered.filter { it.isPinned }
    val others = filtered.filter { !it.isPinned }

    Scaffold(
        containerColor = palette.sidebar,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { scope.launch { onCreateNote("") } },
                containerColor = palette.accent, contentColor = palette.window
            ) { Icon(Icons.Default.Add, contentDescription = "Nouvelle note") }
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("AlphaNote", color = palette.text, style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold), modifier = Modifier.weight(1f))
                IconButton(onClick = onSettingsClick) { Icon(Icons.Default.Settings, contentDescription = "Réglages", tint = palette.secondary) }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)
                    .background(palette.field, RoundedCornerShape(10.dp)).padding(horizontal = 10.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(Icons.Default.Search, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(16.dp))
                BasicTextField(
                    value = query, onValueChange = { query = it }, singleLine = true,
                    modifier = Modifier.weight(1f),
                    textStyle = TextStyle(color = palette.text, fontSize = 14.sp),
                    cursorBrush = SolidColor(palette.accent),
                    decorationBox = { inner -> if (query.isEmpty()) Text("Rechercher", color = palette.secondary, fontSize = 14.sp); inner() }
                )
                if (query.isNotEmpty()) {
                    IconButton(onClick = { query = "" }, modifier = Modifier.size(20.dp)) {
                        Icon(Icons.Default.Close, contentDescription = "Effacer", tint = palette.secondary, modifier = Modifier.size(14.dp))
                    }
                }
            }

            LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 8.dp, end = 8.dp, bottom = 96.dp)) {
                if (pinned.isNotEmpty()) {
                    item { SectionHeader("Épinglées", pinned = true) }
                    items(pinned, key = { "p${it.id}" }) { note ->
                        NoteRow(note, archived = false, onOpen = { onNoteClick(note.id) },
                            onPin = { viewModel.togglePin(note) }, onRename = { renaming = note }, onDuplicate = { viewModel.duplicate(note) },
                            onArchive = { viewModel.archive(note) }, onDelete = { if (settings.confirmDelete && note.content.isNotBlank()) pendingDelete = note else viewModel.delete(note) })
                    }
                }
                if (others.isNotEmpty()) {
                    if (pinned.isNotEmpty()) item { SectionHeader("Notes", pinned = false) }
                    items(others, key = { "n${it.id}" }) { note ->
                        NoteRow(note, archived = false, onOpen = { onNoteClick(note.id) },
                            onPin = { viewModel.togglePin(note) }, onRename = { renaming = note }, onDuplicate = { viewModel.duplicate(note) },
                            onArchive = { viewModel.archive(note) }, onDelete = { if (settings.confirmDelete && note.content.isNotBlank()) pendingDelete = note else viewModel.delete(note) })
                    }
                }
                if (filtered.isEmpty()) {
                    item {
                        Text(if (query.isEmpty()) "Aucune note. Appuie sur + pour écrire." else "Aucun résultat",
                            color = palette.secondary, fontSize = 14.sp, modifier = Modifier.padding(16.dp))
                    }
                }
                if (archivedNotes.isNotEmpty()) {
                    item {
                        Row(
                            modifier = Modifier.fillMaxWidth().combinedClickableNoRipple { showArchived = !showArchived }.padding(horizontal = 12.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Icon(if (showArchived) Icons.Default.ExpandLess else Icons.Default.ExpandMore, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(16.dp))
                            Text("Archives · ${archivedNotes.size}", color = palette.secondary, style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold))
                        }
                    }
                    if (showArchived) {
                        items(archivedNotes, key = { "a${it.id}" }) { note ->
                            NoteRow(note, archived = true, onOpen = { onNoteClick(note.id) },
                                onPin = { viewModel.togglePin(note) }, onRename = { renaming = note }, onDuplicate = { viewModel.duplicate(note) },
                                onArchive = { viewModel.unarchive(note) }, onDelete = { pendingDelete = note })
                        }
                    }
                }
                item {
                    Divider(color = palette.line, modifier = Modifier.padding(top = 12.dp))
                    Text("${activeNotes.size} note${if (activeNotes.size > 1) "s" else ""}", color = palette.secondary, fontSize = 12.sp,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp).navigationBarsPadding())
                }
            }
        }
    }

    pendingDelete?.let { note ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("Supprimer cette note ?") },
            text = { Text("« ${displayTitle(note)} » sera supprimée. Les notes vides se suppriment sans confirmation.") },
            confirmButton = { TextButton(onClick = { viewModel.delete(note); pendingDelete = null }) { Text("Supprimer", color = palette.timer) } },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("Annuler") } }
        )
    }

    renaming?.let { note -> RenameDialog(note, onDismiss = { renaming = null }, onRename = { viewModel.rename(note, it); renaming = null }) }
}

@Composable
fun RenameDialog(note: Note, onDismiss: () -> Unit, onRename: (String) -> Unit) {
    var draft by remember(note.id) { mutableStateOf(note.title.ifEmpty { displayTitle(note) }) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Renommer la note") },
        text = { OutlinedTextField(value = draft, onValueChange = { draft = it }, singleLine = true, label = { Text("Nom (vide = première ligne)") }) },
        confirmButton = { TextButton(onClick = { onRename(draft) }) { Text("Enregistrer") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Annuler") } }
    )
}

@Composable
private fun SectionHeader(title: String, pinned: Boolean) {
    val palette = LocalAlphaPalette.current
    Row(modifier = Modifier.padding(start = 12.dp, top = 10.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        if (pinned) Icon(Icons.Default.PushPin, contentDescription = null, tint = palette.secondary, modifier = Modifier.size(11.dp))
        Text(title.uppercase(), color = palette.secondary, style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.6.sp))
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NoteRow(
    note: Note, archived: Boolean, onOpen: () -> Unit, onPin: () -> Unit, onRename: () -> Unit,
    onDuplicate: () -> Unit, onArchive: () -> Unit, onDelete: () -> Unit
) {
    val palette = LocalAlphaPalette.current
    var menu by remember { mutableStateOf(false) }
    val mode = NoteMode.fromKeyword(note.keyword)
    Box {
        Row(
            modifier = Modifier.fillMaxWidth()
                .combinedClickable(onClick = onOpen, onLongClick = { menu = true })
                .padding(horizontal = 10.dp, vertical = 9.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top
        ) {
            Box(modifier = Modifier.padding(top = 6.dp)) { ModeDot(mode) }
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(displayTitle(note), color = palette.text, style = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(6.dp))
                    Text(NoteDates.shortDate(note.updatedAt), color = palette.secondary.copy(alpha = 0.85f), fontSize = 12.sp)
                }
                Spacer(Modifier.height(2.dp))
                Text(preview(note), color = palette.secondary, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(if (note.isPinned) "Désépingler" else "Épingler") }, onClick = { menu = false; onPin() })
            DropdownMenuItem(text = { Text("Renommer…") }, onClick = { menu = false; onRename() })
            DropdownMenuItem(text = { Text("Dupliquer") }, onClick = { menu = false; onDuplicate() })
            DropdownMenuItem(text = { Text(if (archived) "Désarchiver" else "Archiver") }, onClick = { menu = false; onArchive() })
            DropdownMenuItem(text = { Text("Supprimer", color = palette.timer) }, onClick = { menu = false; onDelete() })
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
private fun Modifier.combinedClickableNoRipple(onClick: () -> Unit): Modifier = this.combinedClickable(onClick = onClick)

fun displayTitle(note: Note): String {
    val title = note.effectiveTitle.ifEmpty { return "Note sans titre" }
    // En-tête de mode nu (« timer », « math ») : un nom lisible plutôt que le mot-clé.
    if (note.title.isEmpty()) MODE_NAMES[title.lowercase()]?.let { return it }
    return title
}

private val MODE_NAMES = mapOf("math" to "Calcul", "list" to "Liste", "code" to "Code", "timer" to "Minuteur", "vault" to "Note sécurisée")

fun preview(note: Note): String {
    if (note.isVault) return "Note sécurisée"
    var lines = note.content.split("\n")
    if (lines.isNotEmpty() && EditorDecorations.isModeHeader(lines.first().trim())) lines = lines.drop(1)
    if (note.title.isEmpty() && lines.isNotEmpty() && lines.first().trim() == note.effectiveTitle) lines = lines.drop(1)
    val text = lines.joinToString(" ").trim().replace(Regex("\\s+"), " ")
    return text.ifEmpty { "Vide" }
}
