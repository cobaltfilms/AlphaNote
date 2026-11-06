import XCTest
@testable import AlphaNote

final class RemindersTests: XCTestCase {

    private func date(_ stamp: String) -> Date {
        Reminders.formatter().date(from: stamp)!
    }

    func testParsesEachLineAsOneReminder() {
        let content = "courses\nrappel 2026-11-10 18:00 : notification, sonnerie\nrappel 2026-11-11 09:30 : vibration"
        let reminders = Reminders.parse(content)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders[0].at, date("2026-11-10 18:00"))
        XCTAssertEqual(reminders[0].kinds, [.notification, .sonnerie])
        XCTAssertEqual(reminders[1].kinds, [.vibration])
    }

    func testIgnoresMalformedLines() {
        let content = """
        rappel 2026-13-40 18:00 : sonnerie
        rappel 2026-11-10 18h : sonnerie
        rappel 2026-11-10 18:00 : clignotant
        rappel 2026-11-10 18:00 :
        rappel 2026-11-10 18:00 : sonnerie
        """
        let reminders = Reminders.parse(content)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.kinds, [.sonnerie])
    }

    func testUnknownKindsAreDroppedButValidOnesKept() {
        let reminders = Reminders.parse("rappel 2026-11-10 18:00 : notification, clignotant, VIBRATION")
        XCTAssertEqual(reminders.first?.kinds, [.notification, .vibration])
    }

    func testKeywordIsCaseInsensitive() {
        XCTAssertEqual(Reminders.parse("  Rappel   2026-11-10 18:00  :  sonnerie  ").count, 1)
    }

    func testLineWritesKindsInFixedOrder() {
        let line = Reminders.line(at: date("2026-11-10 18:00"), kinds: [.vibration, .notification, .sonnerie])
        XCTAssertEqual(line, "rappel 2026-11-10 18:00 : notification, sonnerie, vibration")
    }

    func testRoundTripsThroughParse() {
        let at = date("2026-11-10 18:00")
        let kinds: Set<ReminderKind> = [.sonnerie, .vibration]
        let parsed = Reminders.parse(Reminders.line(at: at, kinds: kinds))
        XCTAssertEqual(parsed, [Reminder(at: at, kinds: kinds)])
    }

    func testWithReminderAppendsOnItsOwnLine() {
        let text = Reminders.withReminder("liste de courses", at: date("2026-11-10 18:00"), kinds: [.notification])
        XCTAssertEqual(text, "liste de courses\nrappel 2026-11-10 18:00 : notification")
    }

    func testWithReminderKeepsExistingTrailingNewline() {
        let text = Reminders.withReminder("texte\n", at: date("2026-11-10 18:00"), kinds: [.notification])
        XCTAssertEqual(text, "texte\nrappel 2026-11-10 18:00 : notification")
    }

    func testWithReminderOnEmptyNoteHasNoLeadingNewline() {
        let text = Reminders.withReminder("", at: date("2026-11-10 18:00"), kinds: [.sonnerie])
        XCTAssertTrue(text.hasPrefix("rappel "))
    }
}
