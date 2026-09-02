import Foundation
import SwiftData

/// Owns the SwiftData stack and exposes the task list as a plain array so the
/// AppKit layer can read it without going through `@Query`.
@MainActor
public final class Store {
    public let container: ModelContainer
    public private(set) var tasks: [TaskItem] = []
    public private(set) var followUps: [FollowUpRecord] = []
    public private(set) var chatMessages: [ChatMessageRecord] = []

    public var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let schema = Schema([TaskItem.self, FocusSessionRecord.self, Scratchpad.self, FollowUpRecord.self, ChatMessageRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [config])
        reload()
        reconcileLegacyStatuses()
    }

    /// Reopens an existing container — used to exercise what happens on the
    /// next launch against a store that already has rows in it.
    public init(container: ModelContainer) {
        self.container = container
        reload()
        reconcileLegacyStatuses()
    }

    /// Tasks created before statuses existed only carry `completedAt`. Without
    /// this they would come back as "Not started" despite being finished.
    private func reconcileLegacyStatuses() {
        var changed = false
        for task in tasks where task.completedAt != nil && task.status == .notStarted {
            task.status = .done
            changed = true
        }
        if changed { save() }
    }

    public func reload() {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        tasks = (try? context.fetch(descriptor)) ?? []
        reloadFollowUps()
        reloadChat()
    }

    // MARK: - Chat

    public func appendChat(role: String, text: String, at date: Date = Date()) {
        context.insert(ChatMessageRecord(role: role, text: text, createdAt: date))
        try? context.save()
        reloadChat()
    }

    public func clearChat() {
        for message in chatMessages { context.delete(message) }
        try? context.save()
        reloadChat()
    }

    private func reloadChat() {
        let descriptor = FetchDescriptor<ChatMessageRecord>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        chatMessages = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Queries

    public var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

    public func tasks(withStatus status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }
    }

    public func completedOn(_ day: Date, calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { task in
            guard let done = task.completedAt else { return false }
            return calendar.isDate(done, inSameDayAs: day)
        }
    }

    public func task(id: UUID) -> TaskItem? { tasks.first { $0.id == id } }

    // MARK: - Mutations

    @discardableResult
    public func add(title: String) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let nextOrder = (tasks.map(\.order).max() ?? -1) + 1
        let task = TaskItem(title: trimmed, order: nextOrder)
        context.insert(task)
        save()
        return task
    }

    public func complete(_ task: TaskItem, at date: Date = Date(), addingSeconds seconds: Double = 0) {
        task.status = .done
        task.completedAt = date
        task.secondsSpent += max(0, seconds)
        save()
    }

    public func reopen(_ task: TaskItem) {
        task.status = .notStarted
        task.completedAt = nil
        save()
    }

    /// `completedAt` is kept in lockstep with the status so "done today" stays
    /// accurate however the task got there.
    public func setStatus(_ status: TaskStatus, for task: TaskItem, at date: Date = Date()) {
        task.status = status
        task.completedAt = status == .done ? (task.completedAt ?? date) : nil
        save()
    }

    public func setCompletionEventID(_ eventID: String, forTaskWith id: UUID) {
        guard let task = task(id: id) else { return }
        task.completionEventID = eventID
        save()
    }

    public func updateNote(_ note: String, forTaskWith id: UUID) {
        guard let task = task(id: id), task.note != note else { return }
        task.note = note
        save()
    }

    public func delete(_ task: TaskItem) {
        context.delete(task)
        save()
    }

    public func addFocusTime(_ seconds: Double, toTaskWith id: UUID) {
        guard seconds > 0, let task = task(id: id) else { return }
        task.secondsSpent += seconds
        save()
    }

    public func rememberPlan(minutes: Int, forTaskWith id: UUID) {
        task(id: id)?.plannedMinutes = minutes
        save()
    }

    public func record(_ session: FocusSessionRecord) {
        context.insert(session)
        save()
    }

    /// Clears finished tasks. Their focus history stays in `FocusSessionRecord`.
    public func clearCompleted() {
        for task in tasks where task.isDone {
            context.delete(task)
        }
        save()
    }

    // MARK: - Follow-ups

    public func record(_ followUp: FollowUpRecord) {
        context.insert(followUp)
        try? context.save()
        reloadFollowUps()
    }

    /// The most recently created follow-up for a task, if any.
    public func followUp(forTaskWith id: UUID) -> FollowUpRecord? {
        followUps.filter { $0.taskID == id }.max { $0.createdAt < $1.createdAt }
    }

    private func reloadFollowUps() {
        followUps = (try? context.fetch(FetchDescriptor<FollowUpRecord>())) ?? []
    }

    // MARK: - Scratchpad

    /// The global notes pane, created the first time it is asked for.
    public var scratchpadText: String {
        get { scratchpad().text }
        set {
            let pad = scratchpad()
            guard pad.text != newValue else { return }
            pad.text = newValue
            pad.updatedAt = Date()
            try? context.save()
        }
    }

    private func scratchpad() -> Scratchpad {
        if let existing = try? context.fetch(FetchDescriptor<Scratchpad>()).first {
            return existing
        }
        let pad = Scratchpad()
        context.insert(pad)
        try? context.save()
        return pad
    }

    private func save() {
        try? context.save()
        reload()
    }
}
