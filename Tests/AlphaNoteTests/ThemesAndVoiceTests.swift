import XCTest
@testable import AlphaNote

/// Thèmes (ligne « thème : … », classement local) et notes vocales (références
/// audio dans le texte). Mêmes cas que NoteThemesTest.kt côté Android.
final class ThemesAndVoiceTests: XCTestCase {

    // MARK: - Ligne de thème

    func testExplicitThemeIsReadFromItsLine() {
        XCTAssertEqual(NoteThemes.explicit(in: "Tarte\nthème : Recettes"), "Recettes")
        XCTAssertEqual(NoteThemes.explicit(in: "Theme: voyage\nBillets"), "voyage")
        XCTAssertEqual(NoteThemes.explicit(in: "x\nTHÈME :  Deux   mots "), "Deux mots")
        XCTAssertNil(NoteThemes.explicit(in: "Le thème du film est sombre"))
        XCTAssertNil(NoteThemes.explicit(in: "thème :   "))
    }

    func testLastThemeLineWins() {
        XCTAssertEqual(NoteThemes.explicit(in: "thème : A\ntexte\nthème : B"), "B")
    }

    func testSettingThemeReplacesAndRemoves() {
        XCTAssertEqual(NoteThemes.settingTheme("Travail", in: "Réunion"), "Réunion\nthème : Travail")
        XCTAssertEqual(NoteThemes.settingTheme("Perso", in: "Réunion\nthème : Travail"), "Réunion\nthème : Perso")
        XCTAssertEqual(NoteThemes.settingTheme(nil, in: "Réunion\nthème : Travail"), "Réunion")
        XCTAssertEqual(NoteThemes.settingTheme("  ", in: "Réunion\nthème : Travail"), "Réunion")
    }

    func testThemeLineStaysBeforeTrailingAttachments() {
        let content = "Repérage\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        XCTAssertEqual(
            NoteThemes.settingTheme("Tournage", in: content),
            "Repérage\nthème : Tournage\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        )
    }

    func testThemeKeyIgnoresCaseAndAccents() {
        XCTAssertEqual(NoteThemes.key("Écoles"), NoteThemes.key("ecoles"))
        XCTAssertNotEqual(NoteThemes.key("Travail"), NoteThemes.key("Voyage"))
    }

    func testSectionsAreAlphabeticalWithNoThemeLast() {
        let sections = NoteThemes.sections(
            noteUUIDs: ["1", "2", "3", "4", "5"],
            themes: ["1": "Voyage", "3": "Recettes", "4": "voyage", "5": "Écoles"]
        )
        XCTAssertEqual(sections.map(\.theme), ["Écoles", "Recettes", "Voyage", NoteThemes.none])
        XCTAssertEqual(sections[2].noteUUIDs, ["1", "4"])
        XCTAssertEqual(sections[3].noteUUIDs, ["2"])
    }

    func testPreviewHidesThemeLine() {
        let note = Note(content: "Tarte aux pommes\npommes, beurre\nthème : Recettes")
        XCTAssertEqual(NoteFormatting.preview(for: note), "pommes, beurre")
    }

    // MARK: - Classement

    func testTokensDropAccentsPluralsAndStopWords() {
        XCTAssertEqual(ThemeSorter.tokens("Les gâteaux et l'huile d'olive"), ["gateau", "huile", "olive"])
    }

    func testCatalogRecognisesCommonThemes() {
        XCTAssertEqual(ThemeSorter.catalogTheme(title: "", content: "Recette gâteau\nau chocolat"), "Cuisine")
        XCTAssertEqual(ThemeSorter.catalogTheme(title: "", content: "list\npain\nfromage\nyaourt"), "Cuisine")
        XCTAssertEqual(ThemeSorter.catalogTheme(title: "", content: "Vol Bruxelles Lisbonne\nhôtel réservé, passeport à renouveler"), "Vie perso")
        XCTAssertNil(ThemeSorter.catalogTheme(title: "", content: "Rappeler Jeanne demain matin"))
    }

    func testExplicitThemeIsKeptAndTeachesSimilarNotes() {
        let items = [
            ThemeSorter.Item(uuid: "a", title: "", content: "Repérage décor usine\ncomédiens à confirmer\nthème : Tournage Lyon", keyword: ""),
            ThemeSorter.Item(uuid: "b", title: "", content: "Décor du hangar, repérage jeudi avec les comédiens\nthème : Tournage Lyon", keyword: ""),
            ThemeSorter.Item(uuid: "c", title: "", content: "Repérage du second décor, comédiens prévenus", keyword: ""),
            ThemeSorter.Item(uuid: "d", title: "", content: "Rappeler Jeanne demain matin", keyword: ""),
        ]
        let themes = ThemeSorter.assign(items)
        XCTAssertEqual(themes["a"], "Tournage Lyon")
        XCTAssertEqual(themes["c"], "Tournage Lyon")
        XCTAssertNil(themes["d"])
    }

    func testOneCatalogWordIsNotEnough() {
        XCTAssertNil(ThemeSorter.catalogTheme(title: "", content: "IKEA"))
        XCTAssertNil(ThemeSorter.catalogTheme(title: "", content: "Appeler la banque"))
        XCTAssertEqual(ThemeSorter.catalogTheme(title: "", content: "Banque\nvirement du loyer"), "Argent & papiers")
    }

    func testTerminalDumpGoesToTech() {
        let log = "Jul 20 18:47:36 host kernel: [ 12.345] usb 1-1: new device\n$ sudo dmesg --follow\necho 1 > /sys/bus/pci/rescan"
        XCTAssertTrue(ThemeSorter.looksLikeCode(log))
        XCTAssertFalse(ThemeSorter.looksLikeCode("Cher Luc,\nmerci pour ta lettre (et pour le livre).\nÀ bientôt"))
        let themes = ThemeSorter.assign([ThemeSorter.Item(uuid: "a", title: "", content: "ls -la /var/log\ncd /etc/nginx", keyword: "")])
        XCTAssertEqual(themes["a"], "Informatique")
    }

    func testCodeNoteFallsBackToTechTheme() {
        let themes = ThemeSorter.assign([ThemeSorter.Item(uuid: "a", title: "", content: "code\nfoo(bar)", keyword: "code")])
        XCTAssertEqual(themes["a"], "Informatique")
    }

    func testAssignIsDeterministic() {
        let items = (0..<40).map { index in
            ThemeSorter.Item(uuid: "\(index)", title: "", content: index % 2 == 0 ? "Recette tarte \(index)\nfarine beurre" : "Facture banque \(index)\nvirement", keyword: "")
        }
        XCTAssertEqual(ThemeSorter.assign(items), ThemeSorter.assign(items))
        XCTAssertEqual(ThemeSorter.assign(items)["0"], "Cuisine")
        XCTAssertEqual(ThemeSorter.assign(items)["1"], "Argent & papiers")
    }

    // MARK: - Notes vocales

    func testAudioReferencesAreSeparatedFromImages() {
        let content = "Texte\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        XCTAssertTrue(NoteAttachments.isAudio("b.m4a"))
        XCTAssertTrue(NoteAttachments.isAudio("B.WAV"))
        XCTAssertFalse(NoteAttachments.isAudio("a.jpg"))
        XCTAssertEqual(NoteAttachments.imageNames(in: content), ["a.jpg"])
        XCTAssertEqual(NoteAttachments.audioNames(in: content), ["b.m4a"])
        XCTAssertEqual(NoteAttachments.markdown("b.m4a"), "![audio](att:b.m4a)")
        XCTAssertEqual(NoteAttachments.markdown("a.jpg"), "![image](att:a.jpg)")
        XCTAssertTrue(NoteAttachments.isAudioLine("![audio](att:b.m4a)"))
        XCTAssertFalse(NoteAttachments.isAudioLine("![image](att:a.jpg)"))
    }

    func testEditorRoundTripKeepsAudioReferences() {
        let content = "Texte\n![image](att:a.jpg)\n![audio](att:b.m4a)"
        // iOS / Android : toutes les pièces jointes sont cachées.
        XCTAssertEqual(NoteAttachments.withImages(NoteAttachments.visibleText(content), content: content), content)
        // macOS : seules les notes vocales le sont.
        XCTAssertEqual(NoteAttachments.textHidingAudio(content), "Texte\n![image](att:a.jpg)")
        XCTAssertEqual(NoteAttachments.withAudio(NoteAttachments.textHidingAudio(content), content: content), content)
    }

    func testAddingVoiceNote() {
        XCTAssertEqual(NoteAttachments.addingVoiceNote(to: "", audioName: "a.m4a", transcript: " Bonjour "), "Bonjour\n![audio](att:a.m4a)")
        XCTAssertEqual(
            NoteAttachments.addingVoiceNote(to: "Idée\nthème : Travail\n![image](att:i.jpg)", audioName: "a.m4a", transcript: "Appeler le client"),
            "Idée\n\nAppeler le client\nthème : Travail\n![image](att:i.jpg)\n![audio](att:a.m4a)"
        )
        XCTAssertEqual(NoteAttachments.addingVoiceNote(to: "Idée", audioName: "a.m4a", transcript: ""), "Idée\n![audio](att:a.m4a)")
    }

    func testRemovingReferenceKeepsTranscript() {
        let content = "Idée\n\nAppeler le client\n![audio](att:a.m4a)\n![audio](att:b.m4a)"
        XCTAssertEqual(NoteAttachments.removingReference("a.m4a", from: content), "Idée\n\nAppeler le client\n![audio](att:b.m4a)")
    }

    func testClockFormat() {
        XCTAssertEqual(VoiceNotePlayer.clock(0), "0:00")
        XCTAssertEqual(VoiceNotePlayer.clock(75.4), "1:15")
    }

    // MARK: - Import Apple Notes (macOS seulement)

    #if os(macOS)
    func testAppleNotesFolderBecomesTheme() {
        XCTAssertEqual(NoteImportService.theme(fromFolder: "Recettes"), "Recettes")
        XCTAssertNil(NoteImportService.theme(fromFolder: "Notes"))
        XCTAssertNil(NoteImportService.theme(fromFolder: nil))
        XCTAssertTrue(NoteImportService.isTrashFolder("Suppressions récentes"))
        XCTAssertTrue(NoteImportService.isTrashFolder("Recently Deleted"))
        XCTAssertFalse(NoteImportService.isTrashFolder("Recettes"))
    }

    func testImportKeepsThemeAndDatesAndCompletesEarlierImports() throws {
        try DatabaseManager.shared.useInMemoryDatabaseForTesting()
        let service = NoteImportService.shared
        let created = Date(timeIntervalSince1970: 1_600_000_000)

        // Ancien import : tout à plat, daté du jour de l'import.
        var report = service.importEntries([ImportEntry(title: "Tarte", content: "Tarte\npommes")], source: "Test")
        XCTAssertEqual(report.imported, 1)

        // Nouvel import de la même note, avec dossier et date : elle est complétée, pas dupliquée.
        let entries = [
            ImportEntry(title: "Tarte", content: "Tarte\npommes", theme: "Recettes", createdAt: created, updatedAt: created),
            ImportEntry(title: "Lisbonne", content: "Lisbonne\nvol 12 mai", theme: "Voyage", createdAt: created, updatedAt: created),
        ]
        report = service.importEntries(entries, source: "Test")
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(report.skippedDuplicates, 0)

        let notes = Note.fetchAll()
        XCTAssertEqual(notes.count, 2)
        let tarte = try XCTUnwrap(notes.first { $0.content.hasPrefix("Tarte") })
        XCTAssertEqual(NoteThemes.explicit(in: tarte.content), "Recettes")
        XCTAssertEqual(tarte.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)
        let lisbonne = try XCTUnwrap(notes.first { $0.content.hasPrefix("Lisbonne") })
        XCTAssertEqual(lisbonne.content, "Lisbonne\nvol 12 mai\nthème : Voyage")
        XCTAssertEqual(lisbonne.title, "")
        XCTAssertEqual(lisbonne.createdAt.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 1)

        // Troisième passage : plus rien à faire.
        report = service.importEntries(entries, source: "Test")
        XCTAssertEqual(report.imported, 0)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(report.skippedDuplicates, 2)
    }
    #endif
}
