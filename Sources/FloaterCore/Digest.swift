import Foundation
import SwiftData

/// What actually happened over a stretch of days. Assembled from the store, not
/// from the model — Claude is asked to write it up, never to recall it, so the
/// numbers in a digest are always real.
public struct Digest: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let title: String
        public let category: String
        public let note: String
        public let completedAt: Date
        public let secondsFocused: Double
    }

    public struct CategoryTotal: Equatable, Sendable {
        public let name: String
        public let completed: Int
        public let secondsFocused: Double
    }

    public let days: Int
    public let from: Date
    public let to: Date
    public let completed: [Entry]
    public let byCategory: [CategoryTotal]
    public let totalFocused: Double
    public let sessions: Int
    /// Still open at the end of the window, so a digest can say what is left.
    public let stillOpen: [String]
    public let blocked: [String]
    public let overdue: [String]

    public var isEmpty: Bool { completed.isEmpty && totalFocused == 0 }

    /// The fact sheet handed to the model. Deliberately plain and complete:
    /// everything it is allowed to say is in here.
    public func factSheet(calendar: Calendar = .current) -> String {
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateFormat = "EEE d MMM"

        var lines: [String] = []
        lines.append("Window: last \(days) day\(days == 1 ? "" : "s") "
                     + "(\(day.string(from: from)) to \(day.string(from: to)))")
        lines.append("Tasks finished: \(completed.count)")
        lines.append("Time focused: \(totalFocused.compactDuration)")
        lines.append("Focus sessions: \(sessions)")
        lines.append("")

        if byCategory.isEmpty {
            lines.append("No finished work in this window.")
        } else {
            lines.append("By project:")
            for total in byCategory {
                lines.append("- \(total.name): \(total.completed) finished, "
                             + "\(total.secondsFocused.compactDuration) focused")
            }
            lines.append("")
            lines.append("Finished:")
            for entry in completed {
                var line = "- \(entry.title)"
                if entry.category != Digest.uncategorised { line += " [\(entry.category)]" }
                lines.append(line)
                // The note usually says what actually changed, which is what a
                // reader needs and the title rarely gives.
                if !entry.note.isEmpty {
                    lines.append("  note: \(entry.note.prefix(240))")
                }
            }
        }

        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("")
            lines.append("\(title):")
            for item in items { lines.append("- \(item)") }
        }
        section("Still open", stillOpen)
        section("Blocked", blocked)
        section("Overdue", overdue)

        return lines.joined(separator: "\n")
    }

    public static let uncategorised = "Uncategorised"
}

public extension Store {
    /// Builds the digest for the N days ending now.
    @MainActor
    func digest(days: Int, now: Date, calendar: Calendar = .current) -> Digest {
        let clampedDays = max(1, days)
        let from = calendar.date(byAdding: .day, value: -(clampedDays - 1),
                                 to: calendar.startOfDay(for: now)) ?? now
        func name(for task: TaskItem) -> String {
            category(id: task.categoryID)?.name ?? Digest.uncategorised
        }

        let finished = allTasks
            .filter { task in
                guard let done = task.completedAt else { return false }
                return done >= from && done <= now
            }
            .sorted { ($0.completedAt ?? from) < ($1.completedAt ?? from) }
            .map {
                Digest.Entry(title: $0.title, category: name(for: $0),
                             note: $0.note.trimmingCharacters(in: .whitespacesAndNewlines),
                             completedAt: $0.completedAt ?? from, secondsFocused: $0.secondsSpent)
            }

        var totals: [String: (count: Int, seconds: Double)] = [:]
        for entry in finished {
            var current = totals[entry.category] ?? (0, 0)
            current.count += 1
            current.seconds += entry.secondsFocused
            totals[entry.category] = current
        }
        let byCategory = totals
            .map { Digest.CategoryTotal(name: $0.key, completed: $0.value.count,
                                        secondsFocused: $0.value.seconds) }
            .sorted { ($0.secondsFocused, $0.completed) > ($1.secondsFocused, $1.completed) }

        let sessions = ((try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? [])
            .filter { $0.startedAt >= from && $0.startedAt <= now }

        let open = tasks.filter { !$0.isDone }
        return Digest(
            days: clampedDays,
            from: from,
            to: now,
            completed: finished,
            byCategory: byCategory,
            totalFocused: finished.reduce(0) { $0 + $1.secondsFocused },
            sessions: sessions.count,
            stillOpen: open.filter { $0.status != .blocked }.map(\.title),
            blocked: open.filter { $0.status == .blocked }.map(\.title),
            overdue: open.filter { $0.dueState(now: now, calendar: calendar) == .overdue }.map(\.title)
        )
    }
}

