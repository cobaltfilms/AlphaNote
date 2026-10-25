package be.cobaltfilms.alphanote.services

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import be.cobaltfilms.alphanote.ui.theme.ColorTheme

/**
 * Icône de lancement assortie au thème de couleur : une <activity-alias> par
 * thème dans le manifeste (.Launcher<Thème>), une seule active à la fois.
 * Certains lanceurs retirent le raccourci de l'écran d'accueil au changement.
 */
object LauncherIcons {
    fun aliasName(theme: ColorTheme): String =
        "be.cobaltfilms.alphanote.Launcher" + theme.raw.replaceFirstChar { it.uppercase() }

    fun apply(context: Context, theme: ColorTheme) {
        val pm = context.packageManager
        // D'abord activer la nouvelle, puis couper les autres : jamais zéro icône.
        val ordered = listOf(theme) + ColorTheme.entries.filter { it != theme }
        for (option in ordered) {
            val component = ComponentName(context.packageName, aliasName(option))
            val wanted = if (option == theme) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            if (pm.getComponentEnabledSetting(component) != wanted) {
                pm.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
