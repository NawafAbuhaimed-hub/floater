import Foundation
import SwiftData

/// Owns the SwiftData stack and exposes the task list as a plain array so the
/// AppKit layer can read it without going through `@Query`.
@MainActor
public class Store {
    public let container: ModelContainer
    /// Everything ever recorded, archived included. Statistics and the digest
    /// read this, so hiding finished work never changes the figures.
    public private(set) var allTasks: [TaskItem] = []
    /// What the list shows.
    public private(set) var tasks: [TaskItem] = []
    public private(set) var followUps: [FollowUpRecord] = []
    public private(set) var chatMessages: [ChatMessageRecord] = []
    public private(set) var categories: [TaskCategory] = []

    public var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let schema = Schema([TaskItem.self, FocusSessionRecord.self, Scratchpad.self, FollowUpRecord.self, ChatMessageRecord.self, TaskCategory.self])
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
        allTasks = (try? context.fetch(descriptor)) ?? []
        tasks = allTasks.filter { !$0.isArchived }
        reloadFollowUps()
        reloadChat()
        reloadCategories()
    }

    // MARK: - Categories

    /// Seeds the user's real projects the first time, so categories are useful
    /// before any setup. Never re-seeds, so deleting one keeps it deleted.
    public func seedCategoriesIfEmpty(home: String) {
        guard categories.isEmpty else { return }
        for category in TaskCategory.seeds(home: home) { context.insert(category) }
        try? context.save()
        reloadCategories()
    }

    public func category(id: UUID?) -> TaskCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    @discardableResult
    public func addCategory(name: String, emoji: String = "", colorHex: String = "8E8E93",
                            repoPath: String = "") -> TaskCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let next = (categories.map(\.order).max() ?? -1) + 1
        let category = TaskCategory(name: trimmed, emoji: emoji, colorHex: colorHex,
                                    repoPath: repoPath, order: next)
        context.insert(category)
        try? context.save()
        reloadCategories()
        return category
    }

    /// Removing a category leaves its tasks uncategorised rather than deleting them.
    public func deleteCategory(_ category: TaskCategory) {
        let id = category.id
        for task in tasks where task.categoryID == id { task.categoryID = nil }
        context.delete(category)
        save()
        reloadCategories()
    }

    public func setCategory(_ categoryID: UUID?, forTaskWith id: UUID) {
        guard let task = task(id: id) else { return }
        task.categoryID = categoryID
        save()
    }

    public func setDueDate(_ due: Date?, forTaskWith id: UUID) {
        guard let task = task(id: id) else { return }
        task.dueDate = due
        save()
    }

    private func reloadCategories() {
        let descriptor = FetchDescriptor<TaskCategory>(sortBy: [SortDescriptor(\.order)])
        categories = (try? context.fetch(descriptor)) ?? []
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
        allTasks.filter { task in
            guard let done = task.completedAt else { return false }
            return calendar.isDate(done, inSameDayAs: day)
        }
    }

    public func task(id: UUID) -> TaskItem? { allTasks.first { $0.id == id } }

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

    /// Hides finished tasks from the list without deleting them. Deleting them
    /// used to take their XP, streak and badges with them, because every
    /// statistic is derived from the tasks themselves.
    public func clearCompleted(at date: Date = Date()) {
        for task in tasks where task.isDone {
            task.archivedAt = date
        }
        save()
    }

    /// Recreates a finished task that is known only from its focus history —
    /// used to repair work deleted before clearing meant hiding. Archived, so
    /// it counts toward the figures without reappearing in the list.
    @discardableResult
    public func restoreCompletion(
        id: UUID, title: String, completedAt: Date, secondsSpent: Double, archivedAt: Date
    ) -> TaskItem? {
        guard task(id: id) == nil else { return nil }
        let task = TaskItem(id: id, title: title, createdAt: completedAt,
                            completedAt: completedAt, secondsSpent: max(0, secondsSpent),
                            order: 0, status: .done)
        task.archivedAt = archivedAt
        context.insert(task)
        save()
        return task
    }

    public func completedSessions() -> [FocusSessionRecord] {
        ((try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? [])
            .filter(\.completedTask)
    }

    /// Brings hidden tasks back into the list.
    public func unarchiveAll() {
        for task in allTasks where task.isArchived {
            task.archivedAt = nil
        }
        save()
    }

    public var archivedCount: Int { allTasks.filter(\.isArchived).count }

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
