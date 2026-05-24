package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument

/**
 * Evénement de partage texte injecté depuis Activity.
 */
data class SharedTextEvent(
    val id: Long,
    val text: String
)

/**
 * Navigation principale AlphaNote.
 */
@Composable
fun AlphaNoteNavHost(
    modifier: Modifier = Modifier,
    navController: NavHostController = rememberNavController(),
    sharedTextEvent: SharedTextEvent? = null,
    onSharedTextConsumed: (Long) -> Unit = {},
    noteViewModel: NoteViewModel = viewModel()
) {
    LaunchedEffect(sharedTextEvent?.id) {
        val payload = sharedTextEvent ?: return@LaunchedEffect
        val noteId = noteViewModel.createNoteAndGetId(content = payload.text)
        navController.navigate("note/$noteId")
        onSharedTextConsumed(payload.id)
    }

    NavHost(
        navController = navController,
        startDestination = "notes",
        modifier = modifier
    ) {
        composable("notes") {
            NoteListScreen(
                viewModel = noteViewModel,
                onCreateNote = { text ->
                    val noteId = noteViewModel.createNoteAndGetId(content = text)
                    navController.navigate("note/$noteId")
                },
                onNoteClick = { noteId ->
                    navController.navigate("note/$noteId")
                },
                onSettingsClick = {
                    navController.navigate("settings")
                }
            )
        }

        composable(
            "note/{noteId}",
            arguments = listOf(navArgument("noteId") { type = NavType.LongType })
        ) { backStackEntry ->
            val noteId = backStackEntry.arguments?.getLong("noteId") ?: return@composable

            NoteEditScreen(
                noteId = noteId,
                viewModel = noteViewModel,
                onBack = { navController.popBackStack() }
            )
        }

        composable("settings") {
            SettingsScreen(
                viewModel = noteViewModel,
                onBack = { navController.popBackStack() }
            )
        }
    }
}
