import Foundation
import Combine

/// Single source of truth for the UI. Owns the store and the timer engine and
/// republishes their state so SwiftUI can render it.
@MainActor
public final class AppModel: ObservableObject {
    public enum Mode { case collapsed, expanded }
    public enum Tab: String, CaseIterable, Identifiable {
        case tasks, notes
        public var id: String { rawValue }
        public var title: String { self == .tasks ? "Tasks" : "Notes" }
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
    @Published public var mode: Mode = .collapsed
    @Published public var tab: Tab = .tasks
    /// The task whose note is open inline, if any.
    @Published public var expandedTaskID: UUID?
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

    public let timerLengths = [15, 30, 45]

    private let store: Store
    private let engine: TimerEngine
    private let prefs: Preferences
    private let clock: Clock
    private var ticker: Timer?
    private var runStartedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    private let noteEdits = PassthroughSubject<(id: UUID, text: String), Never>()

    public init(
        store: Store,
        prefs: Preferences = Preferences(),
        clock: Clock = SystemClock(),
        autoTick: Bool = true
    ) {
        self.store = store
        self.prefs = prefs
        self.clock = clock
        self.engine = TimerEngine(clock: clock)
        self.soundEnabled = prefs.soundEnabled
        self.takeoverEnabled = prefs.takeoverEnabled
        engine.onElapsed = { [weak self] run in
            self?.handleElapsed(run)
        }
        self.scratchpad = store.scratchpadText
        restoreActiveRun()
        refresh()
        startDebouncedWrites()
        if autoTick { startTicking() }
    }

    deinit { ticker?.invalidate() }

    public var openTasks: [TaskItem] { tasks.filter { !$0.isDone } }
    public var doneCount: Int { tasks.count - openTasks.count }
    public var isRunning: Bool { phase == .running }
    public var isActive: Bool { phase != .idle }
    public var activeTask: TaskItem? { activeTaskID.flatMap { id in tasks.first { $0.id == id } } }

    public var remainingText: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Task actions

    public func addDraftTask() {
        guard store.add(title: draft) != nil else { return }
        draft = ""
        refresh()
    }

    public func complete(_ task: TaskItem) {
        let banked = task.id == activeTaskID ? finishActiveRun(completedTask: true) : 0
        store.complete(task, at: clock.now, addingSeconds: banked)
        let title = task.title
        refresh()
        onCelebrate?(title)
    }

    public func reopen(_ task: TaskItem) {
        store.reopen(task)
        refresh()
    }

    public func delete(_ task: TaskItem) {
        if task.id == activeTaskID { _ = finishActiveRun(completedTask: false) }
        store.delete(task)
        refresh()
    }

    public func clearCompleted() {
        store.clearCompleted()
        refresh()
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

    public func toggleNote(for task: TaskItem) {
        expandedTaskID = expandedTaskID == task.id ? nil : task.id
    }

    public func noteChanged(_ text: String, for task: TaskItem) {
        noteEdits.send((id: task.id, text: text))
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
        engine.extend(minutes: minutes)
        onDismissTimeUp?()
        refresh()
    }

    /// "Stop": bank the focused time, leave the task open.
    public func stopTimer() {
        _ = finishActiveRun(completedTask: false)
        onDismissTimeUp?()
        refresh()
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
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Pulls the latest state out of the store and engine into published values.
    public func refresh() {
        store.reload()
        tasks = store.tasks
        completedToday = store.completedOn(clock.now).count
        phase = engine.phase
        remaining = engine.remaining
        progress = engine.progress
        activeTaskID = engine.run?.taskID
        activeTitle = engine.run?.taskTitle ?? ""
        activePlannedMinutes = Int((engine.run?.plannedSeconds ?? 0) / 60)
        prefs.saveActiveRun(engine.run, phase: engine.phase)
    }
}
