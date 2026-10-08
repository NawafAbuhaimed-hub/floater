import XCTest
import Combine
@testable import FloaterCore

/// Counts how often the store is actually read, so a cheap tick stays cheap.
@MainActor
final class CountingStore: Store {
    private(set) var reloads = 0
    override func reload() {
        reloads += 1
        super.reload()
    }
}

@MainActor
final class TickCostTests: XCTestCase {
    private var clock: TestClock!
    private var store: CountingStore!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        store = try CountingStore(inMemory: true)
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
        model.logCompletions = false
    }

    private func startATimer() {
        model.draft = "Something"
        model.addDraftTask()
        model.start(model.tasks[0], minutes: 15)
    }

    func testAPlainTickDoesNotTouchTheStore() {
        startATimer()
        let before = store.reloads

        for _ in 0..<40 {
            clock.advance(0.25)
            model.refreshTimerDisplay()
        }

        XCTAssertEqual(store.reloads, before,
                       "a countdown changing is not a reason to re-read the database")
    }

    func testTheDisplayStillKeepsUpWithTheClock() {
        startATimer()
        XCTAssertEqual(model.remainingText, "15:00")

        clock.advance(61)
        model.refreshTimerDisplay()

        XCTAssertEqual(model.remainingText, "13:59")
        XCTAssertGreaterThan(model.progress, 0)
    }

    func testAFullRefreshStillReadsEverything() {
        startATimer()
        let before = store.reloads
        model.refresh()
        XCTAssertGreaterThan(store.reloads, before)
    }

    func testReachingZeroStillFiresAndRefreshes() {
        var fired = 0
        model.onTimeUp = { _ in fired += 1 }
        startATimer()

        clock.advance(15 * 60)
        model.tick()

        XCTAssertEqual(fired, 1)
        XCTAssertEqual(model.phase, .elapsed)
    }
}

@MainActor
final class SlackTokenDeathTests: XCTestCase {
    final class FailingSlack: SlackPosting, @unchecked Sendable {
        var error: SlackError = .api("invalid_auth")
        private(set) var attempts = 0
        func setStatus(text: String, emoji: String) async throws {
            attempts += 1
            throw error
        }
        @discardableResult
        func post(text: String, channel: String?) async throws -> String { throw error }
    }

    private var secrets: InMemorySecretStore!
    private var model: AppModel!
    private var slack: FailingSlack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        secrets = InMemorySecretStore([.slack: "xoxp-dead"])
        slack = FailingSlack()
        // The status only pushes inside its window, so the clock has to sit in
        // one for the failure path to be reached at all.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        let formatter = DateFormatter()
        formatter.calendar = cal
        formatter.timeZone = cal.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        model = AppModel(store: try Store(inMemory: true),
                         prefs: Preferences(store: InMemoryStore()),
                         clock: TestClock(now: formatter.date(from: "2026-10-04 10:00")!),
                         calendar: cal, secrets: secrets, autoTick: false)
        model.slack = slack
    }

    func testARevokedTokenSwitchesTheFeatureOffInsteadOfRetryingForever() async {
        model.slackStatusEnabled = true
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(model.slackStatusEnabled, "a dead token must not be retried every few minutes")
        XCTAssertNil(secrets.secret(.slack), "a dead token is worse than none")
        XCTAssertTrue(model.slackError?.contains("revoked or expired") ?? false, model.slackError ?? "")

        let attemptsAfterDeath = slack.attempts
        await model.syncSlackStatus()
        await model.syncSlackStatus()
        XCTAssertEqual(slack.attempts, attemptsAfterDeath, "and must stop trying")
    }

    func testATemporaryFailureDoesNotDisconnectAnything() async {
        slack.error = .api("ratelimited")
        model.slackStatusEnabled = true
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(model.slackStatusEnabled, "a transient error is not a reason to disconnect")
        XCTAssertEqual(secrets.secret(.slack), "xoxp-dead")
    }
}

@MainActor
final class PublishCostTests: XCTestCase {
    private var clock: TestClock!
    private var model: AppModel!
    private var changes = 0
    private var bag: AnyCancellable?

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        model = AppModel(store: try Store(inMemory: true),
                         prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
        model.logCompletions = false
        bag = model.objectWillChange.sink { [weak self] _ in self?.changes += 1 }
    }

    func testAnIdleTickPublishesNothing() {
        changes = 0
        for _ in 0..<40 {
            clock.advance(0.25)
            model.refreshTimerDisplay()
        }
        XCTAssertEqual(changes, 0, "an idle app must not redraw itself four times a second")
    }

    func testARunningTimerPublishesAboutOncePerSecondNotFourTimes() {
        model.draft = "Something"
        model.addDraftTask()
        model.start(model.tasks[0], minutes: 15)
        changes = 0

        // Ten seconds at four ticks a second.
        for _ in 0..<40 {
            clock.advance(0.25)
            model.refreshTimerDisplay()
        }

        // Two sources: the second changing (~10) and the progress ring crossing
        // its threshold (~5). Forty ticks produced forty publishes before.
        XCTAssertLessThanOrEqual(changes, 18, "\(changes) publishes for 10 seconds of ticking")
        XCTAssertGreaterThanOrEqual(changes, 8, "but it must still keep up with the clock")
    }
}
