import Foundation
import SwiftData

/// Owns the SwiftData stack and exposes the task list as a plain array so the
/// AppKit layer can read it without going through `@Query`.
@MainActor
public final class Store {
    public let container: ModelContainer
    public private(set) var tasks: [TaskItem] = []

    public var context: ModelContext { container.mainContext }

    public init(inMemory: Bool = false) throws {
        let schema = Schema([TaskItem.self, FocusSessionRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [config])
        reload()
    }

    public func reload() {
        let descriptor = FetchDescriptor<TaskItem>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        tasks = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Queries

    public var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

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
        task.completedAt = date
        task.secondsSpent += max(0, seconds)
        save()
    }

    public func reopen(_ task: TaskItem) {
        task.completedAt = nil
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

    private func save() {
        try? context.save()
        reload()
    }
}
