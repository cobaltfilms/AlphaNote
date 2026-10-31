package be.cobaltfilms.alphanote.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import be.cobaltfilms.alphanote.ai.NoteMode
import be.cobaltfilms.alphanote.ui.theme.LocalAlphaPalette
import be.cobaltfilms.alphanote.vault.VaultKeyring

/**
 * Écran d'une note sécurisée quand le coffre est fermé (port de
 * VaultLockView.swift) : empreinte ou mot de passe maître, ou première mise en
 * place du mot de passe sur ce téléphone.
 */
@Composable
fun VaultLockScreen(title: String, sealedContents: () -> List<String>, modifier: Modifier = Modifier) {
    val palette = LocalAlphaPalette.current
    val activity = LocalContext.current as? FragmentActivity
    val configured by VaultKeyring.isConfigured.collectAsState()
    var password by remember { mutableStateOf("") }
    var confirmation by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    val vaultColor = palette.mode(NoteMode.VAULT)

    fun biometrics() {
        activity ?: return
        VaultKeyring.unlockWithBiometrics(activity) { error -> if (!error.isNullOrEmpty()) message = error }
    }

    // Empreinte proposée d'emblée, sauf juste après un verrouillage demandé.
    LaunchedEffect(Unit) {
        if (configured && !VaultKeyring.justLockedManually && activity != null && VaultKeyring.canUseBiometrics(activity)) biometrics()
    }

    Column(
        modifier = modifier.fillMaxSize().padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)
    ) {
        Icon(Icons.Default.Lock, contentDescription = null, tint = vaultColor, modifier = Modifier.size(40.dp))
        Text(title.ifEmpty { "Note sécurisée" }, color = palette.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)

        val existing = remember(configured) { sealedContents() }
        if (configured) {
            Button(
                onClick = ::biometrics, modifier = Modifier.widthIn(max = 340.dp).fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = vaultColor)
            ) {
                Icon(Icons.Default.Fingerprint, contentDescription = null)
                Text("  Ouvrir le coffre")
            }
            PasswordField("Mot de passe maître", password, { password = it }) {
                runCatching { VaultKeyring.unlock(password) }.onFailure { message = it.message }.onSuccess { password = "" }
            }
        } else {
            Text(
                if (existing.isEmpty()) "Choisis un mot de passe maître. Il chiffre tes notes sécurisées sur tous tes appareils : sans lui, elles sont illisibles, et personne ne peut le retrouver."
                else "Des notes sécurisées arrivent d'un autre appareil. Saisis le mot de passe maître choisi là-bas.",
                color = palette.secondary, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 340.dp)
            )
            val setUp: () -> Unit = {
                if (existing.isEmpty() && password != confirmation) {
                    message = "Les deux mots de passe diffèrent."
                } else {
                    runCatching { VaultKeyring.setUp(password, existing) }
                        .onFailure { message = it.message }
                        .onSuccess { password = ""; confirmation = "" }
                }
            }
            PasswordField("Mot de passe maître", password, { password = it }, onDone = if (existing.isEmpty()) null else setUp)
            if (existing.isEmpty()) PasswordField("Confirmation", confirmation, { confirmation = it }, onDone = setUp)
            Button(
                onClick = setUp, enabled = password.isNotEmpty(), modifier = Modifier.widthIn(max = 340.dp).fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = vaultColor)
            ) { Text("Définir le mot de passe") }
        }
        message?.let { Text(it, color = palette.timer, fontSize = 14.sp, textAlign = TextAlign.Center) }
    }
}

@Composable
private fun PasswordField(label: String, value: String, onChange: (String) -> Unit, onDone: (() -> Unit)?) {
    OutlinedTextField(
        value = value, onValueChange = onChange, singleLine = true, label = { Text(label) },
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = if (onDone != null) ImeAction.Done else ImeAction.Next),
        keyboardActions = KeyboardActions(onDone = { onDone?.invoke() }),
        modifier = Modifier.widthIn(max = 340.dp).fillMaxWidth()
    )
}
