import XCTest
import SwiftData
@testable import FloaterCore

/// Stands in for EventKit so the suite never touches a real calendar.
final class FakeScheduler: FollowUpScheduling, @unchecked Sendable {
    var accessGranted = true
    var errorToThrow: Error?
    private(set) var accessRequests: [FollowUpDestination] = []
    private(set) var scheduled: [FollowUpRequest] = []
    var nextExternalID = "external-1"

    func requestAccess(to destination: FollowUpDestination) async -> Bool {
        accessRequests.append(destination)
        return accessGranted
    }

    var targets: [FollowUpTarget] = []
    func availableTargets(for destination: FollowUpDestination) async -> [FollowUpTarget] {
        accessGranted ? targets : []
    }

    func schedule(_ request: FollowUpRequest) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        scheduled.append(request)
        return nextExternalID
    }
}

final class FollowUpOffsetTests: XCTestCase {
    /// A fixed zone keeps the expected wall-clock times stable wherever this runs.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    private func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    func testTomorrowLandsAtNineNextMorning() {
        let now = date("2026-03-10 14:32")
        XCTAssertEqual(describe(FollowUpOffset.tomorrow.resolve(from: now, calendar: calendar)),
                       "2026-03-11 09:00")
    }

    func testTomorrowFromLateAtNightIsStillTheNextDay() {
        let now = date("2026-03-10 23:58")
        XCTAssertEqual(describe(FollowUpOffset.tomorrow.resolve(from: now, calendar: calendar)),
                       "2026-03-11 09:00")
    }

    func testTomorrowFromEarlyMorningDoesNotCollapseToToday() {
        let now = date("2026-03-10 00:04")
        XCTAssertEqual(describe(FollowUpOffset.tomorrow.resolve(from: now, calendar: calendar)),
                       "2026-03-11 09:00")
    }

    func testThreeDaysAndNextWeek() {
        let now = date("2026-03-10 14:32")
        XCTAssertEqual(describe(FollowUpOffset.days(3).resolve(from: now, calendar: calendar)),
                       "2026-03-13 09:00")
        XCTAssertEqual(describe(FollowUpOffset.nextWeek.resolve(from: now, calendar: calendar)),
                       "2026-03-17 09:00")
    }

    func testItRollsOverAMonthBoundary() {
        let now = date("2026-01-30 16:00")
        XCTAssertEqual(describe(FollowUpOffset.days(3).resolve(from: now, calendar: calendar)),
                       "2026-02-02 09:00")
    }

    func testItRollsOverALeapDay() {
        let now = date("2028-02-28 16:00")
        XCTAssertEqual(describe(FollowUpOffset.tomorrow.resolve(from: now, calendar: calendar)),
                       "2028-02-29 09:00")
    }

    func testItStillLandsAtNineAcrossTheSpringForwardChange() {
        // Clocks go forward 01:00 -> 02:00 on 2026-03-29 in London.
        let now = date("2026-03-28 20:00")
        let resolved = FollowUpOffset.tomorrow.resolve(from: now, calendar: calendar)
        XCTAssertEqual(describe(resolved), "2026-03-29 09:00",
                       "adding 24h of seconds would land at 10:00")
    }

    func testItStillLandsAtNineAcrossTheAutumnChange() {
        // Clocks go back 02:00 -> 01:00 on 2026-10-25 in London.
        let now = date("2026-10-24 20:00")
        XCTAssertEqual(describe(FollowUpOffset.tomorrow.resolve(from: now, calendar: calendar)),
                       "2026-10-25 09:00")
    }

    func testAnExactDateIsUsedVerbatim() {
        let picked = date("2026-05-01 17:45")
        XCTAssertEqual(FollowUpOffset.exact(picked).resolve(from: date("2026-04-01 09:00"),
                                                           calendar: calendar), picked)
    }
}

@MainActor
final class FollowUpSchedulingTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!
    private var scheduler: FakeScheduler!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/London")!
            return calendar
        }()
        // 2026-03-10 14:32 London
        clock = TestClock(now: Date(timeIntervalSince1970: 1_773_153_120))
        store = try Store(inMemory: true)
        scheduler = FakeScheduler()
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: clock, calendar: calendar, scheduler: scheduler, autoTick: false)
    }

    @discardableResult
    private func completeATask(_ title: String = "Ship the deck", note: String = "") -> TaskItem {
        model.draft = title
        model.addDraftTask()
        let task = model.tasks.first { $0.title == title }!
        if !note.isEmpty { store.updateNote(note, forTaskWith: task.id) }
        model.complete(model.tasks.first { $0.id == task.id }!)
        return task
    }

    func testFinishingATaskOffersAFollowUp() {
        completeATask()
        XCTAssertEqual(model.pendingFollowUp?.taskTitle, "Ship the deck")
        XCTAssertNil(model.followUpError)
    }

    func testDismissingClearsThePrompt() {
        completeATask()
        model.dismissFollowUp()
        XCTAssertNil(model.pendingFollowUp)
    }

    func testSchedulingSendsTheRightRequestAndClosesThePrompt() async {
        completeATask("Ship the deck", note: "chase Omar for the numbers")
        model.followUpDestination = .calendar

        await model.scheduleFollowUp(.tomorrow)

        XCTAssertEqual(scheduler.scheduled.count, 1)
        let request = scheduler.scheduled[0]
        XCTAssertEqual(request.title, "Follow up: Ship the deck")
        XCTAssertEqual(request.destination, .calendar)
        XCTAssertTrue(request.notes.contains("chase Omar for the numbers"))
        XCTAssertTrue(request.notes.contains("Completed"))
        XCTAssertEqual(request.date, FollowUpOffset.tomorrow.resolve(from: clock.now, calendar: calendar))
        XCTAssertNil(model.pendingFollowUp)
        XCTAssertNil(model.followUpError)
    }

    func testTheChosenDestinationIsHonouredAndRemembered() async {
        let prefs = Preferences(store: InMemoryStore())
        model = AppModel(store: store, prefs: prefs, clock: clock, calendar: calendar,
                         scheduler: scheduler, autoTick: false)
        completeATask()
        model.followUpDestination = .reminders

        await model.scheduleFollowUp(.days(3))

        XCTAssertEqual(scheduler.scheduled.first?.destination, .reminders)
        XCTAssertEqual(scheduler.accessRequests, [.reminders])
        XCTAssertEqual(prefs.followUpDestination, .reminders, "the next follow-up should default to it")
    }

    func testAScheduledFollowUpIsRecordedAgainstTheTask() async {
        let task = completeATask()
        scheduler.nextExternalID = "cal-abc-123"

        await model.scheduleFollowUp(.nextWeek)

        let saved = model.tasks.first { $0.id == task.id }!
        let record = model.followUp(for: saved)
        XCTAssertEqual(record?.externalID, "cal-abc-123")
        XCTAssertEqual(record?.taskTitle, "Ship the deck")
        XCTAssertEqual(record?.destination, .calendar)
        XCTAssertEqual(record?.scheduledFor,
                       FollowUpOffset.nextWeek.resolve(from: clock.now, calendar: calendar))
    }

    func testADeniedPermissionKeepsThePromptOpenWithAReason() async {
        completeATask()
        scheduler.accessGranted = false

        await model.scheduleFollowUp(.tomorrow)

        XCTAssertEqual(model.followUpError, .accessDenied(.calendar))
        XCTAssertTrue(model.followUpError?.isPermissionProblem ?? false)
        XCTAssertTrue(model.followUpPromptPinned, "the prompt must not vanish while showing an error")
        XCTAssertNotNil(model.pendingFollowUp, "the user should still be able to retry")
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testAFailureFromTheCalendarIsSurfacedNotSwallowed() async {
        completeATask()
        scheduler.errorToThrow = FollowUpError.noDefaultList(.calendar)

        await model.scheduleFollowUp(.tomorrow)

        XCTAssertEqual(model.followUpError, .noDefaultList(.calendar))
        XCTAssertFalse(model.followUpError?.isPermissionProblem ?? true)
        XCTAssertNotNil(model.pendingFollowUp)
    }

    func testARecoveredFailureCanBeRetried() async {
        completeATask()
        scheduler.errorToThrow = FollowUpError.underlying("calendar busy")
        await model.scheduleFollowUp(.tomorrow)
        XCTAssertNotNil(model.followUpError)

        scheduler.errorToThrow = nil
        await model.scheduleFollowUp(.tomorrow)

        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertNil(model.followUpError)
        XCTAssertNil(model.pendingFollowUp)
    }

    func testSchedulingWithNoSchedulerFailsLoudly() async {
        model.scheduler = nil
        completeATask()

        await model.scheduleFollowUp(.tomorrow)

        XCTAssertNotNil(model.followUpError)
        XCTAssertNotNil(model.pendingFollowUp)
    }

    func testAFollowUpSurvivesReopeningTheStore() async {
        let task = completeATask()
        await model.scheduleFollowUp(.tomorrow)

        let reopened = Store(container: store.container)
        XCTAssertEqual(reopened.followUp(forTaskWith: task.id)?.taskTitle, "Ship the deck")
    }
}

@MainActor
final class FollowUpTargetTests: XCTestCase {
    private var store: Store!
    private var prefs: Preferences!
    private var model: AppModel!
    private var scheduler: FakeScheduler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try Store(inMemory: true)
        prefs = Preferences(store: InMemoryStore())
        scheduler = FakeScheduler()
        scheduler.targets = [
            FollowUpTarget(id: "cal-work", title: "Work", sourceName: "iCloud", isSystemDefault: true),
            FollowUpTarget(id: "cal-google", title: "Nawaf", sourceName: "Google", isSystemDefault: false),
        ]
        model = AppModel(store: store, prefs: prefs, clock: TestClock(),
                         scheduler: scheduler, autoTick: false)
    }

    private func completeATask() {
        model.draft = "Ship it"
        model.addDraftTask()
        model.complete(model.tasks[0])
    }

    func testNoTargetIsChosenByDefaultSoTheSystemDefaultIsUsed() async {
        XCTAssertNil(model.selectedTargetID(for: .calendar))
        completeATask()
        await model.scheduleFollowUp(.tomorrow)
        XCTAssertNil(scheduler.scheduled.first?.targetID, "nil means: let EventKit pick the default")
    }

    func testAChosenCalendarIsSentWithTheRequest() async {
        model.selectTarget("cal-google", for: .calendar)
        completeATask()
        await model.scheduleFollowUp(.tomorrow)
        XCTAssertEqual(scheduler.scheduled.first?.targetID, "cal-google")
    }

    func testTargetsAreRememberedSeparatelyPerDestination() {
        model.selectTarget("cal-google", for: .calendar)
        model.selectTarget("list-personal", for: .reminders)
        XCTAssertEqual(model.selectedTargetID(for: .calendar), "cal-google")
        XCTAssertEqual(model.selectedTargetID(for: .reminders), "list-personal")

        let reloaded = Preferences(store: InMemoryStore())
        XCTAssertNil(reloaded.followUpTargetID(for: .calendar), "a fresh store starts unset")
        XCTAssertEqual(prefs.followUpTargetID(for: .calendar), "cal-google", "and the real one persists")
    }

    func testClearingTheChoiceFallsBackToTheSystemDefault() async {
        model.selectTarget("cal-google", for: .calendar)
        model.selectTarget(nil, for: .calendar)
        completeATask()
        await model.scheduleFollowUp(.tomorrow)
        XCTAssertNil(scheduler.scheduled.first?.targetID)
    }

    func testTargetsAreListedOnlyWhenAccessIsGranted() async {
        let granted = await model.availableTargets(for: .calendar)
        XCTAssertEqual(granted.map(\.id), ["cal-work", "cal-google"])

        scheduler.accessGranted = false
        let denied = await model.availableTargets(for: .calendar)
        XCTAssertTrue(denied.isEmpty, "no access means no calendars to choose from")
    }

    func testTargetLabelReadsAsCalendarThenAccount() {
        XCTAssertEqual(scheduler.targets[1].label, "Nawaf — Google")
        XCTAssertEqual(
            FollowUpTarget(id: "x", title: "Work", sourceName: "", isSystemDefault: false).label,
            "Work"
        )
    }
}
