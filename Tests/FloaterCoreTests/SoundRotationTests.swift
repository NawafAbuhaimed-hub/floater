import XCTest
@testable import FloaterCore

final class SoundRotationTests: XCTestCase {
    private func rotation(_ names: [String], prefs: Preferences) -> SoundRotation {
        SoundRotation(names: names, prefs: prefs)
    }

    func testItCyclesInOrderAndWrapsAround() {
        let prefs = Preferences(store: InMemoryStore())
        let sounds = rotation(["a", "b", "c"], prefs: prefs)
        XCTAssertEqual((0..<7).compactMap { _ in sounds.next() },
                       ["a", "b", "c", "a", "b", "c", "a"])
    }

    func testTheRotationContinuesAcrossLaunches() {
        let store = InMemoryStore()
        let first = rotation(["a", "b", "c"], prefs: Preferences(store: store))
        _ = first.next()
        _ = first.next()

        // A fresh process reading the same stored index.
        let second = rotation(["a", "b", "c"], prefs: Preferences(store: store))
        XCTAssertEqual(second.next(), "c", "it picks up where it left off, not back at the start")
    }

    func testAStoredIndexPastTheEndWrapsInsteadOfCrashing() {
        let store = InMemoryStore()
        let prefs = Preferences(store: store)
        prefs.completionSoundIndex = 99 // as if sounds had been removed since
        XCTAssertEqual(rotation(["a", "b"], prefs: prefs).next(), "b", "99 % 2 == 1")
    }

    func testANegativeStoredIndexIsStillInBounds() {
        let prefs = Preferences(store: InMemoryStore())
        prefs.completionSoundIndex = -3
        XCTAssertEqual(rotation(["a", "b"], prefs: prefs).next(), "b")
    }

    func testNoSoundsMeansNoSelectionRatherThanACrash() {
        let sounds = rotation([], prefs: Preferences(store: InMemoryStore()))
        XCTAssertNil(sounds.next())
        XCTAssertEqual(sounds.count, 0)
    }

    func testASingleSoundAlwaysPlays() {
        let sounds = rotation(["only"], prefs: Preferences(store: InMemoryStore()))
        XCTAssertEqual((0..<3).compactMap { _ in sounds.next() }, ["only", "only", "only"])
    }

    func testTheStoredIndexAdvancesByExactlyOnePerPlay() {
        let prefs = Preferences(store: InMemoryStore())
        let sounds = rotation(["a", "b", "c"], prefs: prefs)
        _ = sounds.next()
        XCTAssertEqual(prefs.completionSoundIndex, 1)
        _ = sounds.next()
        XCTAssertEqual(prefs.completionSoundIndex, 2)
    }
}
