package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument

/**
 * Navigation principale AlphaNote.
 * Routes :
 * - "notes" : liste des notes
 * - "note/{noteId}" : édition d'une note
 * - "note/new" : création d'une nouvelle note
 * - "settings" : paramètres
 */
@Composable
fun AlphaNoteNavHost(
    modifier: Modifier = Modifier,
    navController: NavHostController = rememberNavController(),
    initialSharedText: String? = null,
    noteViewModel: NoteViewModel = viewModel()
) {
    NavHost(
        navController = navController,
        startDestination = "notes",
        modifier = modifier
    ) {
        composable("notes") {
            NoteListScreen(
                viewModel = noteViewModel,
                onCreateNote = { text ->
                    noteViewModel.createNote(text)
                    val noteId = noteViewModel.activeNotes.value.firstOrNull()?.id ?: return@NoteListScreen
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
                onBack = { navController.popBackStack() }
            )
        }
    }
}
