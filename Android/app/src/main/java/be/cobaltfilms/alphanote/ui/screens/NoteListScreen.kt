package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import be.cobaltfilms.alphanote.model.Note
import be.cobaltfilms.alphanote.ui.theme.*
import java.text.SimpleDateFormat
import java.util.*

/**
 * Écran de liste des notes.
 * Portage de UI/NoteListView.swift (macOS).
 *
 * Affiche les notes dans une LazyColumn avec swipe-to-dismiss.
 * FAB pour créer une nouvelle note.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteListScreen(
    viewModel: NoteViewModel,
    onCreateNote: (String) -> Unit,
    onNoteClick: (Long) -> Unit,
    onSettingsClick: () -> Unit
) {
    val notes by viewModel.activeNotes.collectAsState()
    val dateFormat = rememberDateFormat()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("AlphaNote") },
                actions = {
                    IconButton(onClick = onSettingsClick) {
                        Icon(Icons.Default.Settings, contentDescription = "Paramètres")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    titleContentColor = MaterialTheme.colorScheme.onPrimary,
                    actionIconContentColor = MaterialTheme.colorScheme.onPrimary
                )
            )
        },
        floatingActionButton = {
            FloatingActionButton(
                onClick = { onCreateNote("") },
                containerColor = MaterialTheme.colorScheme.primary
            ) {
                Icon(Icons.Default.Add, contentDescription = "Nouvelle note")
            }
        }
    ) { padding ->
        if (notes.isEmpty()) {
            // État vide
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "Aucune note",
                        style = MaterialTheme.typography.headlineMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "Appuyez sur + pour créer votre première note",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentPadding = PaddingValues(vertical = 8.dp)
            ) {
                items(notes, key = { it.id }) { note ->
                    NoteListItem(
                        note = note,
                        dateFormat = dateFormat,
                        onClick = { onNoteClick(note.id) },
                        onDelete = { viewModel.deleteNote(note) }
                    )
                }
            }
        }
    }
}

@Composable
private fun NoteListItem(
    note: Note,
    dateFormat: SimpleDateFormat,
    onClick: () -> Unit,
    onDelete: () -> Unit
) {
    val keywordColor = keywordToColor(note.keyword)

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .clickable(onClick = onClick),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.Top
        ) {
            // Indicateur de mot-clé coloré
            if (note.keyword.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .width(4.dp)
                        .height(40.dp)
                        .padding(end = 8.dp)
                ) {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = keywordColor,
                        shape = MaterialTheme.shapes.small
                    ) {}
                }
                Spacer(modifier = Modifier.width(12.dp))
            }

            Column(modifier = Modifier.weight(1f)) {
                // Titre
                Text(
                    text = note.effectiveTitle.ifEmpty { "Sans titre" },
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                Spacer(modifier = Modifier.height(4.dp))

                // Extrait du contenu
                val preview = note.content.lines()
                    .drop(if (note.keyword.isNotEmpty()) 1 else 0)
                    .firstOrNull { it.trim().isNotEmpty() }?.trim() ?: ""
                if (preview.isNotEmpty()) {
                    Text(
                        text = preview,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))

                // Date + badge keyword
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = dateFormat.format(Date(note.updatedAt)),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (note.keyword.isNotEmpty()) {
                        Spacer(modifier = Modifier.width(8.dp))
                        SuggestionChip(
                            onClick = {},
                            label = {
                                Text(
                                    note.keyword.uppercase(),
                                    style = MaterialTheme.typography.labelSmall
                                )
                            },
                            colors = SuggestionChipDefaults.suggestionChipColors(
                                containerColor = keywordColor.copy(alpha = 0.15f),
                                labelColor = keywordColor
                            )
                        )
                    }
                }
            }

            // Bouton supprimer
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "Supprimer",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                )
            }
        }
    }
}

/**
 * Retourne la couleur associée à un mot-clé.
 */
fun keywordToColor(keyword: String): androidx.compose.ui.graphics.Color {
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
    return androidx.compose.runtime.remember {
        SimpleDateFormat("dd MMM yyyy, HH:mm", Locale.FRENCH)
    }
}
