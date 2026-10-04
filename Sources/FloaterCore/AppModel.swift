import Foundation
import Combine

/// Single source of truth for the UI. Owns the store and the timer engine and
/// republishes their state so SwiftUI can render it.
@MainActor
public final class AppModel: ObservableObject {
    public enum Mode { case collapsed, expanded }
    /// A finished task that has not been answered about yet.
    public struct PendingFollowUp: Identifiable, Equatable {
        public let id = UUID()
        public let taskID: UUID
        public let taskTitle: String
        public let note: String
        public let secondsFocused: Double
        public let completedAt: Date
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case tasks, pipeline, notes, chat
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .tasks: return "Tasks"
            case .pipeline: return "Board"
            case .notes: return "Notes"
            case .chat: return "Chat"
            }
        }
    }

    // Published state
    @Published public private(set) var tasks: [TaskItem] = []
    @Published public private(set) var phase: TimerPhase = .idle
    @Published public private(set) var remaining: TimeInterval = 0
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var activeTaskID: UUID?
    @Published public private(set) var activeTitle: String = ""
    @Published public private(set) var activePlannedMinutes: Int = 0
    @Published public private(set) var completedToday: Int = 0
    /// Bumped whenever the pill should visibly demand attention.
    @Published public private(set) var attentionPulse: Int = 0
    @Published public private(set) var pendingFollowUp: PendingFollowUp?
    @Published public private(set) var followUpError: FollowUpError?
    @Published public private(set) var isSchedulingFollowUp = false
    /// Set once the prompt must stay put — a picker is open or an error is showing.
    @Published public private(set) var followUpPromptPinned = false
    @Published public var followUpDestination: FollowUpDestination {
        didSet { prefs.followUpDestination = followUpDestination }
    }
    /// Writes a calendar event for each finished task, at the time it was done.
    @Published public var logCompletions: Bool {
        didSet { prefs.logCompletions = logCompletions }
    }
    @Published public private(set) var completionLogError: String?

    // Chat
    @Published public private(set) var chatMessages: [ChatMessageRecord] = []
    @Published public private(set) var pendingActions: [ProposedAction] = []
    @Published public private(set) var chatError: String?
    @Published public private(set) var isSendingChat = false
    @Published public private(set) var hasAPIKey = false
    @Published public private(set) var stats: GameStats?
    /// Bumped when a level is gained, so the app can celebrate it.
    @Published public private(set) var levelUps: Int = 0
    @Published public private(set) var slackError: String?
    @Published public var slackStatusEnabled: Bool {
        didSet {
            prefs.slackStatusEnabled = slackStatusEnabled
            Task { await syncSlackStatus(force: true) }
        }
    }
    @Published public var goalKind: DailyGoalKind {
        didSet { prefs.goalKind = goalKind; refresh() }
    }
    @Published public var goalTarget: Int {
        didSet { prefs.goalTarget = goalTarget; refresh() }
    }
    @Published public var chatDraft: String = ""
    @Published public private(set) var isGenerating = false
    /// Last generated digest or prompt, also placed on the clipboard by the app.
    @Published public private(set) var lastGenerated: String?
    public var digestDays: Int = 7
    @Published public var mode: Mode = .collapsed
    @Published public var tab: Tab = .tasks
    /// The task whose note is open inline, if any.
    @Published public var expandedTaskID: UUID?
    /// The task Cmd-C acts on when no text field has focus.
    @Published public private(set) var selectedTaskID: UUID?
    @Published public private(set) var categories: [TaskCategory] = []
    @Published public var sort: TaskSort {
        didSet { prefs.taskSort = sort }
    }
    /// Board columns: categories when true, statuses when false.
    @Published public var pipelineByCategory: Bool {
        didSet { prefs.pipelineByCategory = pipelineByCategory }
    }
    @Published public var draft: String = ""
    /// Global notes pane. Written through to the store on a short debounce so
    /// typing does not hit SwiftData on every keystroke.
    @Published public var scratchpad: String = ""
    @Published public var soundEnabled: Bool {
        didSet { prefs.soundEnabled = soundEnabled }
    }
    @Published public var takeoverEnabled: Bool {
        didSet { prefs.takeoverEnabled = takeoverEnabled }
    }

    // Hooks the AppKit layer wires up
    public var onCelebrate: ((String) -> Void)?
    public var onTimeUp: ((FocusRun) -> Void)?
    public var onDismissTimeUp: (() -> Void)?
    /// Fired when the user buys themselves more time on a task.
    public var onExtend: ((Int) -> Void)?
    /// Writes to Calendar / Reminders. Injected by the app layer; nil in tests
    /// that do not exercise follow-ups.
    public var scheduler: FollowUpScheduling?
    /// Reads a project's conventions and history off disk for the prompt generator.
    public var projectContext: ProjectContextReading?
    public var slack: SlackPosting?

    public let timerLengths = [15, 30, 45]

    private let store: Store
    private let engine: TimerEngine
    private let secrets: SecretStore
    private var chat: ChatEngine?
    private let prefs: Preferences
    private let clock: Clock
    private let calendar: Calendar
    private var ticker: Timer?
    private var runStartedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private let noteEdits = PassthroughSubject<(id: UUID, text: String), Never>()

    public init(
        store: Store,
        prefs: Preferences = Preferences(),
        clock: Clock = SystemClock(),
        calendar: Calendar = .current,
        scheduler: FollowUpScheduling? = nil,
        secrets: SecretStore = InMemorySecretStore(),
        makeChatEngine: ((@escaping @Sendable () -> String?) -> ChatEngine)? = nil,
        autoTick: Bool = true
    ) {
        self.store = store
        self.prefs = prefs
        self.clock = clock
        self.calendar = calendar
        self.scheduler = scheduler
        self.secrets = secrets
        self.followUpDestination = prefs.followUpDestination
        self.logCompletions = prefs.logCompletions
        self.sort = prefs.taskSort
        self.pipelineByCategory = prefs.pipelineByCategory
        self.slackStatusEnabled = prefs.slackStatusEnabled
        self.goalKind = prefs.goalKind
        self.goalTarget = prefs.goalTarget
        self.makeChatEngine = makeChatEngine
        self.engine = TimerEngine(clock: clock)
        self.soundEnabled = prefs.soundEnabled
        self.takeoverEnabled = prefs.takeoverEnabled
        engine.onElapsed = { [weak self] run in
            self?.handleElapsed(run)
        }
        store.seedCategoriesIfEmpty(home: NSHomeDirectory())
        self.scratchpad = store.scratchpadText

        restoreActiveRun()
        refresh()
        startDebouncedWrites()
        if autoTick {
            startTicking()
            // Without this the status only ever changed when a task was finished,
            // so a day that started with the app already running showed nothing.
            Task { await syncSlackStatus(force: true) }
        }
    }

    deinit { ticker?.invalidate() }

    public var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }

    /// The list in the order the user asked for. Ties fall back to manual order
    /// so the result is stable rather than shuffling between refreshes.
    public var sortedTasks: [TaskItem] {
        switch sort {
        case .manual:
            return tasks
        case .status:
            return tasks.sorted { a, b in
                if a.status.sortRank != b.status.sortRank { return a.status.sortRank < b.status.sortRank }
                if a.dueDate != b.dueDate { return Self.dueBefore(a.dueDate, b.dueDate) }
                return a.order < b.order
            }
        case .dueDate:
            return tasks.sorted { a, b in
                if a.dueDate != b.dueDate { return Self.dueBefore(a.dueDate, b.dueDate) }
                if a.status.sortRank != b.status.sortRank { return a.status.sortRank < b.status.sortRank }
                return a.order < b.order
            }
        }
    }

    /// A task with no due date sorts after every task that has one.
    static func dueBefore(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (let left?, let right?): return left < right
        }
    }

    public func tasks(in category: TaskCategory?) -> [TaskItem] {
        sortedTasks.filter { $0.categoryID == category?.id }
    }

    public func tasks(with status: TaskStatus) -> [TaskItem] {
        sortedTasks.filter { $0.status == status }
    }

    public var overdueCount: Int {
        tasks.filter { $0.dueState(now: clock.now, calendar: calendar) == .overdue }.count
    }

    public func dueState(of task: TaskItem) -> DueState {
        task.dueState(now: clock.now, calendar: calendar)
    }

    public func category(of task: TaskItem) -> TaskCategory? {
        store.category(id: task.categoryID)
    }
    public var doneCount: Int { tasks.count - openTasks.count }
    public var isRunning: Bool { phase == .running }
    public var isActive: Bool { phase != .idle }
    public var activeTask: TaskItem? { activeTaskID.flatMap { id in tasks.first { $0.id == id } } }
    public var selectedTask: TaskItem? { selectedTaskID.flatMap { id in tasks.first { $0.id == id } } }

    public var remainingText: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Task actions

    /// One task per non-blank line, so pasting a list in and pressing Return
    /// creates the whole list rather than one task with newlines in its title.
    public func addDraftTask() {
        let lines = draft
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }
        for line in lines { store.add(title: line) }
        draft = ""
        refresh()
    }

    public func select(_ task: TaskItem?) {
        selectedTaskID = task?.id
    }

    /// Plain text form of a task for the clipboard: the title, and the note
    /// below it when there is one. No status or dates — this is text meant to be
    /// pasted somewhere else, not a report.
    public func clipboardText(for task: TaskItem) -> String {
        let note = task.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? task.title : task.title + "\n\n" + note
    }

    /// What Cmd-C should put on the clipboard, or nil when nothing is selected.
    public func clipboardTextForSelection() -> String? {
        selectedTask.map { clipboardText(for: $0) }
    }

    public func complete(_ task: TaskItem) {
        let banked = task.id == activeTaskID ? finishActiveRun(completedTask: true) : 0
        let spent = task.secondsSpent + banked
        store.complete(task, at: clock.now, addingSeconds: banked)
        let title = task.title
        pendingFollowUp = PendingFollowUp(
            taskID: task.id,
            taskTitle: title,
            note: task.note,
            secondsFocused: spent,
            completedAt: clock.now
        )
        followUpError = nil
        followUpPromptPinned = false
        completionLogError = nil
        refresh()
        onCelebrate?(title)
        logCompletion(taskID: task.id, title: title, focusedSeconds: spent, finishedAt: clock.now)
        Task { await syncSlackStatus() }
    }

    public func reopen(_ task: TaskItem) {
        unlogCompletion(task)
        store.reopen(task)
        refresh()
    }

    public func delete(_ task: TaskItem) {
        if task.id == activeTaskID { _ = finishActiveRun(completedTask: false) }
        if task.id == selectedTaskID { selectedTaskID = nil }
        if task.id == expandedTaskID { expandedTaskID = nil }
        unlogCompletion(task)
        store.delete(task)
        refresh()
    }

    public func clearCompleted() {
        store.clearCompleted(at: clock.now)
        refresh()
    }

    public func showHiddenAgain() {
        store.unarchiveAll()
        refresh()
    }

    public var hiddenCount: Int { store.archivedCount }

    /// Rebuilds finished tasks that were deleted back when clearing meant
    /// deleting. Their focus history survived, so the work can be counted again.
    @discardableResult
    public func restoreLostCompletions() -> Int {
        var byTask: [UUID: (title: String, at: Date, seconds: Double)] = [:]
        for session in store.completedSessions() {
            guard store.task(id: session.taskID) == nil else { continue }
            let at = session.endedAt ?? session.startedAt
            if var existing = byTask[session.taskID] {
                existing.seconds += session.secondsFocused
                existing.at = max(existing.at, at)
                byTask[session.taskID] = existing
            } else {
                byTask[session.taskID] = (session.taskTitle, at, session.secondsFocused)
            }
        }
        var restored = 0
        for (id, entry) in byTask {
            let title = entry.title.isEmpty ? "Finished task" : entry.title
            if store.restoreCompletion(id: id, title: title, completedAt: entry.at,
                                       secondsSpent: entry.seconds, archivedAt: clock.now) != nil {
                restored += 1
            }
        }
        refresh()
        return restored
    }

    /// Setting a task to Done runs the full completion path (time banked,
    /// confetti). Moving the *running* task to anything else stops its timer,
    /// because you are no longer working on it.
    public func setStatus(_ status: TaskStatus, for task: TaskItem) {
        guard task.status != status else { return }
        if status == .done {
            complete(task)
            return
        }
        if task.id == activeTaskID {
            _ = finishActiveRun(completedTask: false)
        }
        // Leaving Done makes any logged completion a lie; take it back.
        if task.isDone { unlogCompletion(task) }
        store.setStatus(status, for: task, at: clock.now)
        refresh()
    }

    /// Click-through order on the status dot. Deliberately skips Done so you
    /// cannot set off the confetti just by cycling; Done has its own button.
    public func advanceStatus(_ task: TaskItem) {
        if task.isDone {
            setStatus(.notStarted, for: task)
            return
        }
        let cycle: [TaskStatus] = [.notStarted, .inProgress, .blocked]
        let next = cycle[((cycle.firstIndex(of: task.status) ?? 0) + 1) % cycle.count]
        setStatus(next, for: task)
    }

    /// The one-click path on the status dot.
    public func toggleDone(_ task: TaskItem) {
        if task.isDone {
            store.reopen(task)
            refresh()
        } else {
            complete(task)
        }
    }

    /// Opening a task's note also selects it, so Cmd-C has an obvious target.
    public func setCategory(_ category: TaskCategory?, for task: TaskItem) {
        store.setCategory(category?.id, forTaskWith: task.id)
        refresh()
    }

    public func setDueDate(_ due: Date?, for task: TaskItem) {
        store.setDueDate(due, forTaskWith: task.id)
        refresh()
    }

    @discardableResult
    public func addCategory(name: String, emoji: String = "", colorHex: String = "8E8E93",
                            repoPath: String = "") -> TaskCategory? {
        let created = store.addCategory(name: name, emoji: emoji, colorHex: colorHex, repoPath: repoPath)
        refresh()
        return created
    }

    public func deleteCategory(_ category: TaskCategory) {
        store.deleteCategory(category)
        refresh()
    }

    public func toggleNote(for task: TaskItem) {
        expandedTaskID = expandedTaskID == task.id ? nil : task.id
        selectedTaskID = task.id
    }

    public func noteChanged(_ text: String, for task: TaskItem) {
        noteEdits.send((id: task.id, text: text))
    }

    // MARK: - Chat

    private var makeChatEngine: ((@escaping @Sendable () -> String?) -> ChatEngine)?
    private var hasPreparedChat = false

    /// The Keychain is not touched until the user actually opens Chat. Reading
    /// it can block on a system access prompt, which at launch would hang the
    /// app before a window ever appears.
    public func prepareChat() {
        guard !hasPreparedChat else { return }
        hasPreparedChat = true
        hasAPIKey = secrets.has(.anthropic)
        rebuildChatEngine()
    }

    private func rebuildChatEngine() {
        guard hasAPIKey, let makeChatEngine else { chat = nil; return }
        let secrets = self.secrets
        let engine = makeChatEngine({ secrets.secret(.anthropic) })
        engine.restore(transcript: store.chatMessages.map { ($0.roleRaw, $0.text) })
        chat = engine
    }

    public func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, secrets.setSecret(trimmed, for: .anthropic) else { return }
        hasPreparedChat = true
        hasAPIKey = true
        chatError = nil
        rebuildChatEngine()
    }

    public func clearAPIKey() {
        secrets.setSecret(nil, for: .anthropic)
        hasAPIKey = false
        chat = nil
    }

    public func clearChat() {
        store.clearChat()
        pendingActions = []
        chatError = nil
        chat?.reset()
        refresh()
    }

    public func sendChat() async {
        let text = chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingChat else { return }
        prepareChat()
        guard let chat else {
            chatError = ClaudeError.missingAPIKey.message
            return
        }
        chatDraft = ""
        chatError = nil
        pendingActions = []
        store.appendChat(role: "user", text: text, at: clock.now)
        refresh()

        isSendingChat = true
        defer { isSendingChat = false }
        do {
            let turn = try await chat.send(text, tasks: tasks, categories: categories)
            store.appendChat(role: "assistant", text: turn.reply, at: clock.now)
            pendingActions = turn.actions
            refresh()
        } catch let error as ClaudeError {
            chatError = error.message
        } catch {
            chatError = error.localizedDescription
        }
    }

    public func discardProposals() {
        guard !pendingActions.isEmpty else { return }
        pendingActions = []
        chat?.noteDiscarded()
    }

    /// Runs the proposed changes in order. Tasks created earlier in the set are
    /// resolvable by the later actions that referred to them.
    public func applyProposals() async {
        guard !pendingActions.isEmpty else { return }
        let actions = pendingActions
        pendingActions = []
        var created: [String: UUID] = [:]

        func resolve(_ ref: TaskRef) -> TaskItem? {
            switch ref {
            case .existing(let id): return store.task(id: id)
            case .pending(let key): return created[key].flatMap { store.task(id: $0) }
            }
        }

        for proposal in actions {
            switch proposal.action {
            case .createTask(let ref, let title, let note, let status, let categoryID, let due):
                guard let task = store.add(title: title) else { continue }
                created[ref] = task.id
                if !note.isEmpty { store.updateNote(note, forTaskWith: task.id) }
                if let categoryID { store.setCategory(categoryID, forTaskWith: task.id) }
                if let due { store.setDueDate(due, forTaskWith: task.id) }
                if status != .notStarted { store.setStatus(status, for: task, at: clock.now) }
            case .setStatus(let ref, let status):
                guard let task = resolve(ref) else { continue }
                setStatus(status, for: task)
            case .startTimer(let ref, let minutes):
                guard let task = resolve(ref) else { continue }
                start(task, minutes: minutes)
            case .addNote(let ref, let note):
                guard let task = resolve(ref) else { continue }
                store.updateNote(note, forTaskWith: task.id)
            case .setCategory(let ref, let categoryID, _):
                guard let task = resolve(ref) else { continue }
                store.setCategory(categoryID, forTaskWith: task.id)
            case .setDueDate(let ref, let date):
                guard let task = resolve(ref) else { continue }
                store.setDueDate(date, forTaskWith: task.id)
            case .deleteTask(let ref):
                guard let task = resolve(ref) else { continue }
                delete(task)
            case .scheduleFollowUp(let ref, let date, let destination):
                guard let task = resolve(ref) else { continue }
                await scheduleFollowUp(for: task, at: date, destination: destination)
            }
            refresh()
        }
        chat?.noteApplied(actions.count)
        refresh()
    }

    /// Follow-up creation used by the chat, independent of the completion prompt.
    private func scheduleFollowUp(for task: TaskItem, at date: Date, destination: FollowUpDestination) async {
        guard let scheduler else {
            chatError = "Follow-ups are unavailable in this build."
            return
        }
        guard await scheduler.requestAccess(to: destination) else {
            chatError = FollowUpError.accessDenied(destination).message
            return
        }
        do {
            let externalID = try await scheduler.schedule(
                ScheduleRequest(
                    title: "Follow up: \(task.title)",
                    notes: task.note,
                    date: date,
                    destination: destination,
                    targetID: prefs.followUpTargetID(for: destination)
                )
            )
            store.record(
                FollowUpRecord(
                    taskID: task.id, taskTitle: task.title, scheduledFor: date,
                    destination: destination, externalID: externalID, createdAt: clock.now
                )
            )
        } catch let error as FollowUpError {
            chatError = error.message
        } catch {
            chatError = error.localizedDescription
        }
    }

    // MARK: - Completion log

    /// Default block for a task finished without ever running a timer.
    public static let untimedCompletionSeconds: TimeInterval = 15 * 60

    /// Records the finished task on the calendar, ending at the moment it was
    /// completed and reaching back over the time actually focused on it.
    private func logCompletion(taskID: UUID, title: String, focusedSeconds: Double, finishedAt: Date) {
        guard logCompletions, let scheduler else { return }
        let duration = focusedSeconds > 0 ? focusedSeconds : Self.untimedCompletionSeconds
        let start = finishedAt.addingTimeInterval(-duration)
        let note = store.task(id: taskID)?.note ?? ""
        let request = ScheduleRequest(
            title: "\(title) \u{2705}",
            notes: [note.isEmpty ? nil : note, "Focused \(duration.compactDuration)"]
                .compactMap { $0 }.joined(separator: "\n\n"),
            date: start,
            destination: .calendar,
            targetID: prefs.followUpTargetID(for: .calendar),
            duration: duration
        )

        Task { [weak self] in
            guard let self else { return }
            guard await scheduler.requestAccess(to: .calendar) else {
                self.completionLogError = FollowUpError.accessDenied(.calendar).message
                return
            }
            do {
                let eventID = try await scheduler.schedule(request)
                self.store.setCompletionEventID(eventID, forTaskWith: taskID)
                self.refresh()
            } catch let error as FollowUpError {
                self.completionLogError = error.message
            } catch {
                self.completionLogError = error.localizedDescription
            }
        }
    }

    private func unlogCompletion(_ task: TaskItem) {
        let eventID = task.completionEventID
        guard !eventID.isEmpty, let scheduler else { return }
        store.setCompletionEventID("", forTaskWith: task.id)
        Task { try? await scheduler.remove(id: eventID, destination: .calendar) }
    }

    // MARK: - Progress and Slack

    private var lastLevel: Int?
    private var lastStatusText: String?
    private var lastStatusPush: Date?
    /// How stale a status may get before it is pushed again, so the day's
    /// progress stays current without writing to Slack on every tick.
    public static let slackRefreshInterval: TimeInterval = 5 * 60

    private static let bragSystem = """
    You write one short Slack message celebrating what someone got done, from \
    their real figures. Rules:
    - Use only the figures given. Never invent a number, a task or a project.
    - Warm and specific, not corporate. Two or three sentences at most.
    - Write about them in the third person, by name.
    - End with exactly this line, on its own: "— written by Floater AI"
    - No hashtags, no emoji spam. One or two emoji at most.
    """

    /// Pushes the current figures to Slack as a status, when the user has asked
    /// for that. Skips an unchanged status so Slack is not written to on every
    /// tick.
    public func syncSlackStatus(force: Bool = false) async {
        guard slackStatusEnabled, let slack, let stats else { return }
        let text = SlackStatus.text(for: stats, focusing: isRunning,
                                    at: clock.now, calendar: calendar)
        let stale = lastStatusPush.map { clock.now.timeIntervalSince($0) >= Self.slackRefreshInterval } ?? true
        guard force || text != lastStatusText || stale else { return }
        do {
            try await slack.setStatus(text: text,
                                      emoji: SlackStatus.emoji(for: stats, focusing: isRunning))
            lastStatusText = text
            lastStatusPush = clock.now
            slackError = nil
        } catch let error as SlackError {
            handle(error)
        } catch {
            slackError = error.localizedDescription
        }
    }

    /// Slack errors that mean the token will never work again. Retrying one of
    /// these every few minutes forever helps nobody, so the feature switches
    /// itself off and the dead token is dropped.
    private static let deadTokenCodes: Set<String> = [
        "invalid_auth", "token_revoked", "token_expired", "account_inactive", "not_authed",
    ]

    private func handle(_ error: SlackError) {
        slackError = error.message
        guard case .api(let code) = error, Self.deadTokenCodes.contains(code) else { return }
        slackStatusEnabled = false
        secrets.setSecret(nil, for: .slack)
        slackError = "Slack disconnected — the token was revoked or expired. Add a new one to reconnect."
    }

    /// Clears the status Floater set, so turning the feature off leaves nothing behind.
    public func clearSlackStatus() async {
        guard let slack else { return }
        do {
            try await slack.setStatus(text: "", emoji: "")
            lastStatusText = nil
        } catch { /* leaving a stale status is not worth surfacing */ }
    }

    /// Asks Claude to write up the week from real figures, and posts it.
    public func postWeekToSlack(name: String) async {
        guard !isGenerating else { return }
        prepareChat()
        guard let chat else {
            slackError = ClaudeError.missingAPIKey.message
            return
        }
        guard let slack else {
            slackError = SlackError.notConnected.message
            return
        }
        isGenerating = true
        defer { isGenerating = false }

        let facts = digest(days: 7).factSheet(calendar: calendar)
        let stats = self.stats
        var brief = "Name: \(name)\n\n" + facts
        if let stats {
            brief += """


            Level \(stats.level), \(stats.totalXP) XP total.
            Streak: \(stats.streakDays) day\(stats.streakDays == 1 ? "" : "s").
            Badges earned: \(stats.earnedBadges.map(\.name).joined(separator: ", "))
            """
        }

        do {
            let text = try await chat.oneOff(system: Self.bragSystem, user: brief, maxTokens: 600)
            let channel = prefs.slackChannel.isEmpty ? nil : prefs.slackChannel
            try await slack.post(text: text, channel: channel)
            store.appendChat(role: "assistant", text: "Posted to Slack:\n\n" + text, at: clock.now)
            slackError = nil
            refresh()
        } catch let error as SlackError {
            slackError = error.message
        } catch let error as ClaudeError {
            slackError = error.message
        } catch {
            slackError = error.localizedDescription
        }
    }

    // MARK: - Digest and prompt generation

    public func digest(days: Int) -> Digest {
        store.digest(days: days, now: clock.now, calendar: calendar)
    }

    nonisolated static let digestBaseSystem = """
    You turn a fact sheet of finished work into release notes a colleague can \
    read. Follow the house style below exactly.

    Use only what is in the fact sheet. Never invent a change, a number or a \
    project. Output the notes themselves — no preamble, no sign-off.
    """

    /// The base rules plus the editable house style.
    nonisolated static func digestSystem() -> String {
        guard let style = PromptBuilder.skills["changelog"] else { return digestBaseSystem }
        return digestBaseSystem + "\n\n" + style
    }

    /// Writes up the period from real figures. Claude phrases it; the numbers
    /// come from the store.
    public func generateDigest(days: Int) async {
        guard !isGenerating else { return }
        prepareChat()
        guard let chat else {
            chatError = ClaudeError.missingAPIKey.message
            return
        }
        digestDays = days
        isGenerating = true
        chatError = nil
        defer { isGenerating = false }

        let facts = digest(days: days).factSheet(calendar: calendar)
        store.appendChat(role: "user", text: "What did I do in the last \(days) days?", at: clock.now)
        refresh()
        do {
            let text = try await chat.oneOff(system: Self.digestSystem(), user: facts, maxTokens: 2048)
            store.appendChat(role: "assistant", text: text, at: clock.now)
            lastGenerated = text
            refresh()
        } catch let error as ClaudeError {
            chatError = error.message
        } catch {
            chatError = error.localizedDescription
        }
    }

    /// Turns a task into a prompt for Claude Code, informed by its project.
    public func generateClaudeCodePrompt(for task: TaskItem) async {
        guard !isGenerating else { return }
        prepareChat()
        guard let chat else {
            chatError = ClaudeError.missingAPIKey.message
            return
        }
        isGenerating = true
        chatError = nil
        defer { isGenerating = false }

        let categoryName = category(of: task)?.name
        let repoPath = category(of: task)?.repoPath ?? ""
        var context = ProjectContext.empty
        if !repoPath.isEmpty, let reader = projectContext {
            context = await reader.context(
                forRepoAt: repoPath,
                projectName: categoryName ?? "",
                matching: PromptBuilder.keywords(for: task, categoryName: categoryName)
            )
        }

        var dueDescription: String?
        if let due = task.dueDate {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "EEE d MMM"
            dueDescription = formatter.string(from: due)
        }

        let brief = PromptBuilder.brief(task: task, categoryName: categoryName,
                                        dueDescription: dueDescription, context: context)
        let system = PromptBuilder.system(
            includeUITaste: PromptBuilder.isUITask(task, categoryName: categoryName)
        )
        store.appendChat(role: "user", text: "Write a Claude Code prompt for: \(task.title)", at: clock.now)
        refresh()
        do {
            let text = try await chat.oneOff(system: system, user: brief, maxTokens: 2048)
            store.appendChat(role: "assistant", text: text, at: clock.now)
            lastGenerated = text
            refresh()
        } catch let error as ClaudeError {
            chatError = error.message
        } catch {
            chatError = error.localizedDescription
        }
    }

    // MARK: - Follow-ups

    /// Calendars / lists the user can send follow-ups to, asking for access if
    /// it has not been granted yet. Only for an explicit user action.
    public func availableTargets(for destination: FollowUpDestination) async -> [FollowUpTarget] {
        guard let scheduler else { return [] }
        guard await scheduler.requestAccess(to: destination) else { return [] }
        return await scheduler.availableTargets(for: destination)
    }

    /// The same list, but never prompts — returns nothing when access is absent.
    /// Safe to call at launch and on every menu open.
    public func knownTargets(for destination: FollowUpDestination) async -> [FollowUpTarget] {
        guard let scheduler else { return [] }
        return await scheduler.availableTargets(for: destination)
    }

    public func selectedTargetID(for destination: FollowUpDestination) -> String? {
        prefs.followUpTargetID(for: destination)
    }

    public func selectTarget(_ id: String?, for destination: FollowUpDestination) {
        prefs.setFollowUpTargetID(id, for: destination)
    }

    public func followUp(for task: TaskItem) -> FollowUpRecord? {
        store.followUp(forTaskWith: task.id)
    }

    public func previewDate(for offset: FollowUpOffset) -> Date {
        offset.resolve(from: clock.now, calendar: calendar)
    }

    public func pinFollowUpPrompt() {
        followUpPromptPinned = true
    }

    public func dismissFollowUp() {
        pendingFollowUp = nil
        followUpError = nil
        followUpPromptPinned = false
        isSchedulingFollowUp = false
    }

    /// Creates the follow-up in the chosen app. Leaves the prompt open on
    /// failure so the reason is visible rather than silently swallowed.
    public func scheduleFollowUp(_ offset: FollowUpOffset) async {
        guard let pending = pendingFollowUp, !isSchedulingFollowUp else { return }
        guard let scheduler else {
            followUpError = .underlying("Follow-ups are unavailable in this build.")
            followUpPromptPinned = true
            return
        }
        let destination = followUpDestination
        let date = offset.resolve(from: clock.now, calendar: calendar)

        isSchedulingFollowUp = true
        followUpError = nil
        defer { isSchedulingFollowUp = false }

        guard await scheduler.requestAccess(to: destination) else {
            followUpError = .accessDenied(destination)
            followUpPromptPinned = true
            return
        }

        do {
            let externalID = try await scheduler.schedule(
                ScheduleRequest(
                    title: "Follow up: \(pending.taskTitle)",
                    notes: notes(for: pending),
                    date: date,
                    destination: destination,
                    targetID: prefs.followUpTargetID(for: destination)
                )
            )
            store.record(
                FollowUpRecord(
                    taskID: pending.taskID,
                    taskTitle: pending.taskTitle,
                    scheduledFor: date,
                    destination: destination,
                    externalID: externalID,
                    createdAt: clock.now
                )
            )
            pendingFollowUp = nil
            followUpPromptPinned = false
            refresh()
        } catch let error as FollowUpError {
            followUpError = error
            followUpPromptPinned = true
        } catch {
            followUpError = .underlying(error.localizedDescription)
            followUpPromptPinned = true
        }
    }

    private func notes(for pending: PendingFollowUp) -> String {
        var lines: [String] = []
        if !pending.note.isEmpty { lines.append(pending.note) }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var summary = "Completed \(formatter.string(from: pending.completedAt))"
        if pending.secondsFocused > 0 {
            summary += " · \(pending.secondsFocused.compactDuration) focused"
        }
        lines.append(summary)
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Timer actions

    public func start(_ task: TaskItem, minutes: Int) {
        if engine.isActive { _ = finishActiveRun(completedTask: false) }
        store.rememberPlan(minutes: minutes, forTaskWith: task.id)
        if task.status != .inProgress {
            store.setStatus(.inProgress, for: task, at: clock.now)
        }
        runStartedAt = clock.now
        engine.start(taskID: task.id, title: task.title, minutes: minutes)
        mode = .collapsed
        refresh()
        Task { await syncSlackStatus(force: true) }
    }

    public func togglePause() {
        switch phase {
        case .running: engine.pause()
        case .paused: engine.resume()
        default: return
        }
        refresh()
    }

    public func extend(minutes: Int) {
        guard engine.isActive else { return }
        engine.extend(minutes: minutes)
        onDismissTimeUp?()
        refresh()
        onExtend?(minutes)
    }

    /// "Stop": bank the focused time, leave the task open.
    public func stopTimer() {
        _ = finishActiveRun(completedTask: false)
        onDismissTimeUp?()
        refresh()
        Task { await syncSlackStatus(force: true) }
    }

    /// "Done" from the time-up takeover.
    public func completeActiveTask() {
        guard let task = activeTask else { return stopTimer() }
        onDismissTimeUp?()
        complete(task)
    }

    /// Drives the countdown forward. Called by the ticker, on wake, and by tests.
    public func tick() {
        engine.tick()
        refresh()
    }

    // MARK: - Internals

    private func handleElapsed(_ run: FocusRun) {
        attentionPulse += 1
        onTimeUp?(run)
    }

    /// Ends the current run and writes a session record. Returns the focused
    /// seconds only when the caller is about to bank them itself, so time is
    /// never counted twice.
    @discardableResult
    private func finishActiveRun(completedTask: Bool) -> Double {
        guard let run = engine.run, let result = engine.stop() else { return 0 }
        let seconds = result.elapsed
        store.record(
            FocusSessionRecord(
                taskID: run.taskID,
                taskTitle: run.taskTitle,
                startedAt: runStartedAt ?? run.startedAt,
                endedAt: clock.now,
                plannedMinutes: Int(run.plannedSeconds / 60),
                secondsFocused: seconds,
                completedTask: completedTask
            )
        )
        if !completedTask {
            store.addFocusTime(seconds, toTaskWith: run.taskID)
        }
        runStartedAt = nil
        return completedTask ? seconds : 0
    }

    private func restoreActiveRun() {
        guard let saved = prefs.loadActiveRun() else { return }
        runStartedAt = saved.run.startedAt
        engine.restore(saved.run, phase: saved.phase)
    }

    /// Note and scratchpad edits land on a short debounce; every other write is
    /// immediate.
    private func startDebouncedWrites() {
        noteEdits
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] edit in
                guard let self else { return }
                self.store.updateNote(edit.text, forTaskWith: edit.id)
                self.refresh()
            }
            .store(in: &cancellables)

        $scratchpad
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] text in self?.store.scratchpadText = text }
            .store(in: &cancellables)
    }

    private func startTicking() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Ticks per Slack check: a status does not need to be reconsidered four
    /// times a second.
    private static let ticksPerSlackCheck = 120
    private var ticksSinceSlackCheck = 0

    /// The hot path. A countdown changing is not a reason to re-read the
    /// database, recompute every statistic and write to disk — which is what
    /// calling the full refresh here was doing, four times a second, forever.
    private func onTick() {
        let justElapsed = engine.tick()
        if justElapsed || phase != engine.phase {
            refresh()
        } else if engine.isActive {
            // Nothing is counting down when idle, so there is nothing to update.
            refreshTimerDisplay()
        }

        ticksSinceSlackCheck += 1
        if ticksSinceSlackCheck >= Self.ticksPerSlackCheck {
            ticksSinceSlackCheck = 0
            Task { await syncSlackStatus() }
        }
    }

    /// Only the values that change as the clock moves. No store access, no
    /// writes, no statistics — and each one published only when it actually
    /// differs, because every assignment to a @Published re-renders the panel
    /// whether or not the value changed.
    public func refreshTimerDisplay() {
        let newPhase = engine.phase
        if phase != newPhase { phase = newPhase }

        // The countdown is shown in whole seconds. Publishing four times a
        // second to redraw the same digits is four times the work for no
        // visible difference.
        let newRemaining = engine.remaining
        if Int(newRemaining.rounded(.up)) != Int(remaining.rounded(.up)) {
            remaining = newRemaining
        }

        let newProgress = engine.progress
        if abs(newProgress - progress) > 0.002 { progress = newProgress }
    }

    /// Pulls the latest state out of the store and engine into published values.
    public func refresh() {
        store.reload()
        tasks = store.tasks
        completedToday = store.completedOn(clock.now).count
        chatMessages = store.chatMessages
        categories = store.categories
        phase = engine.phase
        remaining = engine.remaining
        progress = engine.progress
        activeTaskID = engine.run?.taskID
        activeTitle = engine.run?.taskTitle ?? ""
        activePlannedMinutes = Int((engine.run?.plannedSeconds ?? 0) / 60)
        prefs.saveActiveRun(engine.run, phase: engine.phase)

        let fresh = store.gameStats(now: clock.now, calendar: calendar,
                                    goalKind: goalKind, goalTarget: goalTarget)
        if let previous = lastLevel, fresh.level > previous { levelUps += 1 }
        lastLevel = fresh.level
        stats = fresh
    }
}
