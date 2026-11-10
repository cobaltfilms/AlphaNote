import XCTest
@testable import AlphaNote

/// Modes de rangement de la liste (forme, mois, tri à faire) et rangement par
/// JEV. Mêmes cas que NoteOrganizerTest.kt côté Android.
final class OrganizerTests: XCTestCase {

    private func note(_ content: String, uuid: String = UUID().uuidString, created: TimeInterval = 1_700_000_000, pinned: Bool = false) -> Note {
        var note = Note(uuid: uuid, content: content, isPinned: pinned)
        note.createdAt = Date(timeIntervalSince1970: created)
        return note
    }

    // MARK: - Forme

    func testShapes() {
        XCTAssertEqual(NoteOrganizer.shape(of: note("timer\ncountdown 5:00")), .timer)
        XCTAssertEqual(NoteOrganizer.shape(of: note("math\n2+2=")), .math)
        XCTAssertEqual(NoteOrganizer.shape(of: note("list\npain\nlait")), .list)
        XCTAssertEqual(NoteOrganizer.shape(of: note("ls -la /var/log\ncd /etc/nginx")), .terminal)
        XCTAssertEqual(NoteOrganizer.shape(of: note("À lire https://example.org/article")), .link)
        XCTAssertEqual(NoteOrganizer.shape(of: note("pain\nlait\noeufs\nbeurre")), .list)
        XCTAssertEqual(NoteOrganizer.shape(of: note("Rappeler Jeanne")), .oneLine)
        XCTAssertEqual(NoteOrganizer.shape(of: note("Rappeler Jeanne\nthème : Vie perso")), .oneLine)
        XCTAssertEqual(NoteOrganizer.shape(of: note("Cher Luc,\nmerci pour ta lettre, elle m'a fait très plaisir et je voulais te répondre.")), .shortText)
        XCTAssertEqual(NoteOrganizer.shape(of: note(String(repeating: "Une phrase assez longue pour remplir. ", count: 60))), .longText)
    }

    // MARK: - Tri à faire

    func testDuplicatesKeepTheOldestNote() {
        let old = note("Recette de la dinde aux marrons, version de mamie", uuid: "old", created: 100)
        let copy = note("recette de la  DINDE aux marrons, version de mamie", uuid: "copy", created: 200)
        let other = note("Tout autre chose, sans aucun rapport avec la dinde", uuid: "other", created: 300)
        XCTAssertEqual(NoteOrganizer.duplicateUUIDs([copy, other, old]), ["copy"])
    }

    func testTriageReasons() {
        XCTAssertEqual(NoteOrganizer.triageReason(for: note("timer\ncountdown 5:00"), duplicates: []), .timer)
        XCTAssertEqual(NoteOrganizer.triageReason(for: note("https://example.org"), duplicates: []), .link)
        XCTAssertEqual(NoteOrganizer.triageReason(for: note("ZR701G87"), duplicates: []), .oneLine)
        XCTAssertEqual(NoteOrganizer.triageReason(for: note("Un vrai texte", uuid: "d"), duplicates: ["d"]), .duplicate)
        // Épinglée, ou porteuse d'une note vocale : jamais proposée au tri.
        XCTAssertNil(NoteOrganizer.triageReason(for: note("ZR701G87", pinned: true), duplicates: []))
        XCTAssertNil(NoteOrganizer.triageReason(for: note("Mémo\n![audio](att:a.m4a)"), duplicates: []))
        XCTAssertNil(NoteOrganizer.triageReason(for: note("pain\nlait\noeufs\nbeurre"), duplicates: []))
    }

    func testTriageSectionsEndWithTheRest() {
        let notes = [note("https://example.org", uuid: "l"), note("pain\nlait\noeufs\nbeurre", uuid: "k"), note("timer", uuid: "t")]
        let sections = NoteOrganizer.sections(notes, grouping: .triage, themes: [:])
        XCTAssertEqual(sections.map(\.title), ["Minuteurs", "Liens seuls", NoteOrganizer.keepTitle])
        XCTAssertEqual(sections.last?.noteUUIDs, ["k"])
    }

    // MARK: - Sections

    func testMonthSectionsAreNewestFirst() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let notes = [
            note("a", uuid: "a", created: 1_600_000_000), // septembre 2020
            note("b", uuid: "b", created: 1_700_000_000), // novembre 2023
            note("c", uuid: "c", created: 1_600_100_000),
        ]
        let sections = NoteOrganizer.sections(notes, grouping: .month, themes: [:], calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["novembre 2023", "septembre 2020"])
        XCTAssertEqual(sections[1].noteUUIDs, ["a", "c"])
    }

    func testShapeSectionsFollowTheShapeOrder() {
        let notes = [note("Rappeler Jeanne", uuid: "o"), note("ls -la /var/log\ncd /etc/nginx", uuid: "t")]
        XCTAssertEqual(NoteOrganizer.sections(notes, grouping: .shape, themes: [:]).map(\.title), ["Commandes et code", "Une seule ligne"])
        XCTAssertEqual(NoteOrganizer.sections(notes, grouping: .recent, themes: [:]).map(\.noteUUIDs), [["o", "t"]])
        XCTAssertEqual(NoteOrganizer.sections(notes, grouping: .theme, themes: ["o": "Vie perso"]).map(\.title), ["Vie perso", NoteThemes.none])
    }

    // MARK: - Rangement par JEV

    private struct FakeTransport: JEVTransport {
        let reply: @Sendable ([String]) throws -> [[String: Any]]
        func post(url: URL, body: Data, delaiMs: Int, headers: [String: String]) async throws -> Data {
            let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let contexts = sent?["contexts"] as? [String] ?? []
            return try JSONSerialization.data(withJSONObject: ["results": try reply(contexts).map { ["decision": $0] }])
        }
    }

    private let config = JEVConfig(url: "http://jev.test", delaiMs: 1000)

    func testCandidatesSkipVaultThemedAndEmptyNotes() {
        let notes = [
            note("Une note à ranger", uuid: "a"),
            note("Déjà rangée\nthème : Cuisine", uuid: "b"),
            note("vault\nsecret", uuid: "c"),
            note("  \n", uuid: "d"),
        ]
        XCTAssertEqual(ThemeClassificationFeature.candidates(notes).map(\.uuid), ["a"])
    }

    func testFragmentIsTitleAndStartOfText() {
        var long = note("Titre\n" + String(repeating: "x", count: 2000) + "\nthème : A\n![audio](att:a.m4a)")
        long.title = "Mon titre"
        let fragment = ThemeClassificationFeature.fragment(for: long)
        XCTAssertTrue(fragment.hasPrefix("Mon titre\nTitre\nxxx"))
        XCTAssertFalse(fragment.contains("thème"))
        XCTAssertFalse(fragment.contains("att:"))
        XCTAssertLessThanOrEqual(fragment.count, "Mon titre\n".count + ThemeClassificationFeature.excerptLength)
    }

    func testSchemaIsAcceptedByTheClient() {
        XCTAssertNil(JEVClient.verifierSchema(ThemeClassificationFeature.schema))
    }

    func testClassifyMapsShelvesAndLeavesTheRestUnsorted() async {
        let notes = (0..<10).map { note("Note numéro \($0)", uuid: "n\($0)") }
        let transport = FakeTransport { contexts in
            contexts.map { text in
                if text.hasSuffix("0") { return ["rayon": "cuisine"] }
                if text.hasSuffix("1") { return ["rayon": "fourre_tout"] }
                if text.hasSuffix("2") { return ["rayon": "inconnu"] }
                return ["rayon": "informatique"]
            }
        }
        let outcome = await ThemeClassificationFeature().classify(notes, config: config, transport: transport)
        XCTAssertEqual(outcome.themes["n0"], "Cuisine")
        XCTAssertEqual(outcome.themes["n3"], "Informatique")
        XCTAssertNil(outcome.themes["n1"])
        XCTAssertEqual(outcome.unsorted, 1)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertEqual(outcome.themes.count, 8)
        XCTAssertNil(outcome.error)
    }

    func testServerErrorStopsAndKeepsWhatWasDecided() async {
        let notes = (0..<12).map { note("Note numéro \($0)", uuid: "n\($0)") }
        let calls = Counter()
        let transport = FakeTransport { contexts in
            if calls.next() > 1 { throw JEVTransportError.http(status: 500) }
            return contexts.map { _ in ["rayon": "cuisine"] }
        }
        let outcome = await ThemeClassificationFeature().classify(notes, config: config, transport: transport)
        XCTAssertEqual(outcome.themes.count, ThemeClassificationFeature.batchSize)
        XCTAssertEqual(outcome.failed, 12 - ThemeClassificationFeature.batchSize)
        XCTAssertNotNil(outcome.error)
    }

    private final class Counter: @unchecked Sendable {
        private var value = 0
        private let lock = NSLock()
        func next() -> Int { lock.withLock { value += 1; return value } }
    }
}
