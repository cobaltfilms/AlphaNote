package be.cobaltfilms.alphanote.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import be.cobaltfilms.alphanote.data.ThemeMode

private val AlphaNoteShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp)
)

@Composable
fun AlphaNoteTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    colorTheme: ColorTheme = ColorTheme.OR,
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val palette = alphaPalette(colorTheme, darkTheme)

    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = palette.accent, onPrimary = palette.window,
            primaryContainer = palette.selection, onPrimaryContainer = palette.text,
            secondary = palette.accent2, onSecondary = palette.window,
            secondaryContainer = palette.selection, onSecondaryContainer = palette.text,
            background = palette.content, onBackground = palette.text,
            surface = palette.content, onSurface = palette.text,
            surfaceVariant = palette.sidebar, onSurfaceVariant = palette.secondary,
            outline = palette.line, outlineVariant = palette.line,
            error = palette.timer
        )
    } else {
        lightColorScheme(
            primary = palette.accent, onPrimary = palette.content,
            primaryContainer = palette.selection, onPrimaryContainer = palette.text,
            secondary = palette.accent2, onSecondary = palette.content,
            secondaryContainer = palette.selection, onSecondaryContainer = palette.text,
            background = palette.content, onBackground = palette.text,
            surface = palette.content, onSurface = palette.text,
            surfaceVariant = palette.sidebar, onSurfaceVariant = palette.secondary,
            outline = palette.line, outlineVariant = palette.line,
            error = palette.timer
        )
    }

    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            @Suppress("DEPRECATION")
            window.statusBarColor = palette.window.toArgb()
            @Suppress("DEPRECATION")
            window.navigationBarColor = palette.content.toArgb()
            val controller = WindowCompat.getInsetsController(window, view)
            controller.isAppearanceLightStatusBars = !darkTheme
            controller.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    CompositionLocalProvider(LocalAlphaPalette provides palette) {
        MaterialTheme(colorScheme = colorScheme, typography = AlphaNoteTypography, shapes = AlphaNoteShapes, content = content)
    }
}
