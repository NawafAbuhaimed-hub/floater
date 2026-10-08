import XCTest
@testable import FloaterCore

final class StatusScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return cal
    }()

    private func at(_ string: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: string)!
    }

    // 2026-10-04 is a Sunday; 2026-10-10 is a Saturday.

    func testTheWorkingWeekRunsSundayToFriday() {
        XCTAssertTrue(StatusSchedule.isWorkingDay(at("2026-10-04 10:00"), calendar: calendar), "Sunday")
        XCTAssertTrue(StatusSchedule.isWorkingDay(at("2026-10-09 10:00"), calendar: calendar), "Friday")
        XCTAssertFalse(StatusSchedule.isWorkingDay(at("2026-10-10 10:00"), calendar: calendar), "Saturday")
    }

    func testSaturdayNeverGetsASlot() {
        for hour in [9, 12, 15, 18, 21] {
            XCTAssertNil(StatusSchedule.slot(at: at("2026-10-10 \(hour):00"), calendar: calendar))
        }
    }

    func testTheDayStartsAtNineAndNotBefore() {
        XCTAssertNil(StatusSchedule.slot(at: at("2026-10-04 08:59"), calendar: calendar))
        XCTAssertEqual(StatusSchedule.slot(at: at("2026-10-04 09:00"), calendar: calendar), 9)
        XCTAssertNil(StatusSchedule.slot(at: at("2026-10-04 03:00"), calendar: calendar))
    }

    func testEachThreeHourBlockIsItsOwnSlot() {
        let expected: [(String, Int)] = [
            ("09:00", 9), ("11:59", 9),
            ("12:00", 12), ("14:30", 12),
            ("15:00", 15), ("17:59", 15),
            ("18:00", 18), ("20:59", 18),
            ("21:00", 21), ("23:30", 21),
        ]
        for (time, slot) in expected {
            XCTAssertEqual(StatusSchedule.slot(at: at("2026-10-04 \(time)"), calendar: calendar),
                           slot, time)
        }
    }

    func testTheSeedHoldsWithinASlotAndMovesBetweenThem() {
        let early = StatusSchedule.seed(at: at("2026-10-04 09:05"), calendar: calendar)
        let late = StatusSchedule.seed(at: at("2026-10-04 11:55"), calendar: calendar)
        let next = StatusSchedule.seed(at: at("2026-10-04 12:05"), calendar: calendar)
        let tomorrow = StatusSchedule.seed(at: at("2026-10-05 09:05"), calendar: calendar)

        XCTAssertEqual(early, late, "the line must not churn inside a slot")
        XCTAssertNotEqual(early, next)
        XCTAssertNotEqual(early, tomorrow)
    }
}

final class StatusQuoteTests: XCTestCase {
    func testEveryLineFitsSlackWithTheSignature() {
        for mood in StatusMood.allCases {
            for seed in 0..<12 {
                let text = StatusQuotes.text(for: mood, seed: seed)
                XCTAssertLessThanOrEqual(text.count, StatusQuotes.limit, text)
                XCTAssertTrue(text.hasSuffix(StatusQuotes.signature),
                              "the signature is the part that was asked for: \(text)")
            }
        }
    }

    func testTheLineNeverCarriesANumberOrATaskTitle() {
        for mood in StatusMood.allCases {
            for seed in 0..<12 {
                let text = StatusQuotes.text(for: mood, seed: seed)
                XCTAssertNil(text.rangeOfCharacter(from: .decimalDigits), text)
            }
        }
    }

    func testTheSameSeedAlwaysGivesTheSameLine() {
        XCTAssertEqual(StatusQuotes.text(for: .focusing, seed: 7),
                       StatusQuotes.text(for: .focusing, seed: 7))
    }

    func testANegativeSeedStillLandsInThePool() {
        let text = StatusQuotes.text(for: .fresh, seed: -5)
        XCTAssertTrue(text.hasSuffix(StatusQuotes.signature), text)
    }

    func testEveryMoodHasLinesAndAnEmoji() {
        for mood in StatusMood.allCases {
            XCTAssertFalse(StatusQuotes.lines[mood]?.isEmpty ?? true, "\(mood) has no lines")
            XCTAssertFalse(StatusQuotes.emoji(for: mood).isEmpty)
        }
    }

    // MARK: - Which line the day earns

    private func mood(events: DayEvents = .none, focusing: Bool = false, overdue: Int = 0,
                      blocked: Int = 0, goalMet: Bool = false, slot: Int = 12) -> StatusMood {
        StatusQuotes.mood(events: events, focusing: focusing, overdue: overdue,
                          blocked: blocked, goalMet: goalMet, slot: slot)
    }

    func testBeingInAMeetingBeatsEverythingElse() {
        let inOne = DayEvents(total: 6, inMeetingNow: true, minutesToNext: nil)
        XCTAssertEqual(mood(events: inOne, focusing: true, overdue: 3), .inMeeting)
    }

    func testARunningTimerReadsAsFocus() {
        XCTAssertEqual(mood(focusing: true, overdue: 2), .focusing)
    }

    func testAPackedCalendarReadsAsAHeavyDay() {
        XCTAssertEqual(mood(events: DayEvents(total: 5, inMeetingNow: false, minutesToNext: 30)),
                       .heavyDay)
        XCTAssertNotEqual(mood(events: DayEvents(total: 2, inMeetingNow: false, minutesToNext: 30)),
                          .heavyDay, "two meetings is not a heavy day")
    }

    func testOverdueWorkOutranksBlockedWork() {
        XCTAssertEqual(mood(overdue: 1, blocked: 4), .behind)
        XCTAssertEqual(mood(overdue: 0, blocked: 1), .blocked)
    }

    func testTheLastSlotWindsDown() {
        XCTAssertEqual(mood(slot: 21), .windingDown)
        XCTAssertEqual(mood(overdue: 3, slot: 21), .windingDown,
                       "nine in the evening is not the time to be told you are behind")
    }

    func testHittingTheGoalIsWorthCelebrating() {
        XCTAssertEqual(mood(goalMet: true), .winning)
    }

    func testAnOrdinaryMorningIsJustFresh() {
        XCTAssertEqual(mood(slot: 9), .fresh)
    }
}

extension StatusQuoteTests {
    /// The status goes to a work Slack, so the pool stays work-appropriate.
    func testNoLineCarriesWordsUnwantedInAWorkStatus() {
        let unwanted = ["playboy", "damn", "hell", "kill", "drunk", "stupid"]
        for mood in StatusMood.allCases {
            for line in StatusQuotes.lines[mood] ?? [] {
                for word in unwanted {
                    XCTAssertFalse(line.lowercased().contains(word),
                                   "\(mood): \(line) contains \"\(word)\"")
                }
            }
        }
    }
}
