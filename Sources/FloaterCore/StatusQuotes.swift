import Foundation

/// What the day looks like right now, which decides which kind of line fits.
public enum StatusMood: String, CaseIterable, Sendable {
    case inMeeting
    case heavyDay
    case focusing
    case blocked
    case behind
    case winning
    case fresh
    case windingDown
}

/// A day's calendar, reduced to what the status needs.
public struct DayEvents: Equatable, Sendable {
    public let total: Int
    public let inMeetingNow: Bool
    public let minutesToNext: Int?

    public init(total: Int, inMeetingNow: Bool, minutesToNext: Int?) {
        self.total = total
        self.inMeetingNow = inMeetingNow
        self.minutesToNext = minutesToNext
    }

    public static let none = DayEvents(total: 0, inMeetingNow: false, minutesToNext: nil)
}

public protocol CalendarReading: AnyObject, Sendable {
    func today(now: Date) async -> DayEvents
}

/// When the status is allowed to change: every three hours, 9am to 9pm, on the
/// working week. Outside those hours Floater leaves whatever is there alone
/// rather than announcing an empty evening.
public enum StatusSchedule {
    public static let slotHours = [9, 12, 15, 18, 21]

    /// Sunday through Friday. Saturday is the weekend here.
    public static func isWorkingDay(_ date: Date, calendar: Calendar) -> Bool {
        calendar.component(.weekday, from: date) != 7
    }

    /// The slot a moment belongs to, or nil when the status should not change.
    public static func slot(at date: Date, calendar: Calendar) -> Int? {
        guard isWorkingDay(date, calendar: calendar) else { return nil }
        let hour = calendar.component(.hour, from: date)
        guard hour >= slotHours.first!, hour < 24 else { return nil }
        // The 9pm slot runs to the end of the evening; before 9am there is none.
        return slotHours.last(where: { $0 <= hour })
    }

    /// Stable within a slot, different between them.
    public static func seed(at date: Date, calendar: Calendar) -> Int {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let slot = slotHours.firstIndex(of: self.slot(at: date, calendar: calendar) ?? 9) ?? 0
        return day * slotHours.count + slot
    }
}

/// Short lines from the films, chosen to suit the day. Iron Man, Spider-Man and
/// the Guardians, as requested.
public enum StatusQuotes {
    public static let signature = "by Floater ai"
    public static let limit = 100

    static let lines: [StatusMood: [String]] = [
        .inMeeting: [
            "Nothing goes over my head.",
            "I have a plan. Well, part of a plan.",
            "I'm something of a scientist myself.",
        ],
        .heavyDay: [
            "Sometimes you gotta run before you can walk.",
            "We are Groot.",
            "I can do this all day.",
        ],
        .focusing: [
            "I am Iron Man.",
            "JARVIS, you up?",
            "I am Groot.",
            "Ain't no thing like me, except me.",
        ],
        .blocked: [
            "Nobody's ever ready for the bad stuff.",
            "I have a plan. Well, part of a plan.",
            "This is going to be one of those days.",
        ],
        .behind: [
            "With great power comes great responsibility.",
            "I can do this all day.",
            "Part of the journey is the end.",
        ],
        .winning: [
            "I am Iron Man.",
            "Oh yeah. We're doing this.",
            "Star-Lord.",
            "Ain't no thing like me, except me.",
        ],
        .fresh: [
            "Your friendly neighbourhood Spider-Man.",
            "Oh yeah. We're doing this.",
            "I am Groot.",
            "Heroes are made by the paths they choose.",
        ],
        .windingDown: [
            "Part of the journey is the end.",
            "We are Groot.",
            "Nothing goes over my head.",
        ],
    ]

    static let emoji: [StatusMood: String] = [
        .inMeeting: ":speech_balloon:",
        .heavyDay: ":calendar:",
        .focusing: ":mechanical_arm:",
        .blocked: ":spider_web:",
        .behind: ":hourglass_flowing_sand:",
        .winning: ":rocket:",
        .fresh: ":sunrise:",
        .windingDown: ":crescent_moon:",
    ]

    /// First match wins, most specific first.
    public static func mood(
        events: DayEvents, focusing: Bool, overdue: Int, blocked: Int,
        goalMet: Bool, slot: Int
    ) -> StatusMood {
        if events.inMeetingNow { return .inMeeting }
        if focusing { return .focusing }
        if slot >= 21 { return .windingDown }
        if overdue > 0 { return .behind }
        if blocked > 0 { return .blocked }
        if events.total >= 4 { return .heavyDay }
        if goalMet { return .winning }
        return .fresh
    }

    public static func text(for mood: StatusMood, seed: Int) -> String {
        let pool = lines[mood] ?? lines[.fresh]!
        let line = pool[((seed % pool.count) + pool.count) % pool.count]
        let full = "\(line) — \(signature)"
        // Slack truncates at 100; drop the line rather than the signature, since
        // the signature is the part that was asked for.
        return full.count <= limit ? full : signature
    }

    public static func emoji(for mood: StatusMood) -> String {
        emoji[mood] ?? ":sparkles:"
    }
}
