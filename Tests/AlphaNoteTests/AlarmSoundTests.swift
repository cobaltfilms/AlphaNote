import XCTest
import AVFoundation
@testable import AlphaNote

final class AlarmSoundTests: XCTestCase {

    /// Chaque sonnerie embarquée est présente et lisible (≈ 1,5 à 3 s).
    func testBundledSoundsArePlayable() throws {
        for sound in AlarmSound.allCases where sound != .systeme {
            let url = try XCTUnwrap(sound.url, "\(sound.label) absent du bundle")
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 1.2, sound.label)
            XCTAssertLessThan(player.duration, 4, sound.label)
        }
        XCTAssertNil(AlarmSound.systeme.url)
    }

    func testDefaultIsMinuterie() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: AlarmSound.storageKey)
        defer { defaults.set(saved, forKey: AlarmSound.storageKey) }
        defaults.removeObject(forKey: AlarmSound.storageKey)
        XCTAssertEqual(AlarmSound.current, .minuterie)
    }
}
