import SwiftUI

/// Écran d'une note sécurisée quand le coffre est fermé : ouverture par
/// Touch ID / Face ID ou mot de passe maître, ou première mise en place du
/// mot de passe sur cet appareil. Partagé macOS / iOS.
struct VaultLockView: View {
    @EnvironmentObject private var store: NoteStore
    @ObservedObject private var vault = VaultKeyring.shared
    let title: String

    @State private var password = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var isWorking = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Palette.modeColor(.vault))
            Text(title.isEmpty ? "Note sécurisée" : title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.textColor)
                .multilineTextAlignment(.center)

            if vault.isConfigured {
                unlockForm
            } else {
                setUpForm
            }

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 340)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.contentColor)
        .task {
            // Touch ID proposé d'emblée, comme une app de mots de passe.
            if vault.isConfigured, !vault.isUnlocked, !vault.justLockedManually { await unlockWithBiometrics() }
        }
    }

    private var unlockForm: some View {
        VStack(spacing: 10) {
            Button {
                Task { await unlockWithBiometrics() }
            } label: {
                Label("Ouvrir le coffre", systemImage: "touchid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.modeColor(.vault))
            .controlSize(.large)
            .disabled(isWorking)

            SecureField("Mot de passe maître", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($passwordFocused)
                .onSubmit(unlockWithPassword)
                .accessibilityIdentifier("vaultPassword")
        }
    }

    private var setUpForm: some View {
        VStack(spacing: 10) {
            Text(store.sealedVaultContents.isEmpty
                 ? "Choisis un mot de passe maître. Il chiffre tes notes sécurisées sur tous tes appareils : sans lui, elles sont illisibles, et personne ne peut le retrouver."
                 : "Des notes sécurisées arrivent d'un autre appareil. Saisis le mot de passe maître choisi là-bas.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Mot de passe maître", text: $password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("vaultPassword")
            if store.sealedVaultContents.isEmpty {
                SecureField("Confirmation", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(setUp)
                    .accessibilityIdentifier("vaultConfirmation")
            }
            Button("Définir le mot de passe", action: setUp)
                .buttonStyle(.borderedProminent)
                .tint(Palette.modeColor(.vault))
                .disabled(password.isEmpty || isWorking)
        }
    }

    // MARK: - Actions

    private func unlockWithBiometrics() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await vault.unlockWithBiometrics()
            didOpen()
        } catch VaultKeyring.UnlockError.cancelled {
            passwordFocused = true
        } catch {
            message = error.localizedDescription
            passwordFocused = true
        }
    }

    private func unlockWithPassword() {
        do {
            try vault.unlock(password: password)
            didOpen()
        } catch {
            message = error.localizedDescription
        }
    }

    private func setUp() {
        let existing = store.sealedVaultContents
        if existing.isEmpty, password != confirmation {
            message = "Les deux mots de passe diffèrent."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try vault.setUp(password: password, existingSealed: existing)
            didOpen()
        } catch {
            message = error.localizedDescription
        }
    }

    private func didOpen() {
        password = ""
        confirmation = ""
        message = nil
        store.sealHeldVaultNotes()
    }
}
