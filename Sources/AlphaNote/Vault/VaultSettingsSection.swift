import SwiftUI

/// Réglages du coffre (macOS et iOS) : état, verrouillage, délai de
/// refermeture, oubli du mot de passe maître sur cet appareil.
struct VaultSettingsSection: View {
    @ObservedObject private var vault = VaultKeyring.shared
    @AppStorage(VaultKeyring.autoLockKey) private var autoLockMinutes = VaultKeyring.autoLockDefault
    @State private var confirmForget = false

    var body: some View {
        Section {
            LabeledContent("État") {
                Label(state, systemImage: vault.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(vault.isUnlocked ? Palette.modeColor(.vault) : Palette.secondaryColor)
            }
            Picker("Refermer après", selection: $autoLockMinutes) {
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("1 heure").tag(60)
            }
            if vault.isUnlocked {
                Button("Verrouiller maintenant") { vault.lockNow() }
            }
            if vault.isConfigured {
                Button("Oublier le mot de passe sur cet appareil", role: .destructive) { confirmForget = true }
                    .confirmationDialog("Oublier le mot de passe maître ?", isPresented: $confirmForget) {
                        Button("Oublier", role: .destructive) { vault.forget() }
                    } message: {
                        Text("Les notes sécurisées restent chiffrées. Il faudra ressaisir le mot de passe maître pour les lire sur cet appareil.")
                    }
            }
        } header: {
            Text("Coffre")
        } footer: {
            Text("Une note dont la première ligne est « vault » (ou « vault: Titre ») est chiffrée sur l'appareil avant d'être enregistrée ou synchronisée ; seul le titre reste lisible. L'IA n'y a jamais accès. Le mot de passe maître est le même sur tous tes appareils et ne peut pas être récupéré.")
        }
    }

    private var state: String {
        if !vault.isConfigured { return "Pas de mot de passe maître" }
        return vault.isUnlocked ? "Ouvert" : "Fermé"
    }
}
