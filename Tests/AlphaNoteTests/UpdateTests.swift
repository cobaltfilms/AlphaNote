import XCTest
@testable import AlphaNote

final class UpdateTests: XCTestCase {

    // MARK: - VersionComparator

    func testNewerMinorVersion() {
        XCTAssertTrue(VersionComparator.isNewer("1.1.0", than: "1.0.9"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.9", than: "1.1.0"))
    }

    func testEqualVersionIsNotNewer() {
        XCTAssertFalse(VersionComparator.isNewer("1.2.3", than: "1.2.3"))
    }

    func testDifferentLengthBasesArePadded() {
        XCTAssertTrue(VersionComparator.isNewer("1.2", than: "1.1.9"))
        XCTAssertTrue(VersionComparator.isNewer("2", than: "1.9.9"))
    }

    func testStableBeatsPrereleaseOfSameBase() {
        XCTAssertTrue(VersionComparator.isNewer("1.0.0", than: "1.0.0b3"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0b3", than: "1.0.0"))
    }

    func testPrereleasesCompareBySuffix() {
        XCTAssertTrue(VersionComparator.isNewer("1.0.0b2", than: "1.0.0b1"))
        XCTAssertFalse(VersionComparator.isNewer("1.0.0b1", than: "1.0.0b2"))
    }

    func testLeadingVIsIgnored() {
        XCTAssertTrue(VersionComparator.isNewer("v1.2.0", than: "1.1.0"))
    }

    // MARK: - UpdateBundleSelector

    func testSelectsBundleMatchingNameAndIdentifier() {
        let candidates = [
            UpdateBundleSelector.Candidate(name: "Other.app", bundleIdentifier: "be.other"),
            UpdateBundleSelector.Candidate(name: "AlphaNote.app", bundleIdentifier: "be.cobaltfilms.alphanote")
        ]
        let outcome = UpdateBundleSelector.select(
            from: candidates,
            expectedName: "AlphaNote.app",
            runningIdentifier: "be.cobaltfilms.alphanote")
        XCTAssertEqual(outcome, .success(candidateIndex: 1))
    }

    func testNoBundleFoundWhenNameMissing() {
        let candidates = [UpdateBundleSelector.Candidate(name: "Other.app", bundleIdentifier: "be.other")]
        let outcome = UpdateBundleSelector.select(
            from: candidates, expectedName: "AlphaNote.app", runningIdentifier: "be.cobaltfilms.alphanote")
        XCTAssertEqual(outcome, .failure(.noBundleFound))
    }

    func testIdentityMismatchRefusesInstall() {
        let candidates = [UpdateBundleSelector.Candidate(name: "AlphaNote.app", bundleIdentifier: "be.wrong")]
        let outcome = UpdateBundleSelector.select(
            from: candidates, expectedName: "AlphaNote.app", runningIdentifier: "be.cobaltfilms.alphanote")
        XCTAssertEqual(outcome, .failure(.identityMismatch(found: "be.wrong")))
    }

    func testUnknownRunningIdentityRefusesInstall() {
        let candidates = [UpdateBundleSelector.Candidate(name: "AlphaNote.app", bundleIdentifier: "be.cobaltfilms.alphanote")]
        let outcome = UpdateBundleSelector.select(
            from: candidates, expectedName: "AlphaNote.app", runningIdentifier: nil)
        XCTAssertEqual(outcome, .failure(.unknownRunningIdentity))
    }
}
