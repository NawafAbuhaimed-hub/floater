import Foundation
import SwiftData

/// A category is a project. It carries the repo it maps to, so a task's
/// category is what tells the prompt generator which codebase to pull context
/// from later.
@Model
public final class TaskCategory {
    public var id: UUID = UUID()
    public var name: String = ""
    public var emoji: String = ""
    /// Hex without the leading hash, e.g. "30D158".
    public var colorHex: String = "8E8E93"
    /// Absolute path to the project this category means, when there is one.
    public var repoPath: String = ""
    public var order: Int = 0

    public init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "",
        colorHex: String = "8E8E93",
        repoPath: String = "",
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.repoPath = repoPath
        self.order = order
    }

    public var label: String { emoji.isEmpty ? name : "\(emoji) \(name)" }
    public var hasRepo: Bool { !repoPath.isEmpty }

    /// What a fresh install starts with — the user's actual projects, so
    /// categories are useful before any setup.
    public static func seeds(home: String) -> [TaskCategory] {
        [
            ("MNZIL CRM", "🏢", "0A84FF", "\(home)/mnzilpostsales"),
            ("CompoundOS", "🏗️", "BF5AF2", "\(home)/compoundos"),
            ("RED", "📐", "FF453A", "\(home)/mnzil-red"),
            ("Floater", "⏱️", "30D158", "\(home)/floater"),
            ("Hally", "👨‍👩‍👧", "FF9F0A", "\(home)/hally"),
            ("Personal", "🙂", "8E8E93", ""),
        ].enumerated().map { index, seed in
            TaskCategory(name: seed.0, emoji: seed.1, colorHex: seed.2, repoPath: seed.3, order: index)
        }
    }
}

/// How the task list is ordered.
public enum TaskSort: String, CaseIterable, Identifiable, Sendable {
    case status
    case dueDate
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .status: return "Status"
        case .dueDate: return "Due"
        case .manual: return "Manual"
        }
    }
}

/// How a due date reads right now. A finished task is never late.
public enum DueState: Equatable, Sendable {
    case none
    case upcoming
    case today
    case overdue
}

extension TaskStatus {
    /// In-progress first, done last — the order the list sorts by.
    var sortRank: Int {
        switch self {
        case .inProgress: return 0
        case .blocked: return 1
        case .notStarted: return 2
        case .done: return 3
        }
    }
}
