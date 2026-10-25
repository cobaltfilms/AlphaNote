package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument

/** Événement de partage texte injecté depuis l'Activity. */
data class SharedTextEvent(val id: Long, val text: String)

@Composable
fun AlphaNoteNavHost(
    modifier: Modifier = Modifier,
    navController: NavHostController = rememberNavController(),
    sharedTextEvent: SharedTextEvent? = null,
    onSharedTextConsumed: (Long) -> Unit = {},
    noteViewModel: NoteViewModel = viewModel()
) {
    // Retour au premier plan : synchro de rattrapage (le système coupe le
    // réseau des apps en arrière-plan, la synchro périodique n'y tourne pas).
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START) noteViewModel.onAppForeground()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(sharedTextEvent?.id) {
        val payload = sharedTextEvent ?: return@LaunchedEffect
        val noteId = noteViewModel.createNoteAndGetId(content = payload.text)
        navController.navigate("note/$noteId")
        onSharedTextConsumed(payload.id)
    }

    NavHost(navController = navController, startDestination = "notes", modifier = modifier) {
        composable("notes") {
            NoteListScreen(
                viewModel = noteViewModel,
                onCreateNote = { text -> navController.navigate("note/${noteViewModel.createNoteAndGetId(content = text)}") },
                onNoteClick = { noteId -> navController.navigate("note/$noteId") },
                onSettingsClick = { navController.navigate("settings") }
            )
        }
        composable("note/{noteId}", arguments = listOf(navArgument("noteId") { type = NavType.LongType })) { backStackEntry ->
            val noteId = backStackEntry.arguments?.getLong("noteId") ?: return@composable
            NoteEditScreen(noteId = noteId, viewModel = noteViewModel, onBack = { navController.popBackStack() })
        }
        composable("settings") {
            SettingsScreen(viewModel = noteViewModel, onBack = { navController.popBackStack() })
        }
    }
}
