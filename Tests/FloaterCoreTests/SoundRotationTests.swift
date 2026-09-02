import XCTest
@testable import FloaterCore

final class SoundRotationTests: XCTestCase {
    private func rotation(_ names: [String], prefs: Preferences) -> SoundRotation {
        SoundRotation(names: names, prefs: prefs, key: "done")
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
        prefs.setSoundIndex(99, forKey: "done") // as if sounds had been removed since
        XCTAssertEqual(rotation(["a", "b"], prefs: prefs).next(), "b", "99 % 2 == 1")
    }

    func testANegativeStoredIndexIsStillInBounds() {
        let prefs = Preferences(store: InMemoryStore())
        prefs.setSoundIndex(-3, forKey: "done")
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
        XCTAssertEqual(prefs.soundIndex(forKey: "done"), 1)
        _ = sounds.next()
        XCTAssertEqual(prefs.soundIndex(forKey: "done"), 2)
    }
}

final class SoundSetTests: XCTestCase {
    func testEachSetKeepsItsOwnPosition() {
        let prefs = Preferences(store: InMemoryStore())
        let done = SoundRotation(names: ["a", "b"], prefs: prefs, key: "done")
        let more = SoundRotation(names: ["x", "y"], prefs: prefs, key: "more")

        XCTAssertEqual(done.next(), "a")
        XCTAssertEqual(done.next(), "b")
        XCTAssertEqual(more.next(), "x", "advancing one set must not move the other")
        XCTAssertEqual(done.next(), "a")
        XCTAssertEqual(more.next(), "y")
    }
}

@MainActor
final class ExtendSoundTests: XCTestCase {
    private var clock: TestClock!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        model = AppModel(store: try Store(inMemory: true),
                         prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
    }

    private func runningTask() -> TaskItem {
        model.draft = "Needs longer"
        model.addDraftTask()
        let task = model.tasks[0]
        model.start(task, minutes: 15)
        return task
    }

    func testExtendingAnnouncesItselfWithTheMinutesAdded() {
        var extended: [Int] = []
        model.onExtend = { extended.append($0) }
        _ = runningTask()

        model.extend(minutes: 10)
        model.extend(minutes: 5)

        XCTAssertEqual(extended, [10, 5])
    }

    func testExtendingFromTimeUpAlsoAnnounces() {
        var extended: [Int] = []
        _ = runningTask()
        clock.advance(15 * 60)
        model.tick()
        XCTAssertEqual(model.phase, .elapsed)

        model.onExtend = { extended.append($0) }
        model.extend(minutes: 10)

        XCTAssertEqual(extended, [10])
        XCTAssertTrue(model.isRunning)
    }

    func testExtendingWithNoTimerRunningDoesNothing() {
        var extended: [Int] = []
        model.onExtend = { extended.append($0) }

        model.extend(minutes: 10)

        XCTAssertTrue(extended.isEmpty, "no timer means nothing to extend, and no sound")
        XCTAssertFalse(model.isActive)
    }
}
