package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import be.cobaltfilms.alphanote.timer.AlarmSound
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import be.cobaltfilms.alphanote.ai.FormulaDraftFeature
import be.cobaltfilms.alphanote.ai.ModeRoutingFeature
import be.cobaltfilms.alphanote.data.ThemeMode
import be.cobaltfilms.alphanote.sync.SyncRunState
import be.cobaltfilms.alphanote.ui.theme.ColorTheme
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette
import be.cobaltfilms.alphanote.update.UpdateManager
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun SettingsScreen(viewModel: NoteViewModel, onBack: () -> Unit) {
    val palette = LocalAlphaPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings by viewModel.settings.collectAsState()
    val aiSettings by viewModel.aiSettings.collectAsState()
    val aiTestResult by viewModel.aiTestResult.collectAsState()
    val syncSettings by viewModel.syncSettings.collectAsState()
    val syncStatus by viewModel.syncStatus.collectAsState()
    val syncMessage by viewModel.syncMessage.collectAsState()
    val updatePhase by viewModel.updatePhase.collectAsState()
    val dateFormat = remember { SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault()) }

    var localServerUrl by remember { mutableStateOf(syncSettings.nextcloudServerUrl) }
    var localUsername by remember { mutableStateOf(syncSettings.nextcloudUsername) }
    var localPassword by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    var intervalText by remember { mutableStateOf(syncSettings.syncIntervalMinutes.toString()) }
    var confirmRestore by remember { mutableStateOf(false) }
    var localJevUrl by remember(aiSettings.jevUrl) { mutableStateOf(aiSettings.jevUrl) }
    var localDelai by remember(aiSettings.jevDelaiMs) { mutableStateOf((aiSettings.jevDelaiMs / 1000).toString()) }
    var localTrigger by remember(settings.listCheckTrigger) { mutableStateOf(settings.listCheckTrigger) }
    var localAppcast by remember(settings.appcastUrl) { mutableStateOf(settings.appcastUrl) }

    LaunchedEffect(syncSettings.nextcloudServerUrl) { localServerUrl = syncSettings.nextcloudServerUrl }
    LaunchedEffect(syncSettings.nextcloudUsername) { localUsername = syncSettings.nextcloudUsername }

    Scaffold(
        containerColor = palette.content,
        topBar = {
            TopAppBar(
                title = { Text("Réglages") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Retour") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = palette.window, titleContentColor = palette.text, navigationIconContentColor = palette.secondary)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsCard("Général") {
                Text("Thème", style = MaterialTheme.typography.bodyMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ThemeMode.entries.forEach { mode ->
                        FilterChip(selected = settings.theme == mode, onClick = { viewModel.setTheme(mode) }, label = { Text(mode.label) })
                    }
                }
                Text("Couleurs : ${settings.colorTheme.label}", style = MaterialTheme.typography.bodyMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ColorTheme.entries.forEach { option ->
                        ColorThemeSwatch(option, selected = settings.colorTheme == option) { viewModel.setColorTheme(option) }
                    }
                }
                Text("Accent et teinte des fonds assortie ; l'icône de l'app suit. Au changement, certains lanceurs retirent l'icône de l'écran d'accueil.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                Text("Taille du texte : ${settings.fontSize.toInt()}", style = MaterialTheme.typography.bodyMedium)
                Slider(value = settings.fontSize, onValueChange = { viewModel.setFontSize(it) }, valueRange = 12f..26f, steps = 13)
                OutlinedTextField(
                    value = localTrigger, onValueChange = { localTrigger = it }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    label = { Text("Déclencheur « coché » (mode liste)") },
                    supportingText = { Text("Une ligne cochée se termine par ce texte. Défaut : /x") },
                    trailingIcon = { TextButton(onClick = { viewModel.setListCheckTrigger(localTrigger) }) { Text("OK") } }
                )
                SwitchSetting("Supprimer les notes vides", "À l'ouverture de la liste, les notes sans contenu disparaissent.", settings.autoCleanup, viewModel::setAutoCleanup)
                SwitchSetting("Confirmer la suppression", "Demande confirmation avant de supprimer une note non vide.", settings.confirmDelete, viewModel::setConfirmDelete)
            }

            SettingsCard("Minuteur") {
                Text("Sonnerie : ${settings.alarmSound.label}", style = MaterialTheme.typography.bodyMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AlarmSound.entries.forEach { sound ->
                        FilterChip(
                            selected = settings.alarmSound == sound,
                            onClick = { if (settings.alarmSound == sound) viewModel.previewAlarm(sound) else viewModel.setAlarmSound(sound) },
                            label = { Text(sound.label) }
                        )
                    }
                }
                Text("Jouée en boucle sur le canal alarme à la fin d'un minuteur. Toucher un choix le fait entendre.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
            }

            SettingsCard("Synchronisation Nextcloud") {
                Text("Mêmes notes que sur le Mac : dossier AlphaNote/notes de ton Nextcloud, un JSON par note.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localServerUrl, onValueChange = { localServerUrl = it }, singleLine = true,
                    label = { Text("Serveur") }, placeholder = { Text("https://cloud.example.com") })
                OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localUsername, onValueChange = { localUsername = it }, singleLine = true, label = { Text("Identifiant") })
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(), value = localPassword, onValueChange = { localPassword = it }, singleLine = true,
                    label = { Text(if (syncSettings.hasPassword) "Nouveau mot de passe d'application" else "Mot de passe d'application") },
                    visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = { TextButton(onClick = { passwordVisible = !passwordVisible }) { Text(if (passwordVisible) "Cacher" else "Voir") } },
                    supportingText = { Text(if (syncSettings.hasPassword) "Un mot de passe est déjà enregistré." else "Nextcloud › Sécurité › Mots de passe d'application.") }
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    Button(modifier = Modifier.weight(1f), onClick = {
                        val normalized = if (localServerUrl.isNotBlank() && !localServerUrl.startsWith("http")) "https://$localServerUrl" else localServerUrl.trim().removeSuffix("/")
                        viewModel.setNextcloudServerUrl(normalized)
                        viewModel.setNextcloudUsername(localUsername.trim())
                        if (localPassword.isNotEmpty()) viewModel.setNextcloudPassword(localPassword)
                        localPassword = ""
                    }) { Text("Enregistrer") }
                    OutlinedButton(modifier = Modifier.weight(1f), onClick = viewModel::testNextcloudConnection) { Text("Tester") }
                }
                OutlinedTextField(
                    modifier = Modifier.fillMaxWidth(), value = intervalText, singleLine = true,
                    onValueChange = { v -> intervalText = v.filter { it.isDigit() }.take(4); intervalText.toIntOrNull()?.let(viewModel::setSyncIntervalMinutes) },
                    label = { Text("Intervalle (minutes)") }
                )
                SwitchSetting("Synchronisation automatique", "Au lancement, toutes les N minutes, et 30 s après une modification.", syncSettings.syncEnabled, viewModel::setSyncEnabled)
                Text(syncStatusText(syncStatus, syncSettings.lastSyncAt, dateFormat), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                if (syncMessage.isNotBlank()) Text(syncMessage, style = MaterialTheme.typography.bodySmall, color = palette.accent)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    Button(modifier = Modifier.weight(1f), onClick = viewModel::runNextcloudSync) { Text("Synchroniser") }
                    OutlinedButton(modifier = Modifier.weight(1f), onClick = viewModel::createNextcloudBackup) { Text("Backup") }
                    TextButton(modifier = Modifier.weight(1f), onClick = { confirmRestore = true }) { Text("Restaurer") }
                }
            }

            SettingsCard("IA — routage de mode (JEV)") {
                SwitchSetting("Classer les demandes par le serveur JEV", "Le serveur choisit un mode (math, liste, minuteur, code, texte). Sans lui : mots-clés.", aiSettings.enabled, viewModel::setAiEnabled)
                SwitchSetting("Laisser l'IA rédiger les formules", "En mode math, une demande en mots (« aire d'un cercle de rayon 3 ») devient une formule écrite par l'IA (une dizaine de secondes), gardée seulement si la note sait la calculer, et marquée « à vérifier ».", aiSettings.formulaDraftEnabled, viewModel::setFormulaDraftEnabled)
                OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localJevUrl, onValueChange = { localJevUrl = it }, singleLine = true, label = { Text("URL du serveur de décision") })
                OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localDelai, onValueChange = { localDelai = it.filter(Char::isDigit).take(3) }, singleLine = true, label = { Text("Délai (secondes)") })
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    Button(modifier = Modifier.weight(1f), onClick = { viewModel.setJevUrl(localJevUrl); localDelai.toIntOrNull()?.let { viewModel.setJevDelaiMs(it * 1000) } }) { Text("Enregistrer") }
                    OutlinedButton(modifier = Modifier.weight(1f), onClick = viewModel::testJev) { Text("Tester") }
                }
                if (aiTestResult.isNotBlank()) Text(aiTestResult, style = MaterialTheme.typography.bodySmall, color = palette.accent)
                Text("Transparence — schéma envoyé", style = MaterialTheme.typography.titleSmall)
                Text("mode (enum : ${ModeRoutingFeature.modeField.choices.joinToString(", ")})", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                Text(ModeRoutingFeature.modeField.description, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                Text("Transparence — consigne des formules", style = MaterialTheme.typography.titleSmall)
                Text(FormulaDraftFeature.systemPrompt, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                Text("Seule la phrase de la demande est envoyée, jamais le contenu des notes. Un lien de recette est lu directement sur le site, sans IA.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
            }

            SettingsCard("Mises à jour") {
                Text("Version installée : ${viewModel.currentVersion}", style = MaterialTheme.typography.bodyMedium)
                OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localAppcast, onValueChange = { localAppcast = it }, singleLine = true, label = { Text("Appcast (JSON)") },
                    trailingIcon = { TextButton(onClick = { viewModel.setAppcastUrl(localAppcast) }) { Text("OK") } })
                when (val phase = updatePhase) {
                    UpdateManager.Phase.Idle -> Unit
                    UpdateManager.Phase.Checking -> Text("Vérification…", color = palette.secondary, style = MaterialTheme.typography.bodySmall)
                    UpdateManager.Phase.UpToDate -> Text("AlphaNote est à jour.", color = palette.accent2, style = MaterialTheme.typography.bodySmall)
                    is UpdateManager.Phase.Available -> {
                        Text("Version ${phase.info.version} disponible — ${phase.info.notes}", style = MaterialTheme.typography.bodySmall)
                        Button(onClick = { viewModel.downloadUpdate(phase.info) }) { Text("Télécharger") }
                    }
                    is UpdateManager.Phase.Downloading -> LinearProgressIndicator(progress = phase.progress, modifier = Modifier.fillMaxWidth())
                    is UpdateManager.Phase.ReadyToInstall -> Button(onClick = { viewModel.installUpdate(phase.file) }) { Text("Installer ${phase.info.version}") }
                    is UpdateManager.Phase.Failed -> Text(phase.message, color = palette.timer, style = MaterialTheme.typography.bodySmall)
                }
                OutlinedButton(onClick = viewModel::checkForUpdates) { Text("Vérifier maintenant") }
            }

            SettingsCard("Avancé") {
                Text("Export : partage un fichier avec toutes les notes actives.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    OutlinedButton(modifier = Modifier.weight(1f), onClick = { scope.launch { share(context, "alphanote-export.json", "application/json", viewModel.exportJson()) } }) { Text("JSON") }
                    OutlinedButton(modifier = Modifier.weight(1f), onClick = { scope.launch { share(context, "alphanote-export.md", "text/markdown", viewModel.exportMarkdown()) } }) { Text("Markdown") }
                }
                Text("AlphaNote Android ${viewModel.currentVersion} — même cœur que la version Mac : éditeur unique, math, liste, code, minuteur, synchro Nextcloud.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmRestore) {
        AlertDialog(
            onDismissRequest = { confirmRestore = false },
            title = { Text("Restaurer le dernier backup") },
            text = { Text("Les notes du dernier backup Nextcloud seront importées. Les notes locales de même UUID seront mises à jour.") },
            confirmButton = { TextButton(onClick = { confirmRestore = false; viewModel.restoreLatestNextcloudBackup() }) { Text("Restaurer") } },
            dismissButton = { TextButton(onClick = { confirmRestore = false }) { Text("Annuler") } }
        )
    }
}

private fun share(context: android.content.Context, filename: String, mime: String, content: String) {
    val dir = java.io.File(context.cacheDir, "exports").apply { mkdirs() }
    val file = java.io.File(dir, filename).apply { writeText(content) }
    val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
    val intent = Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(intent, "Exporter les notes"))
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
    val palette = LocalAlphaPalette.current
    Card(colors = CardDefaults.cardColors(containerColor = palette.sidebar)) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = palette.text)
            content()
        }
    }
}

@Composable
private fun SwitchSetting(title: String, subtitle: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val palette = LocalAlphaPalette.current
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Spacer(modifier = Modifier.height(2.dp))
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
        }
        Spacer(modifier = Modifier.width(14.dp))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

private fun syncStatusText(status: SyncRunState, lastSyncAt: Long?, dateFormat: SimpleDateFormat): String = when (status) {
    SyncRunState.Idle -> lastSyncAt?.let { "Dernière synchro : ${dateFormat.format(Date(it))}" } ?: "Aucune synchronisation."
    SyncRunState.Syncing -> "Synchronisation en cours…"
    SyncRunState.TestingConnection -> "Test de connexion…"
    SyncRunState.BackingUp -> "Backup en cours…"
    SyncRunState.Restoring -> "Restauration en cours…"
    is SyncRunState.Success -> "Dernière opération réussie : ${dateFormat.format(Date(status.timestamp))}"
    is SyncRunState.Error -> status.message
}

/** Pastille d'un thème : fond de nuit + accent, anneau si choisi. */
@Composable
private fun ColorThemeSwatch(theme: ColorTheme, selected: Boolean, onClick: () -> Unit) {
    val palette = LocalAlphaPalette.current
    Box(
        modifier = Modifier
            .size(36.dp)
            .border(if (selected) 2.dp else 1.dp, if (selected) palette.text else palette.line, CircleShape)
            .padding(3.dp)
            .background(Color(0xFF000000.toInt() or theme.night.window), CircleShape)
            .clickable(onClickLabel = theme.label, onClick = onClick)
            .semantics { contentDescription = theme.label },
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.size(18.dp).background(Color(0xFF000000.toInt() or theme.night.accent), CircleShape))
    }
}
