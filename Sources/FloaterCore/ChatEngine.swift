import Foundation

/// A task the chat wants to act on: either one that already exists, or one it
/// proposed creating earlier in the same turn.
public enum TaskRef: Equatable, Sendable {
    case existing(UUID)
    case pending(String)
}

public enum ChatAction: Equatable, Sendable {
    case createTask(ref: String, title: String, note: String, status: TaskStatus,
                    categoryID: UUID?, due: Date?)
    case setCategory(TaskRef, categoryID: UUID?, categoryName: String)
    case setDueDate(TaskRef, date: Date?)
    case setStatus(TaskRef, TaskStatus)
    case startTimer(TaskRef, minutes: Int)
    case addNote(TaskRef, note: String)
    case deleteTask(TaskRef)
    case scheduleFollowUp(TaskRef, date: Date, destination: FollowUpDestination)
}

public struct ProposedAction: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let action: ChatAction
    public let summary: String
    public let symbol: String
    public let isDestructive: Bool

    public init(id: UUID = UUID(), action: ChatAction, summary: String, symbol: String, isDestructive: Bool) {
        self.id = id
        self.action = action
        self.summary = summary
        self.symbol = symbol
        self.isDestructive = isDestructive
    }
}

public struct ChatTurn: Equatable, Sendable {
    public let reply: String
    public let actions: [ProposedAction]
}

/// Turns a plain-language message into a set of proposed changes.
///
/// Every tool the model can call is a *proposal* — nothing is applied until the
/// user confirms. That means one API call per turn: the response's tool calls
/// become the change set, and the conversation history is kept as plain text so
/// the next request never carries a dangling `tool_use` without its result.
@MainActor
public final class ChatEngine {
    public static let maxHistoryTurns = 20

    private let client: ClaudeClient
    private let model: String
    private let clock: Clock
    private let calendar: Calendar
    private var history: [APIMessage] = []
    /// Short handles ("t1") the model uses instead of raw UUIDs.
    private var handles: [String: UUID] = [:]
    /// Category names the model may use, matched case-insensitively.
    private var categoryIDs: [String: UUID] = [:]

    public init(
        client: ClaudeClient,
        model: String = AnthropicClient.defaultModel,
        clock: Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.client = client
        self.model = model
        self.clock = clock
        self.calendar = calendar
    }

    public func reset() {
        history = []
        handles = [:]
    }

    /// Seeds the conversation from a restored transcript.
    public func restore(transcript: [(role: String, text: String)]) {
        history = transcript.suffix(Self.maxHistoryTurns).map {
            APIMessage(role: $0.role, content: [.text($0.text)])
        }
    }

    public func send(_ text: String, tasks: [TaskItem], categories: [TaskCategory] = []) async throws -> ChatTurn {
        buildHandles(for: tasks)
        categoryIDs = Dictionary(
            categories.map { ($0.name.lowercased(), $0.id) }, uniquingKeysWith: { first, _ in first }
        )
        self.categories = categories
        history.append(.user(text))
        if history.count > Self.maxHistoryTurns {
            history.removeFirst(history.count - Self.maxHistoryTurns)
        }

        let response = try await client.send(
            MessagesRequest(
                model: model,
                maxTokens: 4096,
                system: systemPrompt(tasks: tasks, categories: categories),
                messages: history,
                tools: Self.tools
            )
        )

        if response.stop_reason == "refusal" { throw ClaudeError.refused }

        let actions = proposals(from: response, tasks: tasks)
        let reply = response.text.isEmpty ? Self.fallbackReply(for: actions) : response.text
        history.append(.assistant(reply))
        return ChatTurn(reply: reply, actions: actions)
    }

    /// A single question that never touches the conversation — used by the
    /// digest and the prompt generator, which should not pollute the chat's
    /// history or be affected by it.
    public func oneOff(system: String, user: String, maxTokens: Int = 4096) async throws -> String {
        let response = try await client.send(
            MessagesRequest(model: model, maxTokens: maxTokens, system: system,
                            messages: [.user(user)], tools: nil)
        )
        if response.stop_reason == "refusal" { throw ClaudeError.refused }
        return response.text
    }

    /// Records a rejected change set so the model does not keep re-proposing it.
    public func noteDiscarded() {
        history.append(.user("(I discarded those proposed changes.)"))
    }

    public func noteApplied(_ count: Int) {
        history.append(.user("(I applied those \(count) change\(count == 1 ? "" : "s").)"))
    }

    // MARK: - Prompt

    private func buildHandles(for tasks: [TaskItem]) {
        handles = [:]
        for (index, task) in tasks.enumerated() {
            handles["t\(index + 1)"] = task.id
        }
    }

    private var categories: [TaskCategory] = []

    private func systemPrompt(tasks: [TaskItem], categories: [TaskCategory]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.formatOptions = [.withInternetDateTime]

        var lines = [
            "You are the assistant inside Floater, a floating macOS task tracker.",
            "The user talks to you in plain language, in English or Arabic, to manage their task list.",
            "",
            "Every tool you call is a PROPOSAL. Nothing happens until the user presses Apply.",
            "So never say a change is done — say what you are proposing.",
            "Be brief: one or two sentences. The proposed changes are shown to the user separately,",
            "so do not list them again in your reply.",
            "If the user is only asking a question, answer it and call no tools.",
            "",
            "Refer to existing tasks by their handle (t1, t2, ...).",
            "To act on a task you are creating in this same turn, use the ref you gave it (new-1, new-2, ...).",
            "",
            "The current local time is \(formatter.string(from: clock.now)).",
            "",
        ]

        if !categories.isEmpty {
            lines.append("Categories (a task belongs to at most one): "
                         + categories.map(\.name).joined(separator: ", "))
            lines.append("")
        }
        if tasks.isEmpty {
            lines.append("The task list is empty.")
        } else {
            lines.append("Current tasks:")
            for (index, task) in tasks.enumerated() {
                var line = "t\(index + 1) [\(task.status.rawValue)] \(task.title)"
                if task.secondsSpent > 0 { line += " (\(task.secondsSpent.compactDuration) focused)" }
                if let due = task.dueDate {
                    let formatter = ISO8601DateFormatter()
                    formatter.timeZone = calendar.timeZone
                    formatter.formatOptions = [.withFullDate]
                    line += " due:\(formatter.string(from: due))"
                }
                if let category = categories.first(where: { $0.id == task.categoryID }) {
                    line += " [\(category.name)]"
                }
                if !task.note.isEmpty { line += " — note: \(task.note.prefix(160))" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    nonisolated private static func fallbackReply(for actions: [ProposedAction]) -> String {
        actions.isEmpty
            ? "I did not find anything to change."
            : "Proposed \(actions.count) change\(actions.count == 1 ? "" : "s")."
    }

    // MARK: - Tool definitions

    nonisolated private static func schema(_ properties: [String: JSONValue]) -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            // Strict tool use requires every property to be listed as required.
            "required": .array(properties.keys.sorted().map { .string($0) }),
            "properties": .object(properties),
        ])
    }

    nonisolated private static func string(_ description: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(description)])
    }

    nonisolated private static let statusProperty = JSONValue.object([
        "type": .string("string"),
        "enum": .array(TaskStatus.allCases.map { .string($0.rawValue) }),
        "description": .string("Task status."),
    ])

    nonisolated private static let taskIDProperty = JSONValue.object([
        "type": .string("string"),
        "description": .string("Handle of an existing task (t1, t2, ...) or a ref from create_task in this turn (new-1, ...)."),
    ])

    nonisolated public static let tools: [ToolDefinition] = [
        ToolDefinition(
            name: "create_task",
            description: "Propose creating a new task.",
            inputSchema: schema([
                "ref": string("A temporary id for this new task so other calls can refer to it: new-1, new-2, ..."),
                "title": string("Short imperative title."),
                "note": string("Extra detail worth keeping. Empty string if there is none."),
                "status": statusProperty,
                "category": string("Category name exactly as listed, or empty string for none."),
                "due": string("Due date, ISO 8601, or empty string for none."),
            ])
        ),
        ToolDefinition(
            name: "set_task_status",
            description: "Propose changing a task's status. Use status 'done' to finish a task.",
            inputSchema: schema(["task_id": taskIDProperty, "status": statusProperty])
        ),
        ToolDefinition(
            name: "start_timer",
            description: "Propose starting a focus timer on a task. Prefer 15, 30 or 45 minutes.",
            inputSchema: schema([
                "task_id": taskIDProperty,
                "minutes": .object([
                    "type": .string("integer"),
                    "description": .string("Length in minutes, 1 to 240."),
                ]),
            ])
        ),
        ToolDefinition(
            name: "add_note",
            description: "Propose replacing a task's note.",
            inputSchema: schema(["task_id": taskIDProperty, "note": string("The full new note text.")])
        ),
        ToolDefinition(
            name: "delete_task",
            description: "Propose deleting a task. Only when the user clearly wants it gone.",
            inputSchema: schema(["task_id": taskIDProperty])
        ),
        ToolDefinition(
            name: "set_category",
            description: "Propose putting a task in a category. Pass an empty name to clear it.",
            inputSchema: schema([
                "task_id": taskIDProperty,
                "category": string("Category name exactly as listed, or empty string to clear."),
            ])
        ),
        ToolDefinition(
            name: "set_due_date",
            description: "Propose a task's due date. Pass an empty string to clear it.",
            inputSchema: schema([
                "task_id": taskIDProperty,
                "due": string("Local date, or date and time, ISO 8601 (2026-10-09 or 2026-10-09T17:00). Empty to clear."),
            ])
        ),
        ToolDefinition(
            name: "schedule_follow_up",
            description: "Propose a follow-up reminder in the user's Calendar or Reminders app.",
            inputSchema: schema([
                "task_id": taskIDProperty,
                "when": string("Local date and time, ISO 8601, e.g. 2026-09-01T09:00:00."),
                "destination": .object([
                    "type": .string("string"),
                    "enum": .array(FollowUpDestination.allCases.map { .string($0.rawValue) }),
                    "description": .string("Where the follow-up goes."),
                ]),
            ])
        ),
    ]

    // MARK: - Mapping tool calls onto proposals

    private func proposals(from response: MessagesResponse, tasks: [TaskItem]) -> [ProposedAction] {
        var pendingTitles: [String: String] = [:]
        var result: [ProposedAction] = []

        for use in response.toolUses {
            guard let proposal = proposal(
                name: use.name, input: use.input, tasks: tasks, pendingTitles: &pendingTitles
            ) else { continue }
            result.append(proposal)
        }
        return result
    }

    private func proposal(
        name: String,
        input: JSONValue,
        tasks: [TaskItem],
        pendingTitles: inout [String: String]
    ) -> ProposedAction? {
        func ref(_ key: String = "task_id") -> TaskRef? {
            guard let raw = input[key]?.stringValue else { return nil }
            if let id = handles[raw] { return .existing(id) }
            if pendingTitles[raw] != nil { return .pending(raw) }
            return nil
        }
        func label(_ target: TaskRef) -> String {
            switch target {
            case .existing(let id): return tasks.first { $0.id == id }?.title ?? "task"
            case .pending(let ref): return pendingTitles[ref] ?? "new task"
            }
        }

        switch name {
        case "create_task":
            guard let title = input["title"]?.stringValue, !title.isEmpty else { return nil }
            let reference = input["ref"]?.stringValue ?? "new-\(pendingTitles.count + 1)"
            let note = input["note"]?.stringValue ?? ""
            let status = TaskStatus(rawValue: input["status"]?.stringValue ?? "") ?? .notStarted
            let categoryName = input["category"]?.stringValue ?? ""
            let categoryID = categoryIDs[categoryName.lowercased()]
            let due = (input["due"]?.stringValue).flatMap { $0.isEmpty ? nil : Self.parseDate($0, calendar: calendar) }
            pendingTitles[reference] = title
            var summary = "Add \u{201C}\(title)\u{201D}"
            if status != .notStarted { summary += " as \(status.title)" }
            if categoryID != nil { summary += " in \(categoryName)" }
            if due != nil {
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "EEE d MMM"
                summary += ", due \(formatter.string(from: due!))"
            }
            return ProposedAction(
                action: .createTask(ref: reference, title: title, note: note, status: status,
                                    categoryID: categoryID, due: due),
                summary: summary, symbol: "plus.circle", isDestructive: false
            )

        case "set_category":
            guard let target = ref() else { return nil }
            let name = input["category"]?.stringValue ?? ""
            let id = categoryIDs[name.lowercased()]
            guard name.isEmpty || id != nil else { return nil }
            return ProposedAction(
                action: .setCategory(target, categoryID: id, categoryName: name),
                summary: name.isEmpty
                    ? "Remove \u{201C}\(label(target))\u{201D} from its category"
                    : "Put \u{201C}\(label(target))\u{201D} in \(name)",
                symbol: "folder", isDestructive: false
            )

        case "set_due_date":
            guard let target = ref() else { return nil }
            let raw = input["due"]?.stringValue ?? ""
            if raw.isEmpty {
                return ProposedAction(
                    action: .setDueDate(target, date: nil),
                    summary: "Clear the due date on \u{201C}\(label(target))\u{201D}",
                    symbol: "calendar.badge.minus", isDestructive: false
                )
            }
            guard let date = Self.parseDate(raw, calendar: calendar) else { return nil }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEE d MMM"
            return ProposedAction(
                action: .setDueDate(target, date: date),
                summary: "Due \(formatter.string(from: date)) — \u{201C}\(label(target))\u{201D}",
                symbol: "calendar", isDestructive: false
            )

        case "set_task_status":
            guard let target = ref(),
                  let status = TaskStatus(rawValue: input["status"]?.stringValue ?? "") else { return nil }
            return ProposedAction(
                action: .setStatus(target, status),
                summary: "Set \u{201C}\(label(target))\u{201D} to \(status.title)",
                symbol: status.symbol, isDestructive: false
            )

        case "start_timer":
            guard let target = ref(), let minutes = input["minutes"]?.intValue,
                  (1...240).contains(minutes) else { return nil }
            return ProposedAction(
                action: .startTimer(target, minutes: minutes),
                summary: "Start a \(minutes) min timer on \u{201C}\(label(target))\u{201D}",
                symbol: "timer", isDestructive: false
            )

        case "add_note":
            guard let target = ref(), let note = input["note"]?.stringValue else { return nil }
            return ProposedAction(
                action: .addNote(target, note: note),
                summary: "Note on \u{201C}\(label(target))\u{201D}: \(note.prefix(60))",
                symbol: "note.text", isDestructive: false
            )

        case "delete_task":
            guard let target = ref() else { return nil }
            return ProposedAction(
                action: .deleteTask(target),
                summary: "Delete \u{201C}\(label(target))\u{201D}",
                symbol: "trash", isDestructive: true
            )

        case "schedule_follow_up":
            guard let target = ref(),
                  let raw = input["when"]?.stringValue,
                  let date = Self.parseDate(raw, calendar: calendar),
                  let destination = FollowUpDestination(rawValue: input["destination"]?.stringValue ?? "")
            else { return nil }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEE d MMM, HH:mm"
            return ProposedAction(
                action: .scheduleFollowUp(target, date: date, destination: destination),
                summary: "\(destination.title) follow-up on \u{201C}\(label(target))\u{201D} — \(formatter.string(from: date))",
                symbol: destination.symbol, isDestructive: false
            )

        default:
            return nil
        }
    }

    /// Accepts both a zoned ISO timestamp and the bare local form the model
    /// usually produces.
    nonisolated static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        let zoned = ISO8601DateFormatter()
        zoned.formatOptions = [.withInternetDateTime]
        if let date = zoned.date(from: raw) { return date }

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
