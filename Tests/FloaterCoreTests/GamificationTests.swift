import XCTest
@testable import FloaterCore

final class GamificationRuleTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    // MARK: - XP

    func testAFinishedTaskIsWorthTheBaseEvenWithNoTimer() {
        XCTAssertEqual(Gamification.xp(secondsFocused: 0), 10)
    }

    func testFocusedTimeAddsToTheBase() {
        XCTAssertEqual(Gamification.xp(secondsFocused: 45 * 60), 10 + 9)
        XCTAssertEqual(Gamification.xp(secondsFocused: 15 * 60), 10 + 3)
    }

    func testPartialMinutesDoNotEarnAnything() {
        XCTAssertEqual(Gamification.xp(secondsFocused: 4 * 60 + 59), 10)
    }

    func testNegativeTimeCannotReduceTheAward() {
        XCTAssertEqual(Gamification.xp(secondsFocused: -500), 10)
    }

    // MARK: - Levels

    func testLevellingStartsAtOneWithNothing() {
        let progression = Gamification.level(forTotalXP: 0)
        XCTAssertEqual(progression.level, 1)
        XCTAssertEqual(progression.into, 0)
        XCTAssertEqual(progression.needed, 100)
    }

    func testTheFirstLevelTakesAHundred() {
        XCTAssertEqual(Gamification.level(forTotalXP: 99).level, 1)
        XCTAssertEqual(Gamification.level(forTotalXP: 100).level, 2)
        XCTAssertEqual(Gamification.level(forTotalXP: 100).into, 0)
    }

    func testEachLevelCostsMoreThanTheLast() {
        XCTAssertEqual(Gamification.xpNeeded(forLevel: 1), 100)
        XCTAssertEqual(Gamification.xpNeeded(forLevel: 2), 150)
        XCTAssertEqual(Gamification.xpNeeded(forLevel: 5), 300)
        // 100 + 150 + 200 = 450 reaches level 4 exactly.
        XCTAssertEqual(Gamification.level(forTotalXP: 450).level, 4)
        XCTAssertEqual(Gamification.level(forTotalXP: 449).level, 3)
    }

    func testProgressWithinALevelIsReported() {
        let progression = Gamification.level(forTotalXP: 160)
        XCTAssertEqual(progression.level, 2)
        XCTAssertEqual(progression.into, 60)
        XCTAssertEqual(progression.needed, 150)
    }

    // MARK: - Streaks

    func testNoCompletionsMeansNoStreak() {
        XCTAssertEqual(Gamification.streak(completionDates: [], now: date("2026-03-10 12:00"),
                                           calendar: calendar), 0)
    }

    func testConsecutiveDaysCount() {
        let dates = ["2026-03-10 09:00", "2026-03-09 14:00", "2026-03-08 20:00"].map(date)
        XCTAssertEqual(Gamification.streak(completionDates: dates,
                                           now: date("2026-03-10 18:00"), calendar: calendar), 3)
    }

    func testSeveralCompletionsOnOneDayCountOnce() {
        let dates = ["2026-03-10 09:00", "2026-03-10 11:00", "2026-03-09 14:00"].map(date)
        XCTAssertEqual(Gamification.streak(completionDates: dates,
                                           now: date("2026-03-10 18:00"), calendar: calendar), 2)
    }

    func testAStreakSurvivesADayThatHasNotFinishedYet() {
        // Nothing done today, but yesterday and the day before were.
        let dates = ["2026-03-09 14:00", "2026-03-08 20:00"].map(date)
        XCTAssertEqual(Gamification.streak(completionDates: dates,
                                           now: date("2026-03-10 09:00"), calendar: calendar), 2,
                       "a streak should not break at midnight, only after a day is missed")
    }

    func testMissingAWholeDayBreaksIt() {
        let dates = ["2026-03-08 14:00", "2026-03-07 20:00"].map(date)
        XCTAssertEqual(Gamification.streak(completionDates: dates,
                                           now: date("2026-03-10 09:00"), calendar: calendar), 0)
    }

    func testAGapEndsTheCountRatherThanSkippingIt() {
        let dates = ["2026-03-10 09:00", "2026-03-09 09:00", "2026-03-06 09:00"].map(date)
        XCTAssertEqual(Gamification.streak(completionDates: dates,
                                           now: date("2026-03-10 18:00"), calendar: calendar), 2)
    }

    // MARK: - Badges

    private func input(completed: Int = 0, session: Int = 0, streak: Int = 0,
                       bestDay: Double = 0, cleared: Bool = false,
                       early: Bool = false, late: Bool = false) -> Gamification.BadgeInput {
        .init(totalCompleted: completed, longestSessionMinutes: session, streakDays: streak,
              bestDayFocusedSeconds: bestDay, clearedAFullDay: cleared,
              completedBefore7am: early, completedAfterMidnight: late)
    }

    func testNothingIsEarnedOnAFreshInstall() {
        XCTAssertTrue(Gamification.badges(input()).allSatisfy { !$0.earned })
    }

    func testBadgesUnlockAtTheirThreshold() {
        func earned(_ i: Gamification.BadgeInput) -> Set<String> {
            Set(Gamification.badges(i).filter(\.earned).map(\.id))
        }
        XCTAssertEqual(earned(input(completed: 1)), ["first"])
        XCTAssertTrue(earned(input(completed: 10)).contains("ten"))
        XCTAssertTrue(earned(input(completed: 100)).contains("hundred"))
        XCTAssertTrue(earned(input(session: 45)).contains("deep"))
        XCTAssertFalse(earned(input(session: 30)).contains("deep"))
        XCTAssertTrue(earned(input(streak: 7)).contains("week"))
        XCTAssertFalse(earned(input(streak: 6)).contains("week"))
        XCTAssertTrue(earned(input(bestDay: 4 * 3600)).contains("marathon"))
        XCTAssertTrue(earned(input(cleared: true)).contains("sweep"))
    }

    func testEveryBadgeHasAnUnlockHint() {
        for badge in Gamification.badges(input()) {
            XCTAssertFalse(badge.detail.isEmpty, "\(badge.id) needs to say how to earn it")
            XCTAssertFalse(badge.symbol.isEmpty)
        }
    }
}

final class SlackStatusTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    private func stats(streak: Int = 0, done: Int = 3, target: Int = 5) -> GameStats {
        GameStats(totalXP: 400, level: 3, xpIntoLevel: 50, xpNeededForLevel: 200,
                  streakDays: streak, completedToday: done, focusedTodaySeconds: 3600,
                  goalKind: .tasks, goalTarget: target, badges: [])
    }

    /// The only number allowed anywhere is the streak's day count. No task
    /// totals, no level, no goal progress — a status is not a scoreboard.
    func testTheOnlyNumberEverShownIsTheStreak() {
        let moments = (0..<48).map { date("2026-03-10 00:00").addingTimeInterval(Double($0) * 3600) }
        for focusing in [true, false] {
            for streak in [0, 2, 3, 12] {
                for moment in moments {
                    let text = SlackStatus.text(for: stats(streak: streak), focusing: focusing,
                                                at: moment, calendar: calendar)
                    let digits = text.filter(\.isNumber)
                    let onStreakLine = !focusing && streak >= 3
                    XCTAssertEqual(digits, onStreakLine ? String(streak) : "",
                                   "unexpected number in: \(text)")
                    XCTAssertFalse(text.contains("/"), text)
                    XCTAssertFalse(text.contains("Lv"), text)
                    XCTAssertFalse(text.lowercased().contains("xp"), text)
                }
            }
        }
    }

    func testAStatusNeverCarriesWhatIsBeingWorkedOn() {
        // There is no parameter for it, which is the point: a task title cannot
        // reach the workspace even by accident.
        let text = SlackStatus.text(for: stats(streak: 5), focusing: true,
                                    at: date("2026-03-10 10:00"), calendar: calendar)
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(SlackStatus.focusing.contains(text), text)
    }

    func testFocusingAndIdleReadDifferently() {
        let moment = date("2026-03-10 10:00")
        let working = SlackStatus.text(for: stats(), focusing: true, at: moment, calendar: calendar)
        let resting = SlackStatus.text(for: stats(), focusing: false, at: moment, calendar: calendar)
        XCTAssertNotEqual(working, resting)
        XCTAssertTrue(SlackStatus.focusing.contains(working))
        XCTAssertTrue(SlackStatus.idle.contains(resting))
    }

    func testAStreakGetsItsOwnLineWithTheNumberOfDays() {
        let text = SlackStatus.text(for: stats(streak: 12), focusing: false,
                                    at: date("2026-03-10 10:00"), calendar: calendar)
        XCTAssertTrue(text.contains("12"), text)
        XCTAssertFalse(SlackStatus.idle.contains(text))
    }

    func testAShortStreakStillReadsAsIdle() {
        let text = SlackStatus.text(for: stats(streak: 2), focusing: false,
                                    at: date("2026-03-10 10:00"), calendar: calendar)
        XCTAssertTrue(SlackStatus.idle.contains(text), text)
    }

    func testTheLineIsStableWithinAnHourAndChangesAcrossHours() {
        let early = date("2026-03-10 10:05")
        let later = date("2026-03-10 10:55")
        let nextHour = date("2026-03-10 11:05")
        func line(_ moment: Date) -> String {
            SlackStatus.text(for: stats(), focusing: false, at: moment, calendar: calendar)
        }
        XCTAssertEqual(line(early), line(later), "it must not churn, or Slack is written to constantly")
        XCTAssertNotEqual(line(early), line(nextHour))
    }

    func testEveryLineFitsSlacksLimit() {
        for line in SlackStatus.focusing + SlackStatus.idle {
            XCTAssertLessThanOrEqual(line.count, SlackStatus.limit, line)
        }
        for template in SlackStatus.onAStreak {
            XCTAssertLessThanOrEqual(String(format: template, 999).count, SlackStatus.limit, template)
        }
    }

    func testTheEmojiFollowsTheState() {
        XCTAssertEqual(SlackStatus.emoji(for: stats(), focusing: true), ":hourglass_flowing_sand:")
        XCTAssertEqual(SlackStatus.emoji(for: stats(streak: 7), focusing: false), ":fire:")
        XCTAssertEqual(SlackStatus.emoji(for: stats(streak: 3), focusing: false), ":zap:")
        XCTAssertEqual(SlackStatus.emoji(for: stats(), focusing: false), ":coffee:")
    }
}

@MainActor
final class SlackSyncTests: XCTestCase {
    /// Records what would have been sent to Slack.
    final class FakeSlack: SlackPosting, @unchecked Sendable {
        private(set) var statuses: [(text: String, emoji: String)] = []
        private(set) var posts: [(text: String, channel: String?)] = []
        var failWith: Error?

        func setStatus(text: String, emoji: String) async throws {
            if let failWith { throw failWith }
            statuses.append((text, emoji))
        }
        @discardableResult
        func post(text: String, channel: String?) async throws -> String {
            if let failWith { throw failWith }
            posts.append((text, channel))
            return channel ?? "self"
        }
    }

    private var clock: TestClock!
    private var model: AppModel!
    private var slack: FakeSlack!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        slack = FakeSlack()
        model = AppModel(store: try Store(inMemory: true),
                         prefs: Preferences(store: InMemoryStore()),
                         clock: clock, autoTick: false)
        model.slack = slack
        model.logCompletions = false
    }

    func testNothingIsSentUntilTheUserTurnsItOn() async {
        XCTAssertFalse(model.slackStatusEnabled, "Floater must not touch anyone's Slack uninvited")
        await model.syncSlackStatus(force: true)
        XCTAssertTrue(slack.statuses.isEmpty)
    }

    /// Switching the toggle pushes on its own, so settle that before measuring.
    private func enableAndSettle() async -> Int {
        model.slackStatusEnabled = true
        for _ in 0..<20 { await Task.yield() }
        return slack.statuses.count
    }

    func testTurningItOnPushesImmediately() async {
        let pushes = await enableAndSettle()
        XCTAssertEqual(pushes, 1, "switching it on should show the current figures at once")
    }

    func testAnUnchangedStatusIsNotSentAgainStraightAway() async {
        let baseline = await enableAndSettle()
        await model.syncSlackStatus()
        await model.syncSlackStatus()
        XCTAssertEqual(slack.statuses.count, baseline, "Slack should not be written to on every tick")
    }

    func testAStaleStatusIsRefreshedEvenWhenUnchanged() async {
        let baseline = await enableAndSettle()
        clock.advance(AppModel.slackRefreshInterval + 1)
        await model.syncSlackStatus()
        XCTAssertEqual(slack.statuses.count, baseline + 1,
                       "the day's figures must not go stale on screen")
    }

    func testTurningItOffClearsWhatWasSet() async {
        _ = await enableAndSettle()
        await model.clearSlackStatus()
        XCTAssertEqual(slack.statuses.last?.text, "")
        XCTAssertEqual(slack.statuses.last?.emoji, "")
    }

    func testATransientFailureIsReportedAndDoesNotThrow() async {
        // A dead token is handled separately, in SlackTokenDeathTests.
        slack.failWith = SlackError.api("ratelimited")
        model.slackStatusEnabled = true
        await model.syncSlackStatus(force: true)
        XCTAssertEqual(model.slackError, SlackError.api("ratelimited").message)
        XCTAssertTrue(model.slackStatusEnabled, "a rate limit is not a disconnection")
    }

    func testStartingATimerSwitchesTheStatusToFocusing() async {
        _ = await enableAndSettle()
        model.draft = "Something"
        model.addDraftTask()

        model.start(model.tasks[0], minutes: 25)
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(SlackStatus.focusing.contains(slack.statuses.last?.text ?? ""),
                      slack.statuses.last?.text ?? "")
        XCTAssertEqual(slack.statuses.last?.emoji, ":hourglass_flowing_sand:")
    }

    func testStoppingATimerPutsItBack() async {
        _ = await enableAndSettle()
        model.draft = "Something"
        model.addDraftTask()
        model.start(model.tasks[0], minutes: 25)
        for _ in 0..<20 { await Task.yield() }

        model.stopTimer()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(SlackStatus.focusing.contains(slack.statuses.last?.text ?? ""),
                       slack.statuses.last?.text ?? "")
    }

    func testFinishingATaskDoesNotChurnTheStatus() async {
        let before = await enableAndSettle()
        model.draft = "Something"
        model.addDraftTask()

        model.complete(model.tasks[0])
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(slack.statuses.count, before,
                       "the status says nothing about task counts, so finishing one changes nothing")
    }
}
