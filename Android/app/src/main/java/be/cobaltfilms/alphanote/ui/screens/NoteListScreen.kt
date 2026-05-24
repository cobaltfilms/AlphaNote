package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Archive
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Unarchive
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.rememberScrollState
import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.ui.theme.AlphaSpacing
import be.cobaltfilms.alphanote.ui.theme.Blue20
import be.cobaltfilms.alphanote.ui.theme.Blue30
import be.cobaltfilms.alphanote.ui.theme.Blue40
import be.cobaltfilms.alphanote.ui.theme.Blue90
import be.cobaltfilms.alphanote.ui.theme.CodeColor
import be.cobaltfilms.alphanote.ui.theme.ListColor
import be.cobaltfilms.alphanote.ui.theme.MathColor
import be.cobaltfilms.alphanote.ui.theme.TimerColor
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private data class CreateTemplate(
    val label: String,
    val initialContent: String,
    val color: Color
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteListScreen(
    viewModel: NoteViewModel,
    onCreateNote: suspend (String) -> Unit,
    onNoteClick: (Long) -> Unit,
    onSettingsClick: () -> Unit
) {
    val activeNotes by viewModel.activeNotes.collectAsState()
    val archivedNotes by viewModel.archivedNotes.collectAsState()
    val confirmDelete by viewModel.confirmDelete.collectAsState()
    val dateFormat = rememberDateFormat()
    val scope = rememberCoroutineScope()
    val createTemplates = remember {
        listOf(
            CreateTemplate("Note", "", Blue40),
            CreateTemplate("Liste", "list\n", ListColor),
            CreateTemplate("Math", "math\n", MathColor),
            CreateTemplate("Code", "code\n", CodeColor),
            CreateTemplate("Timer", "timer\n", TimerColor)
        )
    }

    var pendingDeleteNote by remember { mutableStateOf<Note?>(null) }

    fun createNote(initialContent: String) {
        scope.launch { onCreateNote(initialContent) }
    }

    Scaffold(
        topBar = {
            AlphaTopHero(
                activeCount = activeNotes.size,
                onSettingsClick = onSettingsClick
            )
        },
        floatingActionButton = {
            CreateFabActions(
                templates = createTemplates,
                onCreateDefault = { createNote("") },
                onCreateTemplate = { template -> createNote(template.initialContent) }
            )
        }
    ) { padding ->
        if (activeNotes.isEmpty() && archivedNotes.isEmpty()) {
            EmptyState(
                modifier = Modifier.padding(padding),
                templates = createTemplates,
                onCreateTemplate = { template -> createNote(template.initialContent) }
            )
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(
                    horizontal = AlphaSpacing.screenHorizontal,
                    vertical = AlphaSpacing.sectionVertical
                ),
                verticalArrangement = Arrangement.spacedBy(AlphaSpacing.itemGap)
            ) {
                item {
                    QuickCreateRow(
                        templates = createTemplates,
                        onCreateTemplate = { template -> createNote(template.initialContent) }
                    )
                }

                if (activeNotes.isNotEmpty()) {
                    item {
                        Text(
                            "Actives",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }

                items(activeNotes, key = { it.id }) { note ->
                    NoteListCard(
                        note = note,
                        dateFormat = dateFormat,
                        archived = false,
                        onOpen = { onNoteClick(note.id) },
                        onArchiveToggle = { viewModel.archiveNote(note) },
                        onDelete = {
                            if (confirmDelete) {
                                pendingDeleteNote = note
                            } else {
                                viewModel.deleteNote(note)
                            }
                        }
                    )
                }

                if (archivedNotes.isNotEmpty()) {
                    item {
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            "Archives",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    items(archivedNotes, key = { it.id }) { note ->
                        NoteListCard(
                            note = note,
                            dateFormat = dateFormat,
                            archived = true,
                            onOpen = { onNoteClick(note.id) },
                            onArchiveToggle = { viewModel.unarchiveNote(note) },
                            onDelete = {
                                if (confirmDelete) {
                                    pendingDeleteNote = note
                                } else {
                                    viewModel.deleteNote(note)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    pendingDeleteNote?.let { note ->
        AlertDialog(
            onDismissRequest = { pendingDeleteNote = null },
            title = { Text("Supprimer la note") },
            text = {
                Text(
                    "Cette note sera placée dans la suppression logicielle. " +
                        "Tu pourras toujours restaurer via synchronisation/backup si nécessaire."
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.deleteNote(note)
                    pendingDeleteNote = null
                }) {
                    Text("Supprimer")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeleteNote = null }) {
                    Text("Annuler")
                }
            }
        )
    }
}

@Composable
private fun EmptyState(
    templates: List<CreateTemplate>,
    onCreateTemplate: (CreateTemplate) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = AlphaSpacing.screenHorizontal),
        verticalArrangement = Arrangement.Top,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(20.dp))
        ElevatedCard(
            elevation = CardDefaults.elevatedCardElevation(defaultElevation = 3.dp)
        ) {
            Column(
                modifier = Modifier.padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text("Bienvenue", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Capture rapidement tes idées, puis structure-les en mode math, list, code ou timer.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(modifier = Modifier.height(8.dp))
                QuickCreateRow(
                    templates = templates,
                    onCreateTemplate = onCreateTemplate
                )
            }
        }
    }
}

@Composable
private fun AlphaTopHero(
    activeCount: Int,
    onSettingsClick: () -> Unit
) {
    val containerShape: Shape = RoundedCornerShape(bottomStart = 26.dp, bottomEnd = 26.dp)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(containerShape)
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(Blue40, Blue30, Blue20)
                )
            )
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 28.dp, y = (-22).dp)
                .size(120.dp)
                .clip(CircleShape)
                .background(Blue90.copy(alpha = 0.22f))
        )
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .offset(x = 8.dp, y = 42.dp)
                .size(56.dp)
                .clip(CircleShape)
                .background(Blue90.copy(alpha = 0.18f))
        )

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(start = AlphaSpacing.screenHorizontal, end = 10.dp, top = 10.dp, bottom = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "AlphaNote",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onPrimary
                )
                Text(
                    text = "$activeCount note${if (activeCount > 1) "s" else ""} actives",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.82f)
                )
            }

            IconButton(onClick = onSettingsClick) {
                Icon(
                    Icons.Default.Settings,
                    contentDescription = "Paramètres",
                    tint = MaterialTheme.colorScheme.onPrimary
                )
            }
        }
    }
}

@Composable
private fun CreateFabActions(
    templates: List<CreateTemplate>,
    onCreateDefault: () -> Unit,
    onCreateTemplate: (CreateTemplate) -> Unit
) {
    var menuExpanded by remember { mutableStateOf(false) }

    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        ExtendedFloatingActionButton(
            onClick = onCreateDefault,
            icon = { Icon(Icons.Default.Add, contentDescription = null) },
            text = { Text("Nouvelle note") },
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary
        )

        Box {
            FloatingActionButton(
                onClick = { menuExpanded = true },
                containerColor = MaterialTheme.colorScheme.secondaryContainer,
                contentColor = MaterialTheme.colorScheme.onSecondaryContainer
            ) {
                Icon(Icons.Default.MoreVert, contentDescription = "Choisir un type de note")
            }

            DropdownMenu(
                expanded = menuExpanded,
                onDismissRequest = { menuExpanded = false }
            ) {
                templates.forEach { template ->
                    DropdownMenuItem(
                        text = { Text("Nouveau ${template.label.lowercase()}") },
                        onClick = {
                            menuExpanded = false
                            onCreateTemplate(template)
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun QuickCreateRow(
    templates: List<CreateTemplate>,
    onCreateTemplate: (CreateTemplate) -> Unit
) {
    val scroll = rememberScrollState()

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = "Créer rapidement",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(scroll),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            templates.forEach { template ->
                SuggestionChip(
                    onClick = { onCreateTemplate(template) },
                    label = { Text("Nouveau ${template.label.lowercase()}") },
                    colors = SuggestionChipDefaults.suggestionChipColors(
                        containerColor = template.color.copy(alpha = 0.14f),
                        labelColor = template.color
                    )
                )
            }
        }
    }
}

@Composable
private fun NoteListCard(
    note: Note,
    dateFormat: SimpleDateFormat,
    archived: Boolean,
    onOpen: () -> Unit,
    onArchiveToggle: () -> Unit,
    onDelete: () -> Unit
) {
    val keywordColor = keywordToColor(note.keyword)
    val preview = note.content.lines()
        .drop(if (note.keyword.isNotEmpty()) 1 else 0)
        .firstOrNull { it.trim().isNotEmpty() }
        ?.trim()
        .orEmpty()

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onOpen),
        colors = CardDefaults.cardColors(
            containerColor = if (archived) {
                MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f)
            } else {
                MaterialTheme.colorScheme.surface
            }
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = if (archived) 0.dp else 2.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(14.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                modifier = Modifier
                    .padding(top = 2.dp)
                    .width(4.dp)
                    .height(44.dp)
                    .background(
                        color = if (note.keyword.isBlank()) {
                            MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
                        } else {
                            keywordColor
                        },
                        shape = MaterialTheme.shapes.small
                    )
            )

            Spacer(modifier = Modifier.width(12.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = note.effectiveTitle.ifEmpty { "Sans titre" },
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                if (preview.isNotBlank()) {
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = preview,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = dateFormat.format(Date(note.updatedAt)),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    if (note.keyword.isNotBlank()) {
                        Spacer(modifier = Modifier.width(8.dp))
                        SuggestionChip(
                            onClick = {},
                            label = { Text(note.keyword.uppercase(), style = MaterialTheme.typography.labelSmall) },
                            colors = SuggestionChipDefaults.suggestionChipColors(
                                containerColor = keywordColor.copy(alpha = 0.14f),
                                labelColor = keywordColor
                            )
                        )
                    }
                }
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                IconButton(onClick = onArchiveToggle) {
                    Icon(
                        imageVector = if (archived) Icons.Default.Unarchive else Icons.Default.Archive,
                        contentDescription = if (archived) "Désarchiver" else "Archiver",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = "Supprimer",
                        tint = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
    }
}

fun keywordToColor(keyword: String): Color {
    return when (keyword.lowercase()) {
        "math" -> MathColor
        "list" -> ListColor
        "code" -> CodeColor
        "timer" -> TimerColor
        else -> Blue40
    }
}

@Composable
private fun rememberDateFormat(): SimpleDateFormat {
    return remember {
        SimpleDateFormat("dd MMM yyyy, HH:mm", Locale.getDefault())
    }
}
