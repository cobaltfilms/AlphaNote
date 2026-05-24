package be.cobaltfilms.alphanote.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import be.cobaltfilms.alphanote.ui.components.AIAssistantBar
import be.cobaltfilms.alphanote.ui.theme.AlphaSpacing
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NoteEditScreen(
    noteId: Long,
    viewModel: NoteViewModel,
    onBack: () -> Unit
) {
    val currentNote by viewModel.currentNote.collectAsState()
    val mathResults by viewModel.mathResult.collectAsState()
    val mathVariables by viewModel.mathVariables.collectAsState()
    val scope = rememberCoroutineScope()

    var editorValue by remember { mutableStateOf(TextFieldValue("")) }
    var loadedNoteId by remember { mutableLongStateOf(-1L) }
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(noteId) {
        loadedNoteId = -1L
        viewModel.loadNote(noteId)
    }

    LaunchedEffect(currentNote?.id, currentNote?.updatedAt) {
        val note = currentNote ?: return@LaunchedEffect
        if (loadedNoteId != note.id) {
            editorValue = TextFieldValue(note.content, TextRange(note.content.length))
            viewModel.updateNoteContent(note.content)
            loadedNoteId = note.id
        }
    }

    val keyword = currentNote?.keyword.orEmpty()

    LaunchedEffect(keyword, editorValue.text) {
        if (keyword.lowercase() == "math") {
            viewModel.evaluateMathLines(editorValue.text)
        }
    }

    fun processInput(newValue: TextFieldValue) {
        val previousText = editorValue.text
        var processed = newValue

        // Android UX: taper "math " en première ligne passe automatiquement à la ligne suivante.
        val firstLine = newValue.text.lineSequence().firstOrNull()?.trim().orEmpty()
        if (keyword.lowercase() != "math" &&
            newValue.text.lines().size == 1 &&
            firstLine == "math" &&
            newValue.text.endsWith(" ")
        ) {
            val forced = "math\n"
            processed = TextFieldValue(forced, TextRange(forced.length))
        }

        // En mode math, '=' calcule sur la ligne en cours ; espace après '=' valide et passe à la ligne.
        val currentMode = currentNote?.keyword.orEmpty().lowercase()
        if (currentMode == "math") {
            val transform = viewModel.applyMathInputTransform(
                previousContent = previousText,
                newContent = processed.text,
                cursorPosition = processed.selection.end
            )
            if (transform.transformed) {
                processed = TextFieldValue(transform.content, TextRange(transform.cursorPosition))
            }
        }

        editorValue = processed
        viewModel.updateNoteContent(processed.text)
    }

    val persistAndBack: () -> Unit = {
        scope.launch {
            viewModel.saveCurrentText(editorValue.text)
            onBack()
        }
    }

    BackHandler { persistAndBack() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = currentNote?.effectiveTitle?.ifEmpty { "Nouvelle note" } ?: "Nouvelle note",
                        style = MaterialTheme.typography.titleLarge
                    )
                },
                navigationIcon = {
                    IconButton(onClick = persistAndBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Retour")
                    }
                },
                actions = {
                    if (keyword.isNotBlank()) {
                        BadgeKeyword(keyword = keyword)
                    }
                }
            )
        },
        bottomBar = {
            AIAssistantBar(
                noteContent = editorValue.text,
                onUpdateContent = { updatedText ->
                    editorValue = TextFieldValue(updatedText, TextRange(updatedText.length))
                    viewModel.updateNoteContent(updatedText)
                },
                evaluator = viewModel.mathEvaluator
            )
        }
    ) { padding ->
        when (keyword.lowercase()) {
            "math" -> MathNoteScreen(
                value = editorValue,
                onValueChange = { processInput(it) },
                mathResults = mathResults,
                mathVariables = mathVariables,
                focusRequester = focusRequester,
                modifier = Modifier.padding(padding)
            )

            "list" -> ListNoteScreen(
                value = editorValue,
                onValueChange = { processInput(it) },
                focusRequester = focusRequester,
                modifier = Modifier.padding(padding)
            )

            "code" -> CodeNoteScreen(
                value = editorValue,
                onValueChange = { processInput(it) },
                focusRequester = focusRequester,
                modifier = Modifier.padding(padding)
            )

            "timer" -> TimerNoteScreen(
                value = editorValue,
                onValueChange = { processInput(it) },
                focusRequester = focusRequester,
                modifier = Modifier.padding(padding)
            )

            else -> PlainNoteScreen(
                value = editorValue,
                onValueChange = { processInput(it) },
                focusRequester = focusRequester,
                modifier = Modifier.padding(padding)
            )
        }
    }
}

@Composable
fun PlainNoteScreen(
    value: TextFieldValue,
    onValueChange: (TextFieldValue) -> Unit,
    focusRequester: FocusRequester = remember { FocusRequester() },
    modifier: Modifier = Modifier
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = AlphaSpacing.screenHorizontal, vertical = 14.dp)
            .focusRequester(focusRequester),
        textStyle = TextStyle(
            fontSize = 17.sp,
            lineHeight = 25.sp,
            color = MaterialTheme.colorScheme.onSurface
        ),
        decorationBox = { innerTextField ->
            Box {
                if (value.text.isEmpty()) {
                    Text(
                        "Commencez à écrire…\n\nAstuce: utilisez `math`, `list`, `code` ou `timer` en première ligne.",
                        style = TextStyle(
                            fontSize = 17.sp,
                            lineHeight = 25.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                        )
                    )
                }
                innerTextField()
            }
        }
    )

    LaunchedEffect(Unit) { focusRequester.requestFocus() }
}

@Composable
fun BadgeKeyword(keyword: String) {
    val color = keywordToColor(keyword)
    SuggestionChip(
        onClick = {},
        label = { Text(keyword.uppercase(), style = MaterialTheme.typography.labelSmall) },
        colors = SuggestionChipDefaults.suggestionChipColors(
            containerColor = color.copy(alpha = 0.14f),
            labelColor = color
        )
    )
    Spacer(modifier = Modifier.width(8.dp))
}
