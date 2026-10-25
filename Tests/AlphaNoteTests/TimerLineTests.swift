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
        XCTAssertEqual(NoteStore.contentWithTimerLine("timer", mode: .pomodoro, seconds: 1500), "timer\npomodoro 25:00")
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
