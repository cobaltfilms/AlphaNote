import CryptoKit
import XCTest
@testable import AlphaNote

/// Notes sécurisées : format d'enveloppe (partagé avec Android) et coffre.
final class VaultTests: XCTestCase {
    private let salt = Data(1...16)
    private let nonceBytes = Data(repeating: 0xA0, count: 12)

    func testSealOpenRoundTripKeepsTextExactly() throws {
        let key = VaultEnvelope.deriveKey(password: "correct horse", salt: salt)
        for content in ["vault: Jetons\nCF: abc\n", "vault", "vault: X\n", "vault: Clés\n\n  indenté\nfin"] {
            let sealed = try VaultEnvelope.seal(content, key: key, salt: salt)
            XCTAssertTrue(sealed.hasPrefix(VaultEnvelope.split(content).header + "\n" + VaultEnvelope.prefix), sealed)
            XCTAssertFalse(sealed.contains("abc"))
            XCTAssertEqual(try VaultEnvelope.open(sealed, key: key), content)
        }
    }

    func testWrongPasswordIsRejected() throws {
        let sealed = try VaultEnvelope.seal("vault: A\nsecret", key: VaultEnvelope.deriveKey(password: "correct horse", salt: salt), salt: salt)
        XCTAssertThrowsError(try VaultEnvelope.open(sealed, key: VaultEnvelope.deriveKey(password: "wrong horse", salt: salt))) {
            XCTAssertEqual($0 as? VaultEnvelope.Failure, .wrongKey)
        }
    }

    func testTamperedCiphertextIsRejected() throws {
        let key = VaultEnvelope.deriveKey(password: "correct horse", salt: salt)
        let sealed = try VaultEnvelope.seal("vault: A\nsecret", key: key, salt: salt)
        // Un caractère au milieu du chiffré (le dernier peut ne porter que des
        // bits de remplissage base64).
        var characters = Array(sealed)
        let middle = characters.count - 20
        characters[middle] = characters[middle] == "A" ? "B" : "A"
        XCTAssertThrowsError(try VaultEnvelope.open(String(characters), key: key))
    }

    /// Vecteur figé : VaultEnvelopeTest.kt (Android) attend la même chaîne.
    func testKnownVectorMatchesAndroid() throws {
        let key = VaultEnvelope.deriveKey(password: "correct horse", salt: salt)
        let nonce = try AES.GCM.Nonce(data: nonceBytes)
        let sealed = try VaultEnvelope.seal("vault: Test\nmot de passe : é1", key: key, salt: salt, nonce: nonce)
        XCTAssertEqual(sealed, Self.knownVector)
        XCTAssertEqual(try VaultEnvelope.open(Self.knownVector, key: key), "vault: Test\nmot de passe : é1")
    }

    static let knownVector = "vault: Test\nANVAULT1.AQIDBAUGBwgJCgsMDQ4PEA.600000.oKCgoKCgoKCgoKCgcVqJJRyNtY6SrGhcHrIrn-vtCtYcRbzau0G83lB4PPgOyZc"

    func testNotesKnowTheyAreVault() {
        var note = Note(content: "vault: Jetons\nabc")
        XCTAssertTrue(note.isVault)
        XCTAssertEqual(note.effectiveTitle, "Jetons")
        note.content = "vaul: Jetons\n" + VaultEnvelope.prefix + "x.600000.y"
        note.detectKeyword()
        XCTAssertFalse(note.isVault, "enveloppe invalide : pas une note scellée")
        XCTAssertFalse(NoteMode.routable.contains(.vault))
    }

    // MARK: - Coffre

    @MainActor
    func testKeyringSealsOnlyWhenUnlocked() throws {
        let defaults = UserDefaults(suiteName: "vault-test-\(UUID().uuidString)")!
        let keyring = VaultKeyring(defaults: defaults, storesSecrets: false)
        XCTAssertNil(keyring.seal("vault\nx"))
        XCTAssertThrowsError(try keyring.setUp(password: "court", existingSealed: []))
        try keyring.setUp(password: "correct horse", existingSealed: [])
        let sealed = try XCTUnwrap(keyring.seal("vault: A\nsecret"))
        XCTAssertEqual(keyring.open(sealed), "vault: A\nsecret")

        keyring.lock()
        XCTAssertNil(keyring.open(sealed))
        XCTAssertThrowsError(try keyring.unlock(password: "wrong horse"))
        try keyring.unlock(password: "correct horse")
        XCTAssertEqual(keyring.open(sealed), "vault: A\nsecret")
    }

    /// Deuxième appareil : le mot de passe doit ouvrir les notes déjà synchronisées.
    @MainActor
    func testSetUpOnSecondDeviceChecksExistingNotes() throws {
        let first = VaultKeyring(defaults: UserDefaults(suiteName: "vault-a-\(UUID().uuidString)")!, storesSecrets: false)
        try first.setUp(password: "correct horse", existingSealed: [])
        let sealed = try XCTUnwrap(first.seal("vault: A\nsecret"))

        let second = VaultKeyring(defaults: UserDefaults(suiteName: "vault-b-\(UUID().uuidString)")!, storesSecrets: false)
        XCTAssertThrowsError(try second.setUp(password: "another one", existingSealed: [sealed]))
        try second.setUp(password: "correct horse", existingSealed: [sealed])
        XCTAssertEqual(second.open(sealed), "vault: A\nsecret")
        // Les notes écrites ensuite gardent le même sel : un seul calcul de clé.
        XCTAssertEqual(VaultEnvelope.parse(try XCTUnwrap(second.seal("vault\ny")))?.salt, VaultEnvelope.parse(sealed)?.salt)
    }
}

/// La garantie qui compte : rien d'une note sécurisée n'atteint la base (donc
/// la synchro) en clair. Base en mémoire, coffre sans trousseau.
@MainActor
final class VaultStoreTests: XCTestCase {
    private var store: NoteStore!
    private var keyring: VaultKeyring!

    override func setUp() async throws {
        try DatabaseManager.shared.useInMemoryDatabaseForTesting()
        keyring = VaultKeyring(defaults: UserDefaults(suiteName: "vault-store-\(UUID().uuidString)")!, storesSecrets: false)
        store = NoteStore()
        store.vaultKeyring = keyring
        store.loadNotes()
    }

    private func stored(_ id: Int64?) -> String {
        Note.fetchAll().first { $0.id == id }?.content ?? ""
    }

    private func type(_ text: String, into note: Note) -> Note {
        var edited = store.notes.first { $0.id == note.id }!
        edited.content = text
        store.edit(edited)
        store.flushPendingSaves()
        return store.notes.first { $0.id == note.id }!
    }

    func testTypedSecretIsStoredEncrypted() throws {
        try keyring.setUp(password: "correct horse", existingSealed: [])
        let note = try XCTUnwrap(store.addNote())
        let current = type("vault: Cloudflare\nCF_TOKEN=s3cr3t", into: note)

        XCTAssertFalse(stored(note.id).contains("s3cr3t"))
        XCTAssertTrue(stored(note.id).hasPrefix("vault: Cloudflare\n" + VaultEnvelope.prefix))
        XCTAssertEqual(store.plaintext(of: current), "vault: Cloudflare\nCF_TOKEN=s3cr3t")
        XCTAssertEqual(NoteFormatting.preview(for: current), "Note sécurisée")
    }

    func testLockedVaultHoldsNoteInMemoryOnly() throws {
        let note = try XCTUnwrap(store.addNote())
        _ = type("vault: Banque\ncode 1234", into: note)
        XCTAssertTrue(store.vaultNeedsUnlock)
        XCTAssertFalse(stored(note.id).contains("1234"), "rien en clair sur disque")

        store.loadNotes()  // une synchro recharge la liste : la note retenue survit
        XCTAssertEqual(store.notes.first { $0.id == note.id }?.content, "vault: Banque\ncode 1234")

        try keyring.setUp(password: "correct horse", existingSealed: [])
        store.sealHeldVaultNotes()
        XCTAssertTrue(VaultEnvelope.isSealed(stored(note.id)))
        XCTAssertFalse(stored(note.id).contains("1234"))
    }

    func testErasingHeaderWhileTypingKeepsNoteEncrypted() throws {
        try keyring.setUp(password: "correct horse", existingSealed: [])
        let note = try XCTUnwrap(store.addNote())
        _ = type("vault: Wifi\nmot de passe hunter2", into: note)
        _ = type("vaul: Wifi\nmot de passe hunter2", into: note)
        XCTAssertFalse(stored(note.id).contains("hunter2"))
    }

    func testLeavingVaultModeDecrypts() throws {
        try keyring.setUp(password: "correct horse", existingSealed: [])
        let note = try XCTUnwrap(store.addNote())
        let sealed = type("vault: Liste\npain", into: note)
        store.setMode(.plain, for: sealed)
        XCTAssertEqual(stored(note.id), "pain")
    }

    func testCreatingVaultNoteDirectlyIsEncrypted() throws {
        try keyring.setUp(password: "correct horse", existingSealed: [])
        let created = try XCTUnwrap(store.addNote(content: "vault: Partagé\njeton xyz789"))
        XCTAssertFalse(stored(created.id).contains("xyz789"))
    }

    func testCommandBarRefusesVaultNotes() async throws {
        try keyring.setUp(password: "correct horse", existingSealed: [])
        let note = try XCTUnwrap(store.addNote())
        _ = type("vault: X\nsecret", into: note)
        store.selectNote(id: try XCTUnwrap(note.id))
        await store.aiStore.routeQuestion("combien font 2 + 2")
        XCTAssertTrue(store.aiStatusMessage?.contains("Note sécurisée") == true)
        XCTAssertFalse(stored(note.id).contains("2 + 2"))
    }
}

