package be.cobaltfilms.alphanote.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/** Schéma de couleurs clair */
private val LightColorScheme = lightColorScheme(
    primary = Blue40,
    onPrimary = WarmGray95,
    primaryContainer = Blue90,
    onPrimaryContainer = Blue10,
    secondary = Blue30,
    surface = WarmGray95,
    onSurface = WarmGray10,
    surfaceVariant = WarmGray90,
    error = ErrorRed
)

/** Schéma de couleurs sombre */
private val DarkColorScheme = darkColorScheme(
    primary = Blue80,
    onPrimary = Blue20,
    primaryContainer = Blue30,
    onPrimaryContainer = Blue90,
    secondary = Blue80,
    surface = WarmGray10,
    onSurface = WarmGray95,
    surfaceVariant = WarmGray20,
    error = ErrorRed
)

/**
 * Thème principal AlphaNote.
 * Applique Material 3 avec les couleurs de la marque.
 */
@Composable
fun AlphaNoteTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    // Colorer la barre de statut
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = colorScheme.primary.toArgb()
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AlphaNoteTypography,
        content = content
    )
}
