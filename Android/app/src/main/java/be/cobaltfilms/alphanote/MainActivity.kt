package be.cobaltfilms.alphanote

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.ui.Modifier
import be.cobaltfilms.alphanote.ui.screens.AlphaNoteNavHost
import be.cobaltfilms.alphanote.ui.theme.AlphaNoteTheme

/**
 * Activité principale — Single Activity architecture.
 * Portage de AlphaNoteApp.swift et NoteWindowController.swift (macOS).
 *
 * Gère la navigation, le thème, et le cycle de vie.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Traiter le texte partagé depuis d'autres apps (intent ACTION_SEND)
        val sharedText = handleSharedIntent()

        setContent {
            AlphaNoteTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    AlphaNoteNavHost(
                        modifier = Modifier.padding(innerPadding),
                        initialSharedText = sharedText
                    )
                }
            }
        }
    }

    /**
     * Gère les intents de partage (ACTION_SEND).
     * @return le texte partagé, ou null si aucune intent de partage.
     */
    private fun handleSharedIntent(): String? {
        if (intent?.action != android.content.Intent.ACTION_SEND) return null
        if (intent.type != "text/plain") return null
        return intent.getStringExtra(android.content.Intent.EXTRA_TEXT)
    }
}
