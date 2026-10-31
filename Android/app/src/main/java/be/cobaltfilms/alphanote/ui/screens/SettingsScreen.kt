package be.cobaltfilms.alphanote.ui.screens

import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.SystemUpdate
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Palette
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
import be.cobaltfilms.alphanote.vault.VaultKeyring
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
import be.cobaltfilms.alphanote.sync.LanSyncCoordinator
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
    var localAccessId by remember(aiSettings.accessClientId) { mutableStateOf(aiSettings.accessClientId) }
    var localAccessSecret by remember(aiSettings.accessClientSecret) { mutableStateOf(aiSettings.accessClientSecret) }
    var localDelai by remember(aiSettings.jevDelaiMs) { mutableStateOf((aiSettings.jevDelaiMs / 1000).toString()) }
    var localTrigger by remember(settings.listCheckTrigger) { mutableStateOf(settings.listCheckTrigger) }
    var localAppcast by remember(settings.appcastUrl) { mutableStateOf(settings.appcastUrl) }
    val lanEnabled by viewModel.lanSync.enabled.collectAsState()
    val lanPaired by viewModel.lanSync.pairedName.collectAsState()
    val lanState by viewModel.lanSync.state.collectAsState()
    var lanCode by remember { mutableStateOf("") }
    var lanMessage by remember { mutableStateOf("") }

    LaunchedEffect(syncSettings.nextcloudServerUrl) { localServerUrl = syncSettings.nextcloudServerUrl }
    LaunchedEffect(syncSettings.nextcloudUsername) { localUsername = syncSettings.nextcloudUsername }

    // Une rubrique à la fois : la page d'accueil liste les rubriques.
    var page by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf<String?>(null) }
    androidx.activity.compose.BackHandler(enabled = page != null) { page = null }

    Scaffold(
        containerColor = palette.content,
        topBar = {
            TopAppBar(
                title = { Text(SETTINGS_PAGES.firstOrNull { it.id == page }?.title ?: "Réglages") },
                navigationIcon = { IconButton(onClick = { if (page != null) page = null else onBack() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Retour") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = palette.window, titleContentColor = palette.text, navigationIconContentColor = palette.secondary)
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (page == null) SettingsHome { page = it }

            if (page == "apparence") SettingsCard("Apparence") {
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
            }

            if (page == "notes") SettingsCard("Notes") {
                OutlinedTextField(
                    value = localTrigger, onValueChange = { localTrigger = it }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                    label = { Text("Déclencheur « coché » (mode liste)") },
                    supportingText = { Text("Une ligne cochée se termine par ce texte. Défaut : /x") },
                    trailingIcon = { TextButton(onClick = { viewModel.setListCheckTrigger(localTrigger) }) { Text("OK") } }
                )
                SwitchSetting("Supprimer les notes vides", "À l'ouverture de la liste, les notes sans contenu disparaissent.", settings.autoCleanup, viewModel::setAutoCleanup)
                SwitchSetting("Confirmer la suppression", "Demande confirmation avant de supprimer une note non vide.", settings.confirmDelete, viewModel::setConfirmDelete)
            }

            if (page == "minuteur") SettingsCard("Minuteur") {
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

            if (page == "synchro") SettingsCard("Mac sur le Wi-Fi") {
                SwitchSetting("Synchroniser avec mon Mac", "Sur le même Wi-Fi, les notes passent directement, sans Nextcloud. Côté Mac : Réglages › Synchronisation › Réseau local.", lanEnabled, viewModel::setLanEnabled)
                if (lanEnabled) {
                    val paired = lanPaired
                    if (paired != null) {
                        Text("Appairé avec $paired", style = MaterialTheme.typography.bodyMedium)
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                            Button(modifier = Modifier.weight(1f), onClick = viewModel::syncLanNow) { Text("Synchroniser") }
                            OutlinedButton(modifier = Modifier.weight(1f), onClick = { lanMessage = ""; viewModel.forgetLan() }) { Text("Oublier") }
                        }
                    } else {
                        Text("Sur le Mac, ouvrez Réglages › Synchronisation › Réseau local et appuyez sur « Appairer un téléphone ».", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                        OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = lanCode, onValueChange = { lanCode = it.filter(Char::isDigit).take(6) }, singleLine = true, label = { Text("Code affiché sur le Mac") })
                        Button(modifier = Modifier.fillMaxWidth(), enabled = lanCode.length == 6, onClick = {
                            viewModel.pairLan(lanCode) { message -> lanMessage = message; if (message.startsWith("Appairé")) lanCode = "" }
                        }) { Text("Appairer") }
                    }
                    Text(lanStatusText(lanState, dateFormat), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                    if (lanMessage.isNotBlank()) Text(lanMessage, style = MaterialTheme.typography.bodySmall, color = palette.accent)
                }
            }

            if (page == "synchro") SettingsCard("Synchronisation Nextcloud") {
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

            if (page == "coffre") SettingsCard("Coffre — notes sécurisées") {
                val configured by VaultKeyring.isConfigured.collectAsState()
                val unlocked by VaultKeyring.isUnlocked.collectAsState()
                var autoLock by remember { mutableStateOf(VaultKeyring.autoLockMinutes) }
                var confirmForget by remember { mutableStateOf(false) }
                Text(
                    when { !configured -> "Pas de mot de passe maître sur ce téléphone."; unlocked -> "Coffre ouvert."; else -> "Coffre fermé." },
                    style = MaterialTheme.typography.bodyMedium
                )
                Text("Refermer après", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf(1 to "1 min", 5 to "5 min", 15 to "15 min", 60 to "1 h").forEach { (minutes, label) ->
                        FilterChip(selected = autoLock == minutes, onClick = { autoLock = minutes; VaultKeyring.setAutoLock(minutes) }, label = { Text(label) })
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    if (unlocked) OutlinedButton(modifier = Modifier.weight(1f), onClick = { VaultKeyring.lockNow() }) { Text("Verrouiller") }
                    if (configured) OutlinedButton(modifier = Modifier.weight(1f), onClick = { confirmForget = true }) { Text("Oublier le mot de passe", color = palette.timer) }
                }
                Text(
                    "Une note dont la première ligne est « vault » (ou « vault: Titre ») est chiffrée sur le téléphone avant d'être enregistrée ou synchronisée ; seul le titre reste lisible. L'IA n'y a jamais accès. Le mot de passe maître est le même sur tous tes appareils et ne peut pas être récupéré.",
                    style = MaterialTheme.typography.bodySmall, color = palette.secondary
                )
                if (confirmForget) AlertDialog(
                    onDismissRequest = { confirmForget = false },
                    title = { Text("Oublier le mot de passe maître ?") },
                    text = { Text("Les notes sécurisées restent chiffrées. Il faudra ressaisir le mot de passe maître pour les lire sur ce téléphone.") },
                    confirmButton = { TextButton(onClick = { confirmForget = false; VaultKeyring.forget() }) { Text("Oublier", color = palette.timer) } },
                    dismissButton = { TextButton(onClick = { confirmForget = false }) { Text("Annuler") } }
                )
            }

            if (page == "ia") SettingsCard("Moteurs en service") {
                EngineRow(
                    "Classement des demandes", if (aiSettings.enabled) "Serveur JEV" else "Modèle local",
                    if (aiSettings.enabled) "Le serveur classe la demande ; s'il ne répond pas, le modèle du téléphone prend le relais."
                    else "Un petit modèle sur le téléphone classe la demande (calcul, liste, minuteur, code, texte), hors ligne."
                )
                EngineRow(
                    "Rédaction des formules",
                    when { !aiSettings.formulaDraftEnabled -> "Désactivée"; aiSettings.enabled -> "Serveur JEV"; else -> "Indisponible" },
                    when {
                        !aiSettings.formulaDraftEnabled -> "Les demandes en mots ne deviennent pas des formules."
                        aiSettings.enabled -> "Une demande en mots (« aire d'un cercle de rayon 3 ») devient une formule, gardée seulement si la note sait la calculer."
                        else -> "Il faut un serveur JEV : le téléphone n'a pas de modèle capable de rédiger."
                    }
                )
                Text("Seule la phrase de la demande quitte le téléphone, et seulement vers un serveur JEV si vous en utilisez un : jamais le contenu des notes.", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
            }

            if (page == "ia") SettingsCard("Rédaction des formules") {
                SwitchSetting("Laisser l'IA rédiger les formules", "Formule marquée « à vérifier », gardée seulement si la note sait la calculer.", aiSettings.formulaDraftEnabled, viewModel::setFormulaDraftEnabled)
            }

            if (page == "ia") SettingsCard("Serveur JEV (facultatif)") {
                SwitchSetting("Utiliser un serveur JEV", "Pour classer les demandes avec votre propre serveur et rédiger les formules.", aiSettings.enabled, viewModel::setAiEnabled)
                if (aiSettings.enabled) {
                    OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localJevUrl, onValueChange = { localJevUrl = it }, singleLine = true, label = { Text("URL du serveur") })
                    OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localAccessId, onValueChange = { localAccessId = it }, singleLine = true,
                        label = { Text("Jeton d'accès — Client ID") }, supportingText = { Text("Cloudflare Access ; vide pour un serveur local ou Tailscale.") })
                    OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localAccessSecret, onValueChange = { localAccessSecret = it }, singleLine = true,
                        label = { Text("Jeton d'accès — Client Secret") }, visualTransformation = PasswordVisualTransformation())
                    OutlinedTextField(modifier = Modifier.fillMaxWidth(), value = localDelai, onValueChange = { localDelai = it.filter(Char::isDigit).take(3) }, singleLine = true, label = { Text("Délai (secondes)") })
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                        Button(modifier = Modifier.weight(1f), onClick = { viewModel.setJevUrl(localJevUrl); viewModel.setJevAccessToken(localAccessId, localAccessSecret); localDelai.toIntOrNull()?.let { viewModel.setJevDelaiMs(it * 1000) } }) { Text("Enregistrer") }
                        OutlinedButton(modifier = Modifier.weight(1f), onClick = viewModel::testJev) { Text("Tester") }
                    }
                    if (aiTestResult.isNotBlank()) Text(aiTestResult, style = MaterialTheme.typography.bodySmall, color = palette.accent)
                    var details by remember { mutableStateOf(false) }
                    TextButton(onClick = { details = !details }) { Text(if (details) "Masquer ce que reçoit le serveur" else "Ce que reçoit le serveur…") }
                    if (details) {
                        Text("Classement : un champ « mode » (${ModeRoutingFeature.modeField.choices.joinToString(", ")}).", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                        Text(ModeRoutingFeature.modeField.description, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                        Text("Formules :", style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                        Text(FormulaDraftFeature.systemPrompt, style = MaterialTheme.typography.bodySmall.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace), color = palette.secondary)
                    }
                }
            }

            if (page == "maj") SettingsCard("Mises à jour") {
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

            if (page == "avance") SettingsCard("Avancé") {
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

private fun lanStatusText(state: LanSyncCoordinator.State, dateFormat: SimpleDateFormat): String = when (state) {
    LanSyncCoordinator.State.Idle -> ""
    LanSyncCoordinator.State.Searching -> "Recherche du Mac sur le Wi-Fi…"
    LanSyncCoordinator.State.Syncing -> "Synchronisation avec le Mac…"
    LanSyncCoordinator.State.NotFound -> "Mac introuvable sur ce Wi-Fi : est-il allumé, sur le même réseau ?"
    is LanSyncCoordinator.State.Done -> "Dernière synchro : ${dateFormat.format(Date(state.at))} — ${state.applied} reçue(s), ${state.pushed} envoyée(s)."
    is LanSyncCoordinator.State.Failed -> state.message
}

private data class SettingsPage(val id: String, val title: String, val subtitle: String, val icon: androidx.compose.ui.graphics.vector.ImageVector)

private val SETTINGS_PAGES = listOf(
    SettingsPage("apparence", "Apparence", "Thème, couleurs, taille du texte", Icons.Default.Palette),
    SettingsPage("notes", "Notes", "Listes, notes vides, suppression", Icons.Default.Description),
    SettingsPage("minuteur", "Minuteur", "Sonnerie", Icons.Default.Timer),
    SettingsPage("synchro", "Synchronisation", "Mac sur le Wi-Fi, Nextcloud", Icons.Default.Sync),
    SettingsPage("coffre", "Coffre", "Notes sécurisées", Icons.Default.Lock),
    SettingsPage("ia", "Intelligence artificielle", "Modèle local, serveur JEV", Icons.Default.AutoAwesome),
    SettingsPage("maj", "Mises à jour", "Version installée, vérification", Icons.Default.SystemUpdate),
    SettingsPage("avance", "Avancé", "Export, sauvegarde", Icons.Default.Tune),
)

@Composable
private fun SettingsHome(onOpen: (String) -> Unit) {
    val palette = LocalAlphaPalette.current
    Card(colors = CardDefaults.cardColors(containerColor = palette.sidebar)) {
        Column {
            SETTINGS_PAGES.forEachIndexed { index, item ->
                Row(
                    modifier = Modifier.fillMaxWidth().clickable { onOpen(item.id) }.padding(horizontal = 16.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Icon(item.icon, contentDescription = null, tint = palette.accent)
                    Column(modifier = Modifier.weight(1f)) {
                        Text(item.title, style = MaterialTheme.typography.bodyLarge, color = palette.text)
                        Text(item.subtitle, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = palette.secondary)
                }
                if (index < SETTINGS_PAGES.lastIndex) androidx.compose.material3.HorizontalDivider(color = palette.line)
            }
        }
    }
}

@Composable
private fun EngineRow(title: String, value: String, detail: String) {
    val palette = LocalAlphaPalette.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
            Text(value, style = MaterialTheme.typography.bodyMedium, color = palette.accent)
        }
        Text(detail, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
    }
}
