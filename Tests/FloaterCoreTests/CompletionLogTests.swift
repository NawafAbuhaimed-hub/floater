import XCTest
@testable import FloaterCore

@MainActor
final class CompletionLogTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var prefs: Preferences!
    private var scheduler: FakeScheduler!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        store = try Store(inMemory: true)
        prefs = Preferences(store: InMemoryStore())
        scheduler = FakeScheduler()
        model = AppModel(store: store, prefs: prefs, clock: clock,
                         scheduler: scheduler, autoTick: false)
    }

    @discardableResult
    private func addTask(_ title: String) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        return model.tasks.first { $0.title == title }!
    }

    private func reread(_ task: TaskItem) -> TaskItem? {
        model.tasks.first { $0.id == task.id }
    }

    /// The log is written from a detached Task; let it land.
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    // MARK: - Writing the log

    func testFinishingATaskWritesAnEventEndingAtTheCompletionMoment() async {
        let task = addTask("Draft Q3 deck")
        model.start(task, minutes: 45)
        clock.advance(45 * 60)

        model.complete(reread(task)!)
        await settle()

        XCTAssertEqual(scheduler.scheduled.count, 1)
        let request = scheduler.scheduled[0]
        XCTAssertEqual(request.title, "Draft Q3 deck \u{2705}")
        XCTAssertEqual(request.destination, .calendar)
        XCTAssertEqual(request.duration, 2700, accuracy: 1, "the block spans the time actually focused")
        XCTAssertEqual(request.date, clock.now.addingTimeInterval(-2700),
                       "it starts a focus-length before the completion, so it ends when the task did")
    }

    func testATaskFinishedWithoutATimerGetsTheFallbackBlock() async {
        let task = addTask("Quick thing")
        model.complete(task)
        await settle()

        XCTAssertEqual(scheduler.scheduled.first?.duration, AppModel.untimedCompletionSeconds)
        XCTAssertEqual(scheduler.scheduled.first?.date,
                       clock.now.addingTimeInterval(-AppModel.untimedCompletionSeconds))
    }

    func testTheEventCarriesTheNoteAndTheFocusedTime() async {
        let task = addTask("With context")
        store.updateNote("chase Omar for the numbers", forTaskWith: task.id)
        model.start(reread(task)!, minutes: 30)
        clock.advance(30 * 60)

        model.complete(reread(task)!)
        await settle()

        let notes = scheduler.scheduled.first?.notes ?? ""
        XCTAssertTrue(notes.contains("chase Omar for the numbers"), notes)
        XCTAssertTrue(notes.contains("Focused 30m"), notes)
    }

    func testItGoesToTheChosenFollowUpCalendar() async {
        prefs.setFollowUpTargetID("cal-google", for: .calendar)
        model.complete(addTask("Targeted"))
        await settle()
        XCTAssertEqual(scheduler.scheduled.first?.targetID, "cal-google")
    }

    func testTheEventIdentifierIsKeptOnTheTask() async {
        scheduler.nextExternalID = "evt-123"
        let task = addTask("Tracked")
        model.complete(task)
        await settle()
        XCTAssertEqual(reread(task)?.completionEventID, "evt-123")
    }

    // MARK: - Not writing it

    func testNothingIsWrittenWhenLoggingIsOff() async {
        model.logCompletions = false
        model.complete(addTask("Unlogged"))
        await settle()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertNil(model.completionLogError)
    }

    func testTheToggleIsOnByDefaultAndPersists() {
        XCTAssertTrue(model.logCompletions)
        model.logCompletions = false
        XCTAssertFalse(Preferences(store: InMemoryStore()).logCompletions == false,
                       "a fresh store still defaults to on")
        XCTAssertFalse(prefs.logCompletions, "the real store remembers the change")
    }

    // MARK: - Taking it back

    func testReopeningATaskRemovesItsEvent() async {
        scheduler.nextExternalID = "evt-reopen"
        let task = addTask("Undo me")
        model.complete(task)
        await settle()

        model.reopen(reread(task)!)
        await settle()

        XCTAssertEqual(scheduler.removed, ["evt-reopen"])
        XCTAssertEqual(reread(task)?.completionEventID, "", "the id is cleared so it cannot be removed twice")
    }

    func testMovingOffDoneByStatusAlsoRemovesTheEvent() async {
        scheduler.nextExternalID = "evt-status"
        let task = addTask("Back to work")
        model.complete(task)
        await settle()

        model.setStatus(.inProgress, for: reread(task)!)
        await settle()

        XCTAssertEqual(scheduler.removed, ["evt-status"])
    }

    func testDeletingAFinishedTaskRemovesItsEvent() async {
        scheduler.nextExternalID = "evt-delete"
        let task = addTask("Gone")
        model.complete(task)
        await settle()

        model.delete(reread(task)!)
        await settle()

        XCTAssertEqual(scheduler.removed, ["evt-delete"])
    }

    func testAnUnfinishedTaskHasNothingToRemove() async {
        model.delete(addTask("Never finished"))
        await settle()
        XCTAssertTrue(scheduler.removed.isEmpty)
    }

    // MARK: - Failure never blocks the completion

    func testACalendarFailureStillCompletesTheTask() async {
        scheduler.errorToThrow = FollowUpError.noDefaultList(.calendar)
        var celebrated: [String] = []
        model.onCelebrate = { celebrated.append($0) }

        let task = addTask("Finishes anyway")
        model.complete(task)
        await settle()

        XCTAssertEqual(reread(task)?.status, .done, "the calendar is not allowed to veto a completion")
        XCTAssertEqual(celebrated, ["Finishes anyway"])
        XCTAssertEqual(model.completionLogError, FollowUpError.noDefaultList(.calendar).message)
        XCTAssertEqual(reread(task)?.completionEventID, "")
    }

    func testADeniedPermissionIsReportedNotSwallowed() async {
        scheduler.accessGranted = false
        model.complete(addTask("Denied"))
        await settle()
        XCTAssertEqual(model.completionLogError, FollowUpError.accessDenied(.calendar).message)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testAFailedRemovalDoesNotBlockReopening() async {
        let task = addTask("Stubborn")
        model.complete(task)
        await settle()
        scheduler.removalError = FollowUpError.underlying("calendar busy")

        model.reopen(reread(task)!)
        await settle()

        XCTAssertEqual(reread(task)?.status, .notStarted)
    }
}
