import XCTest
@testable import FloaterCore

@MainActor
final class AppModelTests: XCTestCase {
    private var clock: TestClock!
    private var model: AppModel!
    private var prefStore: InMemoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        prefStore = InMemoryStore()
        model = AppModel(
            store: try Store(inMemory: true),
            prefs: Preferences(store: prefStore),
            clock: clock,
            autoTick: false
        )
    }

    @discardableResult
    private func addTask(_ title: String) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        return model.openTasks.first { $0.title == title }!
    }

    // MARK: - Tasks

    func testAddingATaskClearsTheDraft() {
        addTask("Write the spec")
        XCTAssertEqual(model.draft, "")
        XCTAssertEqual(model.openTasks.map(\.title), ["Write the spec"])
    }

    func testBlankDraftIsIgnoredAndKeptInTheField() {
        model.draft = "   "
        model.addDraftTask()
        XCTAssertEqual(model.draft, "   ")
        XCTAssertTrue(model.openTasks.isEmpty)
    }

    func testCompletingATaskFiresTheCelebrationWithItsTitle() {
        let task = addTask("Ship Floater")
        var celebrated: [String] = []
        model.onCelebrate = { celebrated.append($0) }

        model.complete(task)

        XCTAssertEqual(celebrated, ["Ship Floater"])
        XCTAssertTrue(model.openTasks.isEmpty)
        XCTAssertEqual(model.completedToday, 1)
    }

    // MARK: - Timer

    func testStartingATimerCollapsesThePillAndTracksTheTask() {
        let task = addTask("Deep work")
        model.mode = .expanded

        model.start(task, minutes: 45)

        XCTAssertEqual(model.mode, .collapsed)
        XCTAssertEqual(model.activeTaskID, task.id)
        XCTAssertEqual(model.activeTitle, "Deep work")
        XCTAssertEqual(model.remainingText, "45:00")
        XCTAssertTrue(model.isRunning)
    }

    func testRemainingTextCountsDown() {
        let task = addTask("Countdown")
        model.start(task, minutes: 15)
        clock.advance(61)
        model.refresh()
        XCTAssertEqual(model.remainingText, "13:59")
    }

    func testCompletingTheActiveTaskBanksFocusedTimeExactlyOnce() {
        let task = addTask("Banked once")
        model.start(task, minutes: 30)
        clock.advance(600)

        model.complete(task)

        let saved = model.tasks.first { $0.id == task.id }
        XCTAssertEqual(saved?.secondsSpent ?? 0, 600, accuracy: 0.5,
                       "10 minutes of focus must be recorded once, not twice")
        XCTAssertFalse(model.isActive)
        XCTAssertNil(model.activeTaskID)
    }

    func testStoppingBanksTimeAndLeavesTheTaskOpen() {
        let task = addTask("Still open")
        model.start(task, minutes: 15)
        clock.advance(300)

        model.stopTimer()

        XCTAssertEqual(model.openTasks.map(\.title), ["Still open"])
        XCTAssertEqual(model.openTasks[0].secondsSpent, 300, accuracy: 0.5)
        XCTAssertFalse(model.isActive)
    }

    func testStartingASecondTimerBanksTheFirstTasksTime() {
        let first = addTask("First")
        let second = addTask("Second")
        model.start(first, minutes: 15)
        clock.advance(420)

        model.start(second, minutes: 30)

        XCTAssertEqual(model.activeTaskID, second.id)
        let firstSaved = model.tasks.first { $0.id == first.id }
        XCTAssertEqual(firstSaved?.secondsSpent ?? 0, 420, accuracy: 0.5)
    }

    func testDeletingTheActiveTaskEndsTheRun() {
        let task = addTask("Doomed")
        model.start(task, minutes: 15)
        clock.advance(60)

        model.delete(task)

        XCTAssertFalse(model.isActive)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testPausingStopsTheClockFromBurningTheBudget() {
        let task = addTask("Interrupted")
        model.start(task, minutes: 15)
        clock.advance(60)
        model.togglePause()

        clock.advance(3600)
        model.refresh()
        XCTAssertEqual(model.remainingText, "14:00")
        XCTAssertEqual(model.phase, .paused)

        model.togglePause()
        XCTAssertTrue(model.isRunning)
    }

    // MARK: - Time up

    func testReachingZeroFiresTimeUpOnceAndPulsesThePill() {
        let task = addTask("Times out")
        var fired: [FocusRun] = []
        model.onTimeUp = { fired.append($0) }
        model.start(task, minutes: 15)

        clock.advance(900)
        model.tick()
        model.tick()
        model.tick()

        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first?.taskTitle, "Times out")
        XCTAssertEqual(model.attentionPulse, 1)
        XCTAssertEqual(model.phase, .elapsed)
    }

    func testExtendingFromTimeUpResumesAndDismissesTheTakeover() {
        let task = addTask("Needs longer")
        model.start(task, minutes: 15)
        clock.advance(900)
        model.tick()

        var dismissed = 0
        model.onDismissTimeUp = { dismissed += 1 }
        model.extend(minutes: 10)

        XCTAssertEqual(dismissed, 1)
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.remainingText, "10:00")
    }

    func testDoneFromTimeUpCompletesTheTaskAndCelebrates() {
        let task = addTask("Finished at the buzzer")
        model.start(task, minutes: 15)
        clock.advance(900)
        model.tick()

        var celebrated: [String] = []
        var dismissed = 0
        model.onCelebrate = { celebrated.append($0) }
        model.onDismissTimeUp = { dismissed += 1 }

        model.completeActiveTask()

        XCTAssertEqual(celebrated, ["Finished at the buzzer"])
        XCTAssertEqual(dismissed, 1)
        XCTAssertTrue(model.openTasks.isEmpty)
        XCTAssertEqual(model.tasks.first?.secondsSpent ?? 0, 900, accuracy: 0.5)
        XCTAssertFalse(model.isActive)
    }

    // MARK: - Persistence

    func testAnInFlightRunSurvivesRelaunch() throws {
        let prefs = Preferences(store: prefStore)
        let store = try Store(inMemory: true)
        let first = AppModel(store: store, prefs: prefs, clock: clock, autoTick: false)
        first.draft = "Long haul"
        first.addDraftTask()
        let task = first.openTasks[0]
        first.start(task, minutes: 45)
        clock.advance(600)
        first.refresh()

        // Same store, fresh model — as if the app had been quit and reopened.
        let revived = AppModel(store: store, prefs: prefs, clock: clock, autoTick: false)

        XCTAssertTrue(revived.isRunning)
        XCTAssertEqual(revived.activeTitle, "Long haul")
        XCTAssertEqual(revived.remainingText, "35:00")
    }

    func testARunThatExpiredWhileQuitFiresTimeUpOnRelaunch() throws {
        let prefs = Preferences(store: prefStore)
        let store = try Store(inMemory: true)
        let first = AppModel(store: store, prefs: prefs, clock: clock, autoTick: false)
        first.draft = "Expired while away"
        first.addDraftTask()
        first.start(first.openTasks[0], minutes: 15)
        first.refresh()

        clock.advance(86_400) // quit overnight

        let revived = AppModel(store: store, prefs: prefs, clock: clock, autoTick: false)
        XCTAssertEqual(revived.phase, .elapsed, "a deadline missed while quit must still surface")
        XCTAssertEqual(revived.remainingText, "0:00")
    }

    func testSettingsRoundTripThroughPreferences() {
        model.soundEnabled = false
        model.takeoverEnabled = false
        let reloaded = Preferences(store: prefStore)
        XCTAssertFalse(reloaded.soundEnabled)
        XCTAssertFalse(reloaded.takeoverEnabled)
    }
}
