package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.components.AIAssistantBar

/**
 * Écran d'édition de note — dispatch vers le mode approprié.
 * Portage de UI/NoteViews/PlainNoteView.swift + NoteWindowController.swift (macOS).
 *
 * Détecte le keyword à partir de la première ligne et affiche le bon mode.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteEditScreen(
    noteId: Long,
    viewModel: NoteViewModel,
    onBack: () -> Unit
) {
    val currentNote by viewModel.currentNote.collectAsState()
    var text by remember { mutableStateOf("") }
    var isNew by remember { mutableStateOf(true) }
    val focusRequester = remember { FocusRequester() }

    // Charger la note
    LaunchedEffect(noteId) {
        viewModel.loadNote(noteId)
    }

    // Synchroniser le contenu
    LaunchedEffect(currentNote) {
        currentNote?.let { note ->
            if (isNew) {
                text = note.content
                isNew = false
            }
        }
    }

    val keyword = currentNote?.keyword ?: ""
    val note = currentNote

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        note?.effectiveTitle?.ifEmpty { "Nouvelle note" } ?: "Nouvelle note"
                    )
                },
                navigationIcon = {
                    IconButton(onClick = {
                        viewModel.updateNoteContent(text)
                        viewModel.saveNote()
                        onBack()
                    }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Retour")
                    }
                },
                actions = {
                    if (keyword.isNotEmpty()) {
                        BadgeKeyword(keyword = keyword)
                    }
                }
            )
        },
        bottomBar = {
            AIAssistantBar(
                noteContent = text,
                onUpdateContent = { newText ->
                    text = newText
                    viewModel.updateNoteContent(newText)
                },
                evaluator = viewModel.mathEvaluator
            )
        }
    ) { padding ->
        // Router vers le bon écran de mode
        when (keyword.lowercase()) {
            "math" -> MathNoteScreen(
                text = text,
                onTextChange = { newText ->
                    text = newText
                    viewModel.updateNoteContent(newText)
                    viewModel.evaluateMathLines(newText)
                },
                mathResults = viewModel.mathResult.collectAsState().value,
                modifier = Modifier.padding(padding)
            )
            "list" -> ListNoteScreen(
                text = text,
                onTextChange = { newText ->
                    text = newText
                    viewModel.updateNoteContent(newText)
                },
                modifier = Modifier.padding(padding)
            )
            "code" -> CodeNoteScreen(
                text = text,
                onTextChange = { newText ->
                    text = newText
                    viewModel.updateNoteContent(newText)
                },
                modifier = Modifier.padding(padding)
            )
            "timer" -> TimerNoteScreen(
                text = text,
                onTextChange = { newText ->
                    text = newText
                    viewModel.updateNoteContent(newText)
                },
                modifier = Modifier.padding(padding)
            )
            else -> PlainNoteScreen(
                text = text,
                onTextChange = { newText ->
                    text = newText
                    viewModel.updateNoteContent(newText)
                },
                focusRequester = focusRequester,
                modifier = Modifier.padding(padding)
            )
        }
    }
}

/**
 * Écran de note simple (mode par défaut).
 * BasicTextField multiligne, plein écran.
 */
@Composable
fun PlainNoteScreen(
    text: String,
    onTextChange: (String) -> Unit,
    focusRequester: FocusRequester = remember { FocusRequester() },
    modifier: Modifier = Modifier
) {
    BasicTextField(
        value = text,
        onValueChange = onTextChange,
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp)
            .focusRequester(focusRequester),
        textStyle = TextStyle(
            fontSize = 16.sp,
            lineHeight = 24.sp,
            color = MaterialTheme.colorScheme.onSurface
        ),
        decorationBox = { innerTextField ->
            Box {
                if (text.isEmpty()) {
                    Text(
                        "Commencez à écrire...\n\nAstuce : tapez math, list, code ou timer\nen première ligne pour activer un mode.",
                        style = TextStyle(
                            fontSize = 16.sp,
                            lineHeight = 24.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                        )
                    )
                }
                innerTextField()
            }
        }
    )

    // Focus auto
    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
    }
}

/**
 * Badge coloré affichant le mot-clé dans la top bar.
 */
@Composable
fun BadgeKeyword(keyword: String) {
    val color = keywordToColor(keyword)
    SuggestionChip(
        onClick = {},
        label = { Text(keyword.uppercase(), style = MaterialTheme.typography.labelSmall) },
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = color.copy(alpha = 0.15f),
            labelColor = color
        )
    )
    Spacer(modifier = Modifier.width(8.dp))
}
