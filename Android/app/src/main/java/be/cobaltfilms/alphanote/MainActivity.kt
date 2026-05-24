package be.cobaltfilms.alphanote

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import be.cobaltfilms.alphanote.ui.screens.AlphaNoteNavHost
import be.cobaltfilms.alphanote.ui.screens.SharedTextEvent
import be.cobaltfilms.alphanote.ui.theme.AlphaNoteTheme

/**
 * Activité principale — Single Activity architecture.
 * Portage de AlphaNoteApp.swift et NoteWindowController.swift (macOS).
 */
class MainActivity : ComponentActivity() {

    private var sharedTextEvent: SharedTextEvent? by mutableStateOf(null)
    private var sharedEventId = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        consumeIncomingShareIntent(intent)

        setContent {
            AlphaNoteTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    AlphaNoteNavHost(
                        modifier = Modifier.padding(innerPadding),
                        sharedTextEvent = sharedTextEvent,
                        onSharedTextConsumed = { consumedId ->
                            if (sharedTextEvent?.id == consumedId) {
                                sharedTextEvent = null
                            }
                        }
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        consumeIncomingShareIntent(intent)
    }

    private fun consumeIncomingShareIntent(incoming: Intent?) {
        val text = extractSharedText(incoming) ?: return
        sharedEventId += 1
        sharedTextEvent = SharedTextEvent(id = sharedEventId, text = text)
    }

    private fun extractSharedText(incoming: Intent?): String? {
        if (incoming?.action != Intent.ACTION_SEND) return null
        if (incoming.type != "text/plain") return null
        return incoming.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
    }
}
