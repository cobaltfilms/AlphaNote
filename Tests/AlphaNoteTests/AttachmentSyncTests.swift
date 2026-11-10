import XCTest
@testable import AlphaNote

/// Plan de synchro des pièces jointes : logique pure, sans réseau ni disque.
final class AttachmentSyncTests: XCTestCase {
    private typealias Planner = AttachmentSyncPlanner
    private typealias Item = AttachmentSyncPlanner.Item

    private func note(_ uuid: String, _ content: String, deleted: Bool = false, keyword: String = "") -> Note {
        Note(uuid: uuid, content: content, keyword: keyword, isDeleted: deleted)
    }

    // MARK: Références

    func testReferencesKeepLiveNotesOnly() {
        let notes = [
            note("n1", "Courses\n![audio](att:a.m4a)\n![image](att:b.jpg)"),
            note("n2", "Corbeille\n![audio](att:c.m4a)", deleted: true),
            note("n3", "vault: Secret\n![audio](att:d.m4a)", keyword: VaultEnvelope.keyword),
            note("n4", "Sans pièce jointe")
        ]
        XCTAssertEqual(Planner.references(in: notes), ["n1": ["a.m4a", "b.jpg"]])
    }

    func testReferencesSkipSealedVaultContent() {
        let sealed = note("n1", "vault\n\(VaultEnvelope.prefix)abc\n![audio](att:a.m4a)")
        XCTAssertTrue(sealed.isVault)
        XCTAssertTrue(Planner.references(in: [sealed]).isEmpty)
    }

    func testReferencesDropDuplicatesAndUnsafeNames() {
        let notes = [note("n1", "![audio](att:a.m4a)\n![audio](att:a.m4a)\n![image](att:..)\n![image](att:.cache)\n![image](att:.)")]
        XCTAssertEqual(Planner.references(in: notes), ["n1": ["a.m4a"]])
    }

    func testReferencesSkipUnsafeNoteUUID() {
        let notes = [note("../autre", "![audio](att:a.m4a)"), note("", "![audio](att:b.m4a)")]
        XCTAssertTrue(Planner.references(in: notes).isEmpty)
    }

    // MARK: Noms

    func testSafeNames() {
        XCTAssertTrue(Planner.isSafeName("3f2a-9c.m4a"))
        XCTAssertTrue(Planner.isSafeName("photo_1.JPG"))
        for bad in ["", ".", "..", ".part", "a/b.m4a", "a\\b", "a b.m4a", "é.m4a", "a.m4a\n"] {
            XCTAssertFalse(Planner.isSafeName(bad), bad)
        }
    }

    func testSafeNoteUUIDs() {
        XCTAssertTrue(Planner.isSafeNoteUUID("0b6e1d3c-1111-4222-8333-444455556666"))
        for bad in ["", ".", "..", "a/b", "a.b", "a b"] {
            XCTAssertFalse(Planner.isSafeNoteUUID(bad), bad)
        }
    }

    // MARK: Plan

    func testPlanUploadsLocalOnlyAndDownloadsRemoteOnly() {
        let plan = Planner.plan(
            references: ["n1": ["here.m4a", "there.m4a", "both.jpg", "nowhere.m4a"]],
            local: ["n1": ["here.m4a", "both.jpg"]],
            remote: ["n1": ["there.m4a", "both.jpg"]]
        )
        XCTAssertEqual(plan.uploads, [Item(noteUUID: "n1", name: "here.m4a")])
        XCTAssertEqual(plan.downloads, [Item(noteUUID: "n1", name: "there.m4a")])
    }

    func testPlanIgnoresUnreferencedFiles() {
        // Fichier retiré du texte, ou d'une note absente des références
        // (supprimée, sécurisée) : ni envoyé, ni téléchargé, ni supprimé.
        let plan = Planner.plan(
            references: ["n1": ["a.m4a"]],
            local: ["n1": ["a.m4a", "orphelin.m4a"], "n2": ["x.m4a"]],
            remote: ["n1": ["a.m4a", "ancien.jpg"], "n3": ["y.m4a"]]
        )
        XCTAssertTrue(plan.isEmpty)
    }

    func testPlanWithNoRemoteFolderUploadsEverythingLocal() {
        let plan = Planner.plan(
            references: ["n2": ["b.m4a"], "n1": ["a.m4a", "manquant.m4a"]],
            local: ["n1": ["a.m4a"], "n2": ["b.m4a"]],
            remote: [:]
        )
        XCTAssertEqual(plan.uploads, [Item(noteUUID: "n1", name: "a.m4a"), Item(noteUUID: "n2", name: "b.m4a")])
        XCTAssertTrue(plan.downloads.isEmpty)
    }

    func testPlanNeverEscapesTheNoteFolder() {
        let plan = Planner.plan(
            references: ["n1": ["..", ".", ".secret", "a/b.m4a", "ok.m4a"], "../n2": ["x.m4a"], "": ["y.m4a"]],
            local: ["n1": ["..", "."], "../n2": ["x.m4a"]],
            remote: ["n1": [".secret", "a/b.m4a", "ok.m4a"], "": ["y.m4a"]]
        )
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertEqual(plan.downloads, [Item(noteUUID: "n1", name: "ok.m4a")])
    }

    func testPlanFromNotesEndToEnd() {
        let notes = [
            note("n1", "Mémo\n![audio](att:a.m4a)"),
            note("n2", "Supprimée\n![audio](att:b.m4a)", deleted: true),
            note("n3", "vault\n![audio](att:c.m4a)", keyword: VaultEnvelope.keyword)
        ]
        let plan = Planner.plan(
            references: Planner.references(in: notes),
            local: ["n2": ["b.m4a"], "n3": ["c.m4a"]],
            remote: ["n1": ["a.m4a"], "n2": [], "n3": []]
        )
        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertEqual(plan.downloads, [Item(noteUUID: "n1", name: "a.m4a")])
    }

    // MARK: Liste WebDAV

    func testRemoteEntryParsing() {
        let base = "/remote.php/dav/files/paul/AlphaNote/attachments/"
        XCTAssertNil(Planner.remoteEntry(fromHref: base))
        XCTAssertEqual(Planner.remoteEntry(fromHref: base + "n1/"), .init(noteUUID: "n1", name: nil))
        XCTAssertEqual(Planner.remoteEntry(fromHref: base + "n1/a.m4a"), .init(noteUUID: "n1", name: "a.m4a"))
        XCTAssertEqual(
            Planner.remoteEntry(fromHref: "https://cloud.example.org" + base + "n1/a.m4a"),
            .init(noteUUID: "n1", name: "a.m4a")
        )
        // Fichier posé directement dans `attachments`, sous-dossier, nom douteux, autre dossier.
        XCTAssertNil(Planner.remoteEntry(fromHref: base + "perdu.m4a"))
        XCTAssertNil(Planner.remoteEntry(fromHref: base + "n1/sous/a.m4a"))
        XCTAssertNil(Planner.remoteEntry(fromHref: base + "n1/sous/"))
        XCTAssertNil(Planner.remoteEntry(fromHref: base + "n1/a%20b.m4a"))
        XCTAssertNil(Planner.remoteEntry(fromHref: base + "n1/%2E%2E"))
        XCTAssertNil(Planner.remoteEntry(fromHref: "/remote.php/dav/files/paul/AlphaNote/notes/n1.json"))
    }
}
