import XCTest
@testable import FloaterCore

final class TimerEngineTests: XCTestCase {
    private var clock: TestClock!
    private var engine: TimerEngine!
    private let taskID = UUID()

    override func setUp() {
        super.setUp()
        clock = TestClock()
        engine = TimerEngine(clock: clock)
    }

    private func start(_ minutes: Int = 15) {
        engine.start(taskID: taskID, title: "Write the thing", minutes: minutes)
    }

    func testStartBeginsRunningWithFullBudget() {
        start(15)
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.remaining, 900, accuracy: 0.001)
        XCTAssertEqual(engine.elapsed, 0, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 0, accuracy: 0.001)
    }

    func testCountdownFollowsTheClock() {
        start(30)
        clock.advance(600)
        XCTAssertEqual(engine.remaining, 1200, accuracy: 0.001)
        XCTAssertEqual(engine.elapsed, 600, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 1.0 / 3.0, accuracy: 0.001)
    }

    func testPauseFreezesRemainingAndResumePushesDeadline() {
        start(15)
        clock.advance(300)
        engine.pause()
        XCTAssertEqual(engine.phase, .paused)

        clock.advance(10_000) // a long lunch
        XCTAssertEqual(engine.remaining, 600, accuracy: 0.001, "paused time must not burn the budget")
        XCTAssertEqual(engine.elapsed, 300, accuracy: 0.001, "paused time is not focus time")

        engine.resume()
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.remaining, 600, accuracy: 0.001)
        clock.advance(100)
        XCTAssertEqual(engine.remaining, 500, accuracy: 0.001)
        XCTAssertEqual(engine.elapsed, 400, accuracy: 0.001)
    }

    func testTickFiresElapsedExactlyOnceEvenAfterALongSleep() {
        var fired: [FocusRun] = []
        engine.onElapsed = { fired.append($0) }
        start(15)

        clock.advance(60)
        XCTAssertFalse(engine.tick())
        XCTAssertTrue(fired.isEmpty)

        clock.advance(86_400) // machine slept overnight past the deadline
        XCTAssertTrue(engine.tick())
        XCTAssertEqual(engine.phase, .elapsed)
        XCTAssertEqual(fired.count, 1)

        // Extra ticks must not re-fire.
        clock.advance(60)
        XCTAssertFalse(engine.tick())
        XCTAssertFalse(engine.tick())
        XCTAssertEqual(fired.count, 1)
    }

    func testElapsedTimeIsNotInflatedByASleepPastTheDeadline() {
        start(15)
        clock.advance(86_400)
        engine.tick()
        XCTAssertEqual(engine.elapsed, 900, accuracy: 0.001, "cannot focus longer than the budget")
    }

    func testRemainingIsZeroNotNegativeAfterTheDeadline() {
        start(15)
        clock.advance(1200)
        XCTAssertEqual(engine.remaining, 0, accuracy: 0.001)
        XCTAssertEqual(engine.progress, 1, accuracy: 0.001)
    }

    func testExtendFromElapsedResumesWithMoreTime() {
        start(15)
        clock.advance(900)
        engine.tick()
        XCTAssertEqual(engine.phase, .elapsed)

        engine.extend(minutes: 10)
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.remaining, 600, accuracy: 0.001)
        XCTAssertEqual(engine.run?.plannedSeconds, 1500)

        clock.advance(600)
        XCTAssertTrue(engine.tick())
        XCTAssertEqual(engine.elapsed, 1500, accuracy: 0.001)
    }

    func testExtendWhileRunningAddsToTheDeadline() {
        start(15)
        clock.advance(300)
        engine.extend(minutes: 5)
        XCTAssertEqual(engine.remaining, 900, accuracy: 0.001)
        XCTAssertEqual(engine.phase, .running)
    }

    func testExtendWhilePausedAddsToTheFrozenRemainder() {
        start(15)
        clock.advance(300)
        engine.pause()
        engine.extend(minutes: 5)
        XCTAssertEqual(engine.remaining, 900, accuracy: 0.001)
        engine.resume()
        XCTAssertEqual(engine.remaining, 900, accuracy: 0.001)
    }

    func testStopReturnsFocusedTimeAndGoesIdle() {
        start(45)
        clock.advance(1234)
        let result = engine.stop()
        XCTAssertEqual(result?.taskID, taskID)
        XCTAssertEqual(result?.elapsed ?? 0, 1234, accuracy: 0.001)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.run)
        XCTAssertFalse(engine.isActive)
    }

    func testStartingANewRunReplacesTheOldOne() {
        start(15)
        clock.advance(120)
        let other = UUID()
        engine.start(taskID: other, title: "Something else", minutes: 45)
        XCTAssertEqual(engine.run?.taskID, other)
        XCTAssertEqual(engine.remaining, 2700, accuracy: 0.001)
        XCTAssertEqual(engine.elapsed, 0, accuracy: 0.001)
    }

    func testRestoreAfterRelaunchDetectsAMissedDeadline() {
        start(15)
        let saved = engine.run!
        clock.advance(2000) // app was quit; deadline passed while it was gone

        let revived = TimerEngine(clock: clock)
        var fired = 0
        revived.onElapsed = { _ in fired += 1 }
        let missed = revived.restore(saved, phase: .running)

        XCTAssertTrue(missed)
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(revived.phase, .elapsed)
    }

    func testRestoreWithTimeLeftKeepsRunning() {
        start(45)
        let saved = engine.run!
        clock.advance(600)

        let revived = TimerEngine(clock: clock)
        XCTAssertFalse(revived.restore(saved, phase: .running))
        XCTAssertEqual(revived.phase, .running)
        XCTAssertEqual(revived.remaining, 2100, accuracy: 0.001)
    }

    func testCommandsAreNoOpsWhenIdle() {
        engine.pause()
        engine.resume()
        engine.extend(minutes: 10)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.stop())
        XCTAssertFalse(engine.tick())
    }
}
