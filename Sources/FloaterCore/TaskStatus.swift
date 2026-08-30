import Foundation

public enum TaskStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case notStarted
    case inProgress
    case blocked
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notStarted: return "Not started"
        case .inProgress: return "In progress"
        case .blocked: return "Blocked"
        case .done: return "Done"
        }
    }

    public var symbol: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .blocked: return "exclamationmark.octagon.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    /// Statuses that still need work, used for the "waiting" count on the pill.
    public var isOpen: Bool { self != .done }
}
