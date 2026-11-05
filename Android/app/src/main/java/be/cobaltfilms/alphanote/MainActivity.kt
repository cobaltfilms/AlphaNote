package be.cobaltfilms.alphanote

import android.content.Intent
import android.os.Bundle
import androidx.fragment.app.FragmentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import be.cobaltfilms.alphanote.data.AppSettings
import be.cobaltfilms.alphanote.data.AppSettingsRepository
import be.cobaltfilms.alphanote.timer.TimerAlarms
import be.cobaltfilms.alphanote.timer.TimerRegistry
import be.cobaltfilms.alphanote.ui.screens.AlphaNoteNavHost
import be.cobaltfilms.alphanote.ui.screens.SharedTextEvent
import be.cobaltfilms.alphanote.ui.theme.AlphaNoteTheme

/** Activité unique. Le thème suit le réglage (Système / Clair / Sombre). */
class MainActivity : FragmentActivity() {

    private var sharedTextEvent: SharedTextEvent? by mutableStateOf(null)
    private var sharedEventId = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        consumeIncomingShareIntent(intent)

        setContent {
            val settingsRepository = remember { AppSettingsRepository(this) }
            val settings by settingsRepository.settings.collectAsState(initial = AppSettings())
            AlphaNoteTheme(themeMode = settings.theme, colorTheme = settings.colorTheme) {
                AlphaNoteNavHost(
                    sharedTextEvent = sharedTextEvent,
                    onSharedTextConsumed = { consumedId -> if (sharedTextEvent?.id == consumedId) sharedTextEvent = null }
                )
            }
        }
    }

    override fun onStart() {
        super.onStart()
        TimerRegistry.shared.appVisible = true
        TimerAlarms.cancelAllNotifications(this)
    }

    override fun onStop() {
        TimerRegistry.shared.appVisible = false
        super.onStop()
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
        if (incoming?.action != Intent.ACTION_SEND || incoming.type != "text/plain") return null
        return incoming.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
    }
}
