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
    /// Slack truncates a status at 100 characters, so this builds from the most
    /// useful part outward and stops before it would be cut.
    public static let limit = 100

    public static func text(for stats: GameStats) -> String {
        var parts: [String] = []
        if stats.streakDays > 0 { parts.append("\(stats.streakDays)d streak") }
        parts.append("Lv \(stats.level)")
        if stats.goalTarget > 0 {
            parts.append(stats.goalKind == .tasks
                         ? "\(stats.goalDone)/\(stats.goalTarget) done"
                         : "\(stats.goalDone)/\(stats.goalTarget) min")
        }
        if stats.focusedTodaySeconds >= 60 {
            parts.append("\(stats.focusedTodaySeconds.compactDuration) focused")
        }

        var text = ""
        for part in parts {
            let candidate = text.isEmpty ? part : text + " · " + part
            if candidate.count > limit { break }
            text = candidate
        }
        return text
    }

    public static func emoji(for stats: GameStats) -> String {
        if stats.streakDays >= 7 { return ":fire:" }
        if stats.goalMet { return ":white_check_mark:" }
        if stats.focusedTodaySeconds > 0 { return ":hourglass_flowing_sand:" }
        return ":dart:"
    }
}
