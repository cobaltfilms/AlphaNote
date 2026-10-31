import CryptoKit
import Foundation
import LocalAuthentication

/// Le coffre des notes sécurisées : garde le mot de passe maître (trousseau),
/// dérive et met en cache les clés tant que le coffre est ouvert, et le
/// referme après quelques minutes sans usage. Déverrouillage par Touch ID /
/// Face ID (ou le mot de passe de session en secours), sinon par le mot de
/// passe maître.
@MainActor
final class VaultKeyring: ObservableObject {
    static let shared = VaultKeyring()

    static let autoLockKey = "vaultAutoLockMinutes"
    static let autoLockDefault = 5

    enum UnlockError: LocalizedError, Equatable {
        case notConfigured
        case wrongPassword
        case passwordTooShort
        case biometricsUnavailable
        case cancelled

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Aucun mot de passe maître n'est défini sur cet appareil."
            case .wrongPassword: return "Mot de passe maître incorrect."
            case .passwordTooShort: return "Le mot de passe maître doit faire au moins 8 caractères."
            case .biometricsUnavailable: return "Déverrouillage biométrique indisponible : utilise le mot de passe maître."
            case .cancelled: return "Déverrouillage annulé."
            }
        }
    }

    @Published private(set) var isUnlocked = false
    /// Verrouillage demandé à l'instant : l'écran du coffre ne relance pas
    /// Touch ID de lui-même.
    private(set) var lastManualLock: Date?
    @Published private(set) var isConfigured: Bool

    private static let keychainServer = "alphanote-vault"
    private static let keychainAccount = "master"
    private static let primarySaltKey = "vaultPrimarySalt"

    private var password: String?
    /// Mot de passe « enregistré » quand rien ne va au trousseau (tests).
    private var memoryStoredPassword: String?
    private var keysBySalt: [Data: SymmetricKey] = [:]
    private var lockTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let storesSecrets: Bool

    /// `storesSecrets: false` pour les tests : rien n'est écrit au trousseau.
    init(defaults: UserDefaults = .standard, storesSecrets: Bool = true) {
        self.defaults = defaults
        self.storesSecrets = storesSecrets
        isConfigured = storesSecrets && Self.keychainPassword() != nil
    }

    // MARK: - Mise en place

    /// Définit le mot de passe maître sur cet appareil. S'il existe déjà des
    /// notes sécurisées (venues d'un autre appareil), le mot de passe doit les
    /// ouvrir : c'est lui qui a servi à les chiffrer.
    func setUp(password: String, existingSealed: [String]) throws {
        guard password.count >= 8 else { throw UnlockError.passwordTooShort }
        if let sample = existingSealed.lazy.compactMap(VaultEnvelope.parse).first {
            let key = VaultEnvelope.deriveKey(password: password, salt: sample.salt, iterations: sample.iterations)
            guard (try? VaultEnvelope.open(sample, key: key)) != nil else { throw UnlockError.wrongPassword }
            defaults.set(sample.salt.base64URL, forKey: Self.primarySaltKey)
        } else if primarySalt == nil {
            defaults.set(VaultEnvelope.randomSalt().base64URL, forKey: Self.primarySaltKey)
        }
        if storesSecrets {
            try KeychainService.shared.savePassword(password, serverURL: Self.keychainServer, username: Self.keychainAccount)
        } else {
            memoryStoredPassword = password
        }
        isConfigured = true
        open(with: password)
    }

    /// Oublie le mot de passe maître sur cet appareil (les notes restent
    /// chiffrées ; il faudra le ressaisir pour les lire).
    func forget() {
        lock()
        if storesSecrets {
            try? KeychainService.shared.deletePassword(serverURL: Self.keychainServer, username: Self.keychainAccount)
        }
        memoryStoredPassword = nil
        isConfigured = false
    }

    // MARK: - Ouvrir / fermer

    func unlock(password candidate: String) throws {
        guard isConfigured, let stored = storedPassword() else {
            throw UnlockError.notConfigured
        }
        guard Self.constantTimeEquals(candidate, stored) else { throw UnlockError.wrongPassword }
        open(with: stored)
    }

    /// Touch ID / Face ID, avec le mot de passe de session en secours.
    func unlockWithBiometrics() async throws {
        guard isConfigured, let stored = storedPassword() else { throw UnlockError.notConfigured }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw UnlockError.biometricsUnavailable
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "ouvrir les notes sécurisées")
        } catch {
            throw UnlockError.cancelled
        }
        open(with: stored)
    }

    /// Verrouillage demandé (bouton, menu) plutôt qu'automatique.
    func lockNow() {
        lock()
        lastManualLock = Date()
    }

    var justLockedManually: Bool {
        lastManualLock.map { Date().timeIntervalSince($0) < 3 } ?? false
    }

    func lock() {
        lockTask?.cancel()
        lockTask = nil
        password = nil
        keysBySalt.removeAll()
        isUnlocked = false
    }

    // MARK: - Chiffrer / déchiffrer

    /// Scelle le contenu d'une note sécurisée. Nil si le coffre est fermé.
    func seal(_ content: String) -> String? {
        guard isUnlocked, let salt = primarySalt, let key = key(for: salt, iterations: VaultEnvelope.iterations) else {
            return nil
        }
        touch()
        return try? VaultEnvelope.seal(content, key: key, salt: salt)
    }

    /// Texte en clair d'une note scellée. Nil si fermé ou si le mot de passe
    /// de cet appareil ne l'ouvre pas.
    func open(_ content: String) -> String? {
        guard isUnlocked, let parsed = VaultEnvelope.parse(content),
              let key = key(for: parsed.salt, iterations: parsed.iterations) else {
            return nil
        }
        touch()
        return try? VaultEnvelope.open(parsed, key: key)
    }

    // MARK: - Interne

    private var primarySalt: Data? {
        defaults.string(forKey: Self.primarySaltKey).flatMap(Data.init(base64URL:))
    }

    private func open(with password: String) {
        self.password = password
        isUnlocked = true
        touch()
    }

    private func key(for salt: Data, iterations: Int) -> SymmetricKey? {
        if let key = keysBySalt[salt] { return key }
        guard let password else { return nil }
        let key = VaultEnvelope.deriveKey(password: password, salt: salt, iterations: iterations)
        keysBySalt[salt] = key
        return key
    }

    /// Refermeture automatique après N minutes sans lecture ni écriture.
    private func touch() {
        let minutes = defaults.object(forKey: Self.autoLockKey) as? Int ?? Self.autoLockDefault
        lockTask?.cancel()
        guard minutes > 0 else { return }
        lockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lock()
        }
    }

    private func storedPassword() -> String? {
        storesSecrets ? Self.keychainPassword() : memoryStoredPassword
    }

    private static func keychainPassword() -> String? {
        try? KeychainService.shared.readPassword(serverURL: keychainServer, username: keychainAccount)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
