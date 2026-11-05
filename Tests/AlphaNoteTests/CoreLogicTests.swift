import XCTest
@testable import AlphaNote

/// Logique métier pure : hachage des embeddings, détection de mode, routage
/// par mots-clés, formatage des listes, minuteur, raccourci global.
final class CoreLogicTests: XCTestCase {

    // MARK: - Embeddings

    func testHashEmbeddingIsStableAndNormalised() {
        let a = HashEmbedding.embed(text: "Courses : tomates, pâtes, huile")
        let b = HashEmbedding.embed(text: "Courses : tomates, pâtes, huile")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, HashEmbedding.dimensions)
        XCTAssertEqual(sqrt(a.reduce(0) { $0 + $1 * $1 }), 1, accuracy: 1e-9)
        // Valeur FNV-1a 64 bits de référence pour une chaîne vide.
        XCTAssertEqual(HashEmbedding.fnv1a64(""), 0xcbf29ce484222325)
        XCTAssertEqual(HashEmbedding.fnv1a64("a"), 0xaf63dc4c8601ec8c)
    }

    func testCosineSimilarityOrdersRelatedTexts() {
        let query = HashEmbedding.embed(text: "liste de courses tomates")
        let near = HashEmbedding.embed(text: "courses : tomates, pain")
        let far = HashEmbedding.embed(text: "réunion budget trimestriel")
        XCTAssertGreaterThan(HashEmbedding.cosineSimilarity(query, near), HashEmbedding.cosineSimilarity(query, far))
        XCTAssertEqual(HashEmbedding.cosineSimilarity([], []), 0)
    }

    // MARK: - Détection de mode

    func testKeywordDetection() {
        XCTAssertEqual(Note(content: "math\n2+2=").keyword, "math")
        XCTAssertEqual(Note(content: "List: Courses\npain").keyword, "list")
        XCTAssertEqual(Note(content: "  timer  \ncountdown 5:00").keyword, "timer")
        XCTAssertEqual(Note(content: "mathematics are fun").keyword, "")
        XCTAssertEqual(Note(content: "").keyword, "")
    }

    func testEffectiveTitle() {
        XCTAssertEqual(Note(content: "list: Courses\npain").effectiveTitle, "Courses")
        XCTAssertEqual(Note(content: "\n\nPremière ligne utile").effectiveTitle, "Première ligne utile")
        var named = Note(content: "math\n1+1=")
        named.title = "Budget"
        XCTAssertEqual(named.effectiveTitle, "Budget")
    }

    // MARK: - Routage mots-clés

    func testKeywordIntentRouter() {
        XCTAssertEqual(KeywordIntentRouter.classify("minuteur 25 minutes", noteKeyword: nil), .timer)
        XCTAssertEqual(KeywordIntentRouter.classify("12 * 8", noteKeyword: nil), .math)
        XCTAssertEqual(KeywordIntentRouter.classify("10 km to mi", noteKeyword: nil), .math)
        XCTAssertEqual(KeywordIntentRouter.classify("courses : pain, lait, œufs", noteKeyword: nil), .list)
        XCTAssertEqual(KeywordIntentRouter.classify("une pensée", noteKeyword: nil), .plain)
        XCTAssertEqual(KeywordIntentRouter.classify("n'importe quoi", noteKeyword: "list"), .list)
    }

    func testTimerRequestParsing() {
        let twentyFive = KeywordIntentRouter.parseTimerRequest("minuteur 25 min")
        XCTAssertEqual(twentyFive?.type, .countdown)
        XCTAssertEqual(twentyFive?.totalSeconds, 25 * 60)

        let mixed = KeywordIntentRouter.parseTimerRequest("1 h 30 min")
        XCTAssertEqual(mixed?.totalSeconds, 5400)

        let byDefault = KeywordIntentRouter.parseTimerRequest("lance le minuteur")
        XCTAssertEqual(byDefault?.type, .countdown)
        XCTAssertEqual(byDefault?.totalSeconds, 600, "durée par défaut")

        let wakeUp = KeywordIntentRouter.parseTimerRequest("réveille-moi à 7h30")
        XCTAssertEqual(wakeUp?.type, .alarm)
        XCTAssertEqual(wakeUp?.totalSeconds, 7 * 3600 + 30 * 60)
        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("alarme à 14h")?.totalSeconds, 14 * 3600)
        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("sonne à 18:15")?.type, .alarm)
        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("alarme à 7 h du soir")?.totalSeconds, 19 * 3600)
        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("rappelle-moi à midi")?.totalSeconds, 12 * 3600)
        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("alarme dans 10 minutes")?.type, .countdown, "« dans » = une durée")
        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("mets un minuteur pour 2h")?.type, .countdown)
        XCTAssertEqual(KeywordIntentRouter.classify("réveille-moi à 6h45", noteKeyword: nil), .timer)
        XCTAssertEqual(KeywordIntentRouter.classify("sonne à 18h15", noteKeyword: nil), .timer)

        XCTAssertEqual(KeywordIntentRouter.parseTimerRequest("lance un chrono")?.type, .stopwatch)
    }

    // MARK: - Listes

    func testListFormatterSplitsCommasAndKeepsHeadings() {
        let normalized = ListModeFormatter.normalizeForListMode(content: "pain, lait\n# Frais\nbeurre", forceListHeader: true)
        XCTAssertEqual(normalized, "list\npain\nlait\n# Frais\nbeurre")
        XCTAssertTrue(ListModeFormatter.isListHeader("List: Courses"))
        XCTAssertTrue(ListModeFormatter.isComment("  // note"))
        XCTAssertTrue(ListModeFormatter.isHeading("## Titre"))
    }

    // MARK: - Minuteur

    @MainActor
    func testTimerSessionCountsDownAndRestoresFromSnapshot() {
        let session = TimerSession(id: "test", mode: .countdown, targetDuration: 90)
        XCTAssertEqual(session.displayTime, "01:30")
        XCTAssertEqual(session.state, .stopped)

        session.start()
        XCTAssertEqual(session.state, .running)
        session.pause()
        XCTAssertEqual(session.state, .paused)

        var snapshot = session.snapshot()
        XCTAssertEqual(snapshot.mode, .countdown)

        // Une session « en cours » depuis plus longtemps que sa durée est terminée à la restauration.
        snapshot = TimerSession.Snapshot(mode: .countdown, state: .running, targetDuration: 10, elapsed: 0,
                                         runStartDate: Date().addingTimeInterval(-60))
        let restored = TimerSession(id: "restored", mode: .countdown, targetDuration: 10)
        restored.restore(from: snapshot)
        XCTAssertEqual(restored.state, .finished)
        XCTAssertEqual(restored.remaining, 0)
        restored.reset()

        XCTAssertEqual(TimerSession.format(3725), "1:02:05")
        XCTAssertEqual(TimerSession.Mode(keyword: "chronomètre"), .stopwatch)
        XCTAssertNil(TimerSession.Mode(keyword: "rien"))
    }

    // MARK: - Raccourci global

    #if os(macOS)
    func testHotkeyDescription() {
        let aKey = HotkeySettings.keyCode(forCharacter: "a") ?? 0
        XCTAssertEqual(HotkeySettings.describe(keyCode: aKey, modifiers: [.option]), "⌥A")
        XCTAssertEqual(HotkeySettings.describe(keyCode: 49, modifiers: [.command, .shift]), "⇧⌘␣")
        XCTAssertEqual(HotkeySettings.describe(keyCode: 122, modifiers: []), "F1")
    }
    #endif

    // MARK: - Sync : baseline ETag

    func testUnchangedRemoteDoesNotTriggerUploadUnlessLocalEdited() {
        let synced = Date(timeIntervalSince1970: 1000)
        var note = Note(uuid: "u1", content: "a", updatedAt: synced)
        note.lastSyncedAt = synced
        let dto = CloudNoteDTO(note: note)
        XCTAssertFalse(SyncEngine.shouldUploadLocal(local: dto, remote: dto, lastSyncedAt: synced))

        var edited = note
        edited.updatedAt = synced.addingTimeInterval(10)
        let editedDTO = CloudNoteDTO(note: edited)
        XCTAssertTrue(SyncEngine.shouldUploadLocal(local: editedDTO, remote: dto, lastSyncedAt: synced))
    }

    func testShortDateBuckets() {
        var components = DateComponents(year: 2026, month: 10, day: 23, hour: 15, minute: 4)
        components.calendar = Calendar.current
        let now = components.date!
        XCTAssertEqual(NoteFormatting.shortDate(now.addingTimeInterval(-3600), now: now), "14:04")
        XCTAssertEqual(NoteFormatting.shortDate(now.addingTimeInterval(-86400), now: now), "hier")
        XCTAssertEqual(NoteFormatting.shortDate(now.addingTimeInterval(-3 * 86400), now: now), "mar.")
        XCTAssertEqual(NoteFormatting.shortDate(now.addingTimeInterval(-40 * 86400), now: now), "13 sept.")
        XCTAssertEqual(NoteFormatting.shortDate(now.addingTimeInterval(-400 * 86400), now: now), "sept. 2025")
    }
}
