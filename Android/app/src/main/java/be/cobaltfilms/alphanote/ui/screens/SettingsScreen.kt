package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * Écran de paramètres.
 * Portage de UI/SettingsView.swift (macOS).
 *
 * Sections : Général, Apparence, IA, À propos
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Paramètres") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Retour")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
        ) {
            // Section Général
            SettingsSection(title = "Général") {
                var autoDetectMode by remember { mutableStateOf(true) }
                SwitchSetting(
                    title = "Détection automatique du mode",
                    subtitle = "Analyse la première ligne pour activer math, list, code ou timer",
                    checked = autoDetectMode,
                    onCheckedChange = { autoDetectMode = it }
                )

                var confirmDelete by remember { mutableStateOf(true) }
                SwitchSetting(
                    title = "Confirmer la suppression",
                    subtitle = "Demander confirmation avant de supprimer une note",
                    checked = confirmDelete,
                    onCheckedChange = { confirmDelete = it }
                )
            }

            Divider(modifier = Modifier.padding(horizontal = 16.dp))

            // Section Apparence
            SettingsSection(title = "Apparence") {
                var darkTheme by remember { mutableStateOf(false) }
                SwitchSetting(
                    title = "Thème sombre",
                    subtitle = "Utiliser le thème sombre par défaut",
                    checked = darkTheme,
                    onCheckedChange = { darkTheme = it }
                )

                var monospace by remember { mutableStateOf(false) }
                SwitchSetting(
                    title = "Police monospace",
                    subtitle = "Utiliser une police à chasse fixe dans toutes les notes",
                    checked = monospace,
                    onCheckedChange = { monospace = it }
                )
            }

            Divider(modifier = Modifier.padding(horizontal = 16.dp))

            // Section IA
            SettingsSection(title = "Intelligence Artificielle") {
                var enableAI by remember { mutableStateOf(true) }
                SwitchSetting(
                    title = "Assistant IA",
                    subtitle = "Activer les suggestions IA dans la barre d'outils",
                    checked = enableAI,
                    onCheckedChange = { enableAI = it }
                )

                var localOnly by remember { mutableStateOf(true) }
                SwitchSetting(
                    title = "IA locale uniquement",
                    subtitle = "Utiliser uniquement le moteur d'inférence local (MediaPipe)",
                    checked = localOnly,
                    onCheckedChange = { localOnly = it }
                )
            }

            Divider(modifier = Modifier.padding(horizontal = 16.dp))

            // Section À propos
            SettingsSection(title = "À propos") {
                Text(
                    text = "AlphaNote v1.0.0 (Android)",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
                )

                Text(
                    text = "Application de prise de notes éphémères.\nPortage Android depuis macOS Swift/SwiftUI.\n\n© 2026 Cobalt Films. Tous droits réservés.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                )
            }

            Spacer(modifier = Modifier.height(32.dp))
        }
    }
}

/** Titre de section */
@Composable
private fun SettingsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier = Modifier.padding(top = 16.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
        )
        content()
    }
}

/** Composant switch avec titre et sous-titre */
@Composable
private fun SwitchSetting(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(modifier = Modifier.width(16.dp))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange
        )
    }
}
