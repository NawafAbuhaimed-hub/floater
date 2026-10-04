import XCTest
@testable import FloaterCore

@MainActor
final class ArchiveTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        store = try Store(inMemory: true)
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
        model.logCompletions = false
    }

    @discardableResult
    private func finish(_ title: String, minutes: Int = 30) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        let task = model.tasks.first { $0.title == title }!
        if minutes > 0 {
            model.start(task, minutes: minutes)
            clock.advance(TimeInterval(minutes * 60))
            model.stopTimer()
        }
        model.complete(model.tasks.first { $0.id == task.id }!)
        return task
    }

    func testHidingFinishedWorkKeepsTheXPAndLevel() {
        finish("One", minutes: 45)
        finish("Two", minutes: 30)
        let xpBefore = model.stats?.totalXP ?? 0
        let levelBefore = model.stats?.level ?? 0
        XCTAssertGreaterThan(xpBefore, 0)

        model.clearCompleted()

        XCTAssertEqual(model.stats?.totalXP, xpBefore, "clearing the list must not erase what was earned")
        XCTAssertEqual(model.stats?.level, levelBefore)
    }

    func testHidingKeepsTheStreakAndBadges() {
        finish("One", minutes: 45)
        let streakBefore = model.stats?.streakDays ?? 0
        let badgesBefore = model.stats?.earnedBadges.count ?? 0
        XCTAssertGreaterThan(streakBefore, 0)
        XCTAssertGreaterThan(badgesBefore, 0)

        model.clearCompleted()

        XCTAssertEqual(model.stats?.streakDays, streakBefore)
        XCTAssertEqual(model.stats?.earnedBadges.count, badgesBefore)
    }

    func testHidingKeepsTheDoneTodayCount() {
        finish("One", minutes: 0)
        finish("Two", minutes: 0)
        XCTAssertEqual(model.completedToday, 2)

        model.clearCompleted()

        XCTAssertEqual(model.completedToday, 2, "it still happened today")
    }

    func testHiddenWorkStillAppearsInTheDigest() {
        finish("Shipped the thing", minutes: 45)
        model.clearCompleted()

        let digest = model.digest(days: 7)
        XCTAssertEqual(digest.completed.map(\.title), ["Shipped the thing"])
        XCTAssertEqual(digest.totalFocused, 45 * 60, accuracy: 1)
    }

    func testHidingTakesThemOutOfTheList() {
        finish("Done one", minutes: 0)
        model.draft = "Still open"
        model.addDraftTask()

        model.clearCompleted()

        XCTAssertEqual(model.tasks.map(\.title), ["Still open"])
        XCTAssertEqual(model.hiddenCount, 1)
        XCTAssertEqual(model.doneCount, 0, "nothing finished is showing any more")
    }

    func testHiddenWorkCanBeBroughtBack() {
        finish("Done one", minutes: 0)
        model.clearCompleted()
        XCTAssertEqual(model.hiddenCount, 1)

        model.showHiddenAgain()

        XCTAssertEqual(model.tasks.map(\.title), ["Done one"])
        XCTAssertEqual(model.hiddenCount, 0)
    }

    func testHidingLeavesUnfinishedWorkAlone() {
        model.draft = "Open"
        model.addDraftTask()
        finish("Closed", minutes: 0)

        model.clearCompleted()

        XCTAssertEqual(model.tasks.map(\.title), ["Open"])
        XCTAssertEqual(model.hiddenCount, 1)
    }

    func testDeletingATaskStillRemovesItFromTheFigures() {
        let task = finish("Deleted", minutes: 45)
        let xpBefore = model.stats?.totalXP ?? 0
        XCTAssertGreaterThan(xpBefore, 0)

        model.delete(store.task(id: task.id)!)

        XCTAssertEqual(model.stats?.totalXP, 0, "deleting is still a real delete")
        XCTAssertEqual(model.hiddenCount, 0)
    }

    func testAHiddenTaskIsStillReachableByIdSoItsEventCanBeRemoved() {
        let task = finish("Hidden", minutes: 0)
        model.clearCompleted()
        XCTAssertNotNil(store.task(id: task.id), "archived is hidden, not gone")
    }
}

@MainActor
final class RestoreLostWorkTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        store = try Store(inMemory: true)
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
        model.logCompletions = false
    }

    /// A session record left behind by a task that was deleted.
    private func orphanSession(_ title: String, seconds: Double, daysAgo: Int,
                               id: UUID = UUID()) {
        let when = Calendar.current.date(byAdding: .day, value: -daysAgo, to: clock.now)!
        store.record(FocusSessionRecord(taskID: id, taskTitle: title, startedAt: when,
                                        endedAt: when, plannedMinutes: Int(seconds / 60),
                                        secondsFocused: seconds, completedTask: true))
    }

    func testDeletedWorkIsRebuiltFromItsFocusHistory() {
        orphanSession("Leads Import", seconds: 45 * 60, daysAgo: 1)
        orphanSession("RED tool", seconds: 30 * 60, daysAgo: 2)
        XCTAssertEqual(model.stats?.totalXP, 0)

        let restored = model.restoreLostCompletions()

        XCTAssertEqual(restored, 2)
        XCTAssertEqual(model.stats?.totalXP, (10 + 9) + (10 + 6))
    }

    func testRestoredWorkStaysOutOfTheList() {
        orphanSession("Old thing", seconds: 600, daysAgo: 3)
        model.restoreLostCompletions()
        XCTAssertTrue(model.tasks.isEmpty, "it is history, not something still to do")
        XCTAssertEqual(model.hiddenCount, 1)
    }

    func testSeveralSessionsOnOneTaskBecomeOneTask() {
        let id = UUID()
        orphanSession("Long haul", seconds: 45 * 60, daysAgo: 2, id: id)
        orphanSession("Long haul", seconds: 15 * 60, daysAgo: 1, id: id)

        XCTAssertEqual(model.restoreLostCompletions(), 1)
        XCTAssertEqual(model.stats?.totalXP, 10 + 12, "their focused time adds up")
    }

    func testRunningItTwiceChangesNothing() {
        orphanSession("Once", seconds: 600, daysAgo: 1)
        model.restoreLostCompletions()
        let xp = model.stats?.totalXP

        XCTAssertEqual(model.restoreLostCompletions(), 0, "nothing left to restore")
        XCTAssertEqual(model.stats?.totalXP, xp)
        XCTAssertEqual(model.hiddenCount, 1)
    }

    func testATaskThatStillExistsIsLeftAlone() {
        model.draft = "Still here"
        model.addDraftTask()
        let task = model.tasks[0]
        model.complete(task)
        let xp = model.stats?.totalXP

        XCTAssertEqual(model.restoreLostCompletions(), 0)
        XCTAssertEqual(model.stats?.totalXP, xp)
        XCTAssertEqual(model.tasks.map(\.title), ["Still here"], "and is not duplicated")
    }

    func testRestoredDatesBringBackTheStreak() {
        orphanSession("Yesterday", seconds: 600, daysAgo: 1)
        orphanSession("Today", seconds: 600, daysAgo: 0)
        XCTAssertEqual(model.stats?.streakDays, 0)

        model.restoreLostCompletions()

        XCTAssertEqual(model.stats?.streakDays, 2)
    }
}
