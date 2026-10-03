import Foundation

public enum SlackError: Error, Equatable {
    case notConnected
    case api(String)
    case transport(String)

    public var message: String {
        switch self {
        case .notConnected: return "Add a Slack token to post from Floater."
        case .api(let code): return "Slack said: \(code)"
        case .transport(let text): return "Network problem talking to Slack: \(text)"
        }
    }
}

public protocol SlackPosting: AnyObject, Sendable {
    func setStatus(text: String, emoji: String) async throws
    /// Returns the channel the message landed in.
    @discardableResult
    func post(text: String, channel: String?) async throws -> String
}

public enum SlackStatus {
    /// Slack cuts a status at 100 characters.
    public static let limit = 100

    /// Deliberately no task counts and no task titles. Counts turn a status
    /// into a scoreboard, and titles would put whatever the user is working on
    /// — client names included — in front of the whole workspace.
    static let focusing = [
        "heads down, do not perceive me",
        "in the zone. send snacks",
        "focusing. aggressively.",
        "brain fully charged, body on fumes",
        "locked in 🔒",
        "currently outsmarting my own to-do list",
        "deep work or a convincing impression of it",
        "timer running, excuses paused",
    ]

    static let onAStreak = [
        "day %d of pretending I have it together",
        "%d days straight. unstoppable. ish.",
        "on a %d-day heater",
        "streak: %d. ego: unmanageable.",
        "%d days in a row. someone stop me.",
    ]

    static let idle = [
        "technically working",
        "between tasks, emotionally",
        "looking busy",
        "my to-do list and I are not speaking",
        "touching grass (metaphorically)",
        "rebooting the human",
        "in the gap between two good ideas",
    ]

    /// Changes at most once an hour, so the status has variety without Floater
    /// writing to Slack every tick.
    static func seed(at date: Date, calendar: Calendar) -> Int {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let hour = calendar.component(.hour, from: date)
        return day * 24 + hour
    }

    public static func text(
        for stats: GameStats,
        focusing: Bool,
        at date: Date,
        calendar: Calendar = .current
    ) -> String {
        let index = seed(at: date, calendar: calendar)
        let line: String
        if focusing {
            line = focusing_(index)
        } else if stats.streakDays >= 3 {
            line = String(format: onAStreak[index % onAStreak.count], stats.streakDays)
        } else {
            line = idle[index % idle.count]
        }
        return String(line.prefix(limit))
    }

    private static func focusing_(_ index: Int) -> String {
        focusing[index % focusing.count]
    }

    public static func emoji(for stats: GameStats, focusing: Bool) -> String {
        if focusing { return ":hourglass_flowing_sand:" }
        if stats.streakDays >= 7 { return ":fire:" }
        if stats.streakDays >= 3 { return ":zap:" }
        return ":coffee:"
    }
}
