import XCTest
@testable import AlphaNote

@MainActor
final class TimerLineTests: XCTestCase {

    func testReplacesExistingLineWithSeconds() {
        let content = "timer: Oeuf a la coque\ncountdown 10:00\n// mollet"
        XCTAssertEqual(NoteStore.contentWithTimerLine(content, mode: .countdown, seconds: 270),
                       "timer: Oeuf a la coque\ncountdown 4:30\n// mollet")
    }

    func testAddsLineUnderHeaderWhenMissing() {
        XCTAssertEqual(NoteStore.contentWithTimerLine("timer", mode: .countdown, seconds: 1500), "timer\ncountdown 25:00")
    }

    func testAlarmLineIsTimeOfDay() {
        XCTAssertEqual(NoteStore.contentWithTimerLine("timer\ncountdown 5:00", mode: .alarm, seconds: 7 * 3600 + 30 * 60),
                       "timer\nalarm 07:30")
        let parameters = NoteStore.timerParameters(content: "timer\nalarm 18:05")
        XCTAssertEqual(parameters.mode, .alarm)
        XCTAssertEqual(parameters.seconds, 18 * 3600 + 5 * 60)
    }

    func testLegacyPomodoroLineReadsAsCountdown() {
        let parameters = NoteStore.timerParameters(content: "timer\npomodoro 25:00")
        XCTAssertEqual(parameters.mode, .countdown)
        XCTAssertEqual(parameters.seconds, 1500)
        XCTAssertEqual(NoteStore.contentWithTimerLine("timer\npomodoro 25:00", mode: .alarm, seconds: 6 * 3600), "timer\nalarm 06:00")
    }

    func testAlarmFiresAtNextOccurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 8, minute: 0))!
        XCTAssertEqual(TimerSession.secondsUntil(9 * 3600, from: now, calendar: calendar), 3600)
        XCTAssertEqual(TimerSession.secondsUntil(7 * 3600, from: now, calendar: calendar), 23 * 3600, "heure passée : demain")
    }

    func testLegacyPomodoroSnapshotStillDecodes() throws {
        let json = #"{"mode":"pomodoro","state":"paused","targetDuration":1500,"elapsed":10}"#
        let snapshot = try JSONDecoder().decode(TimerSession.Snapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.mode, .countdown)
        XCTAssertNil(snapshot.alarmTime)
    }

    func testStopwatchHasNoDuration() {
        XCTAssertEqual(NoteStore.contentWithTimerLine("timer\ncountdown 5:00", mode: .stopwatch, seconds: 300), "timer\nstopwatch")
    }

    func testLeavesOtherTextAlone() {
        // « Chronologie » n'est pas une ligne de réglage.
        let content = "timer\nChronologie du tournage\ncountdown 1:00"
        XCTAssertEqual(NoteStore.contentWithTimerLine(content, mode: .countdown, seconds: 95),
                       "timer\nChronologie du tournage\ncountdown 1:35")
    }

    func testWrittenLineReadsBack() {
        let store = NoteStore()
        var note = Note()
        note.content = NoteStore.contentWithTimerLine("timer", mode: .countdown, seconds: 222)
        let parameters = store.timerParameters(for: note)
        XCTAssertEqual(parameters.mode, .countdown)
        XCTAssertEqual(parameters.seconds, 222)
    }
}
