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
    /// Persisted as a string so adding cases never breaks an existing store.
    public var statusRaw: String = TaskStatus.notStarted.rawValue
    public var note: String = ""
    /// Calendar event logging this task's completion, so reopening can remove it.
    public var completionEventID: String = ""

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        plannedMinutes: Int? = nil,
        secondsSpent: Double = 0,
        order: Int = 0,
        status: TaskStatus = .notStarted,
        note: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.plannedMinutes = plannedMinutes
        self.secondsSpent = secondsSpent
        self.order = order
        self.statusRaw = status.rawValue
        self.note = note
    }

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .notStarted }
        set { statusRaw = newValue.rawValue }
    }

    public var isDone: Bool { status == .done }
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


/// The single global notes pane. One row, created on demand.
@Model
public final class Scratchpad {
    public var text: String = ""
    public var updatedAt: Date = Date()

    public init(text: String = "", updatedAt: Date = Date()) {
        self.text = text
        self.updatedAt = updatedAt
    }
}


/// A follow-up Floater created in Calendar or Reminders, kept so a finished
/// task can show that it has one.
@Model
public final class FollowUpRecord {
    public var id: UUID = UUID()
    public var taskID: UUID = UUID()
    public var taskTitle: String = ""
    public var scheduledFor: Date = Date()
    public var destinationRaw: String = FollowUpDestination.calendar.rawValue
    public var externalID: String = ""
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitle: String,
        scheduledFor: Date,
        destination: FollowUpDestination,
        externalID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.scheduledFor = scheduledFor
        self.destinationRaw = destination.rawValue
        self.externalID = externalID
        self.createdAt = createdAt
    }

    public var destination: FollowUpDestination {
        FollowUpDestination(rawValue: destinationRaw) ?? .calendar
    }
}


/// The visible chat transcript. Tool calls are not stored — the conversation is
/// replayed to the API as plain text, so a restored session never carries a
/// `tool_use` block without its result.
@Model
public final class ChatMessageRecord {
    public var id: UUID = UUID()
    public var roleRaw: String = "user"
    public var text: String = ""
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), role: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.roleRaw = role
        self.text = text
        self.createdAt = createdAt
    }

    public var isUser: Bool { roleRaw == "user" }
}
