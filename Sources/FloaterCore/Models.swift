import Foundation
import SwiftData

@Model
public final class TaskItem {
    public var id: UUID = UUID()
    public var title: String = ""
    public var createdAt: Date = Date()
    public var completedAt: Date?
    /// Last timer length chosen for this task, in minutes.
    public var plannedMinutes: Int?
    /// Total focused time banked against this task.
    public var secondsSpent: Double = 0
    public var order: Int = 0

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        plannedMinutes: Int? = nil,
        secondsSpent: Double = 0,
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.plannedMinutes = plannedMinutes
        self.secondsSpent = secondsSpent
        self.order = order
    }

    public var isDone: Bool { completedAt != nil }
}

@Model
public final class FocusSessionRecord {
    public var id: UUID = UUID()
    public var taskID: UUID = UUID()
    public var taskTitle: String = ""
    public var startedAt: Date = Date()
    public var endedAt: Date?
    public var plannedMinutes: Int = 0
    public var secondsFocused: Double = 0
    public var completedTask: Bool = false

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitle: String,
        startedAt: Date,
        endedAt: Date? = nil,
        plannedMinutes: Int,
        secondsFocused: Double = 0,
        completedTask: Bool = false
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
        self.secondsFocused = secondsFocused
        self.completedTask = completedTask
    }
}
