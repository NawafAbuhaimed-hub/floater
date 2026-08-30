import XCTest
import SwiftData
@testable import FloaterCore

@MainActor
final class StatusAndNotesTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        store = try Store(inMemory: true)
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
    }

    @discardableResult
    private func addTask(_ title: String) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        return model.tasks.first { $0.title == title }!
    }

    private func reread(_ task: TaskItem) -> TaskItem {
        model.tasks.first { $0.id == task.id }!
    }

    // MARK: - Status

    func testNewTasksStartNotStarted() {
        let task = addTask("Fresh")
        XCTAssertEqual(task.status, .notStarted)
        XCTAssertFalse(task.isDone)
    }

    func testStartingATimerMarksTheTaskInProgress() {
        let task = addTask("Working on it")
        model.start(task, minutes: 15)
        XCTAssertEqual(reread(task).status, .inProgress)
    }

    func testCompletingSetsDoneAndStampsTheCompletionDate() {
        let task = addTask("Finish me")
        model.complete(task)
        let saved = reread(task)
        XCTAssertEqual(saved.status, .done)
        XCTAssertNotNil(saved.completedAt)
        XCTAssertTrue(saved.isDone)
    }

    func testSettingStatusToDoneGoesThroughTheCelebrationPath() {
        let task = addTask("Via status")
        var celebrated: [String] = []
        model.onCelebrate = { celebrated.append($0) }

        model.setStatus(.done, for: task)

        XCTAssertEqual(celebrated, ["Via status"])
        XCTAssertEqual(reread(task).status, .done)
    }

    func testMovingOffDoneClearsTheCompletionDate() {
        let task = addTask("Undo me")
        model.complete(task)
        model.setStatus(.inProgress, for: task)
        let saved = reread(task)
        XCTAssertEqual(saved.status, .inProgress)
        XCTAssertNil(saved.completedAt, "an unfinished task must not count as done today")
        XCTAssertEqual(model.completedToday, 0)
    }

    func testToggleDoneRoundTripsThroughNotStarted() {
        let task = addTask("Toggle")
        model.toggleDone(task)
        XCTAssertEqual(reread(task).status, .done)
        model.toggleDone(reread(task))
        let saved = reread(task)
        XCTAssertEqual(saved.status, .notStarted)
        XCTAssertNil(saved.completedAt)
    }

    func testBlockingTheRunningTaskStopsItsTimerAndBanksTheTime() {
        let task = addTask("Waiting on someone")
        model.start(task, minutes: 30)
        clock.advance(420)

        model.setStatus(.blocked, for: task)

        XCTAssertFalse(model.isActive, "you are not focusing on a blocked task")
        XCTAssertNil(model.activeTaskID)
        let saved = reread(task)
        XCTAssertEqual(saved.status, .blocked)
        XCTAssertEqual(saved.secondsSpent, 420, accuracy: 0.5)
    }

    func testBlockingSomeOtherTaskLeavesTheTimerAlone() {
        let running = addTask("Running")
        let other = addTask("Other")
        model.start(running, minutes: 15)

        model.setStatus(.blocked, for: other)

        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.activeTaskID, running.id)
    }

    func testSettingTheStatusItAlreadyHasDoesNothing() {
        let task = addTask("No-op")
        model.start(task, minutes: 15)
        var celebrated = 0
        model.onCelebrate = { _ in celebrated += 1 }

        model.setStatus(.inProgress, for: task)

        XCTAssertTrue(model.isRunning, "a redundant status change must not stop the timer")
        XCTAssertEqual(celebrated, 0)
    }

    func testDoneTasksStayInTheListButOutOfTheOpenCount() {
        addTask("One")
        let two = addTask("Two")
        model.complete(two)
        XCTAssertEqual(model.tasks.count, 2, "done tasks stay visible until cleared")
        XCTAssertEqual(model.openTasks.map(\.title), ["One"])
        XCTAssertEqual(model.doneCount, 1)
    }

    func testLegacyTasksWithACompletionDateAreReconciledToDone() throws {
        // A task as it would have been stored before statuses existed.
        let legacy = TaskItem(title: "From before", completedAt: Date())
        legacy.statusRaw = TaskStatus.notStarted.rawValue
        store.context.insert(legacy)
        try store.context.save()

        let reopened = Store(container: store.container)
        let migrated = reopened.tasks.first { $0.title == "From before" }
        XCTAssertEqual(migrated?.status, .done, "a finished task must not come back as Not started")
    }

    // MARK: - Notes

    func testTaskNotesPersistAfterTheDebounce() {
        let task = addTask("Has a note")
        store.updateNote("call the vendor first", forTaskWith: task.id)
        XCTAssertEqual(reread(task).note, "call the vendor first")
    }

    func testUpdatingANoteWithTheSameTextIsANoOp() {
        let task = addTask("Same")
        store.updateNote("abc", forTaskWith: task.id)
        store.updateNote("abc", forTaskWith: task.id)
        XCTAssertEqual(reread(task).note, "abc")
    }

    func testToggleNoteOpensAndClosesTheInlineEditor() {
        let task = addTask("Note toggle")
        XCTAssertNil(model.expandedTaskID)
        model.toggleNote(for: task)
        XCTAssertEqual(model.expandedTaskID, task.id)
        model.toggleNote(for: task)
        XCTAssertNil(model.expandedTaskID)
    }

    func testNotesSurviveCompletion() {
        let task = addTask("Keeps its note")
        store.updateNote("the tricky bit was the deadline math", forTaskWith: task.id)
        model.complete(task)
        XCTAssertEqual(reread(task).note, "the tricky bit was the deadline math")
    }

    // MARK: - Scratchpad

    func testScratchpadStartsEmptyAndRoundTrips() {
        XCTAssertEqual(model.scratchpad, "")
        store.scratchpadText = "buy milk\nrenew the domain"
        XCTAssertEqual(store.scratchpadText, "buy milk\nrenew the domain")
    }

    func testScratchpadReusesASingleRow() throws {
        store.scratchpadText = "first"
        store.scratchpadText = "second"
        let rows = try store.context.fetch(FetchDescriptor<Scratchpad>())
        XCTAssertEqual(rows.count, 1, "the scratchpad must not accumulate rows")
        XCTAssertEqual(rows[0].text, "second")
    }

    func testANewModelLoadsTheSavedScratchpad() {
        store.scratchpadText = "carried over"
        let revived = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                               clock: clock, autoTick: false)
        XCTAssertEqual(revived.scratchpad, "carried over")
    }
}
