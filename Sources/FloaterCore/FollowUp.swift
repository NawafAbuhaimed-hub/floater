import Foundation

public enum FollowUpDestination: String, CaseIterable, Codable, Identifiable, Sendable {
    case calendar
    case reminders

    public var id: String { rawValue }
    public var title: String { self == .calendar ? "Calendar" : "Reminders" }
    public var symbol: String { self == .calendar ? "calendar" : "checklist" }
}

/// When a follow-up should land. Presets resolve to 9am on their day; `exact`
/// is whatever the user picked.
public enum FollowUpOffset: Equatable, Sendable {
    case tomorrow
    case days(Int)
    case nextWeek
    case exact(Date)

    public static let presets: [FollowUpOffset] = [.tomorrow, .days(3), .nextWeek]

    public static let presetHour = 9

    public var title: String {
        switch self {
        case .tomorrow: return "Tomorrow"
        case .days(let n): return "\(n) days"
        case .nextWeek: return "Next week"
        case .exact: return "Custom"
        }
    }

    /// Resolved against a calendar rather than by adding seconds, so a preset
    /// lands at 9am local time even across a DST change or a month boundary.
    public func resolve(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .exact(let date):
            return date
        case .tomorrow:
            return Self.morning(daysFromNow: 1, now: now, calendar: calendar)
        case .days(let n):
            return Self.morning(daysFromNow: n, now: now, calendar: calendar)
        case .nextWeek:
            return Self.morning(daysFromNow: 7, now: now, calendar: calendar)
        }
    }

    private static func morning(daysFromNow: Int, now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: startOfToday) ?? startOfToday
        // `bySettingHour` finds the real 9am even on a day that gains or loses one.
        return calendar.date(bySettingHour: presetHour, minute: 0, second: 0, of: day)
            ?? day.addingTimeInterval(TimeInterval(presetHour * 3600))
    }
}

/// A calendar or reminders list a follow-up can be written to.
public struct FollowUpTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// The account it belongs to — "Google", "iCloud", "On My Mac".
    public let sourceName: String
    public let isSystemDefault: Bool

    public init(id: String, title: String, sourceName: String, isSystemDefault: Bool) {
        self.id = id
        self.title = title
        self.sourceName = sourceName
        self.isSystemDefault = isSystemDefault
    }

    public var label: String { sourceName.isEmpty ? title : "\(title) — \(sourceName)" }
}

public struct FollowUpRequest: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var date: Date
    public var destination: FollowUpDestination
    /// Which calendar or list to write to. `nil` uses the system default.
    public var targetID: String?
    /// Length of the calendar event. Ignored for reminders.
    public var duration: TimeInterval

    public init(
        title: String,
        notes: String,
        date: Date,
        destination: FollowUpDestination,
        targetID: String? = nil,
        duration: TimeInterval = 15 * 60
    ) {
        self.title = title
        self.notes = notes
        self.date = date
        self.destination = destination
        self.targetID = targetID
        self.duration = duration
    }
}

public enum FollowUpError: Error, Equatable {
    case accessDenied(FollowUpDestination)
    case noDefaultList(FollowUpDestination)
    case underlying(String)

    public var message: String {
        switch self {
        case .accessDenied(let destination):
            return "Floater needs \(destination.title) access to add this."
        case .noDefaultList(let destination):
            return destination == .calendar
                ? "No default calendar is set for new events."
                : "No default list is set for new reminders."
        case .underlying(let text):
            return text
        }
    }

    /// Only a denial is worth sending the user to System Settings for.
    public var isPermissionProblem: Bool {
        if case .accessDenied = self { return true }
        return false
    }
}

/// Writing to Calendar or Reminders. Behind a protocol so the app model can be
/// tested without EventKit, permissions, or writing to a real calendar.
public protocol FollowUpScheduling: AnyObject {
    func requestAccess(to destination: FollowUpDestination) async -> Bool
    /// Calendars or lists that can be written to. Empty when access is not granted.
    func availableTargets(for destination: FollowUpDestination) async -> [FollowUpTarget]
    /// Returns the created item's external identifier.
    func schedule(_ request: FollowUpRequest) async throws -> String
}
