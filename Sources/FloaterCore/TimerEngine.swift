import Foundation

/// A single focus session attached to one task.
///
/// The countdown is *deadline based*, never tick-counting: `remaining` is always
/// recomputed as `deadline - now`. That makes it immune to dropped timer ticks,
/// machine sleep, and the app being quit and relaunched.
public struct FocusRun: Equatable, Codable {
    public var taskID: UUID
    public var taskTitle: String
    /// Total time budgeted for this run, including any extensions.
    public var plannedSeconds: TimeInterval
    public var startedAt: Date
    public var deadline: Date
    /// When the current running segment began. `nil` while paused.
    public var segmentStart: Date?
    /// Work time banked from segments that have already ended.
    public var bankedElapsed: TimeInterval
    /// Frozen countdown value while paused. `nil` while running.
    public var remainingAtPause: TimeInterval?

    public init(
        taskID: UUID,
        taskTitle: String,
        plannedSeconds: TimeInterval,
        startedAt: Date,
        deadline: Date,
        segmentStart: Date?,
        bankedElapsed: TimeInterval = 0,
        remainingAtPause: TimeInterval? = nil
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.plannedSeconds = plannedSeconds
        self.startedAt = startedAt
        self.deadline = deadline
        self.segmentStart = segmentStart
        self.bankedElapsed = bankedElapsed
        self.remainingAtPause = remainingAtPause
    }
}

public enum TimerPhase: String, Equatable, Codable {
    case idle
    case running
    case paused
    /// Hit zero and is waiting for the user to say what happened.
    case elapsed
}

public final class TimerEngine {
    public private(set) var run: FocusRun?
    public private(set) var phase: TimerPhase = .idle

    /// Fired exactly once per run when the countdown reaches zero.
    public var onElapsed: ((FocusRun) -> Void)?

    private let clock: Clock

    public init(clock: Clock = SystemClock()) {
        self.clock = clock
    }

    // MARK: - Derived values

    public var remaining: TimeInterval {
        guard let run else { return 0 }
        if let paused = run.remainingAtPause { return paused }
        return max(0, run.deadline.timeIntervalSince(clock.now))
    }

    /// Actual work time spent on this run so far, excluding paused stretches.
    public var elapsed: TimeInterval {
        guard let run else { return 0 }
        guard let segmentStart = run.segmentStart else { return run.bankedElapsed }
        // Never bank time past the deadline; a machine that slept for an hour
        // should not report an hour of focus.
        let segmentEnd = min(clock.now, run.deadline)
        return run.bankedElapsed + max(0, segmentEnd.timeIntervalSince(segmentStart))
    }

    public var progress: Double {
        guard let run, run.plannedSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / run.plannedSeconds))
    }

    public var isActive: Bool { phase != .idle }

    // MARK: - Commands

    public func start(taskID: UUID, title: String, minutes: Int) {
        let seconds = TimeInterval(minutes * 60)
        let now = clock.now
        run = FocusRun(
            taskID: taskID,
            taskTitle: title,
            plannedSeconds: seconds,
            startedAt: now,
            deadline: now.addingTimeInterval(seconds),
            segmentStart: now
        )
        phase = .running
    }

    public func pause() {
        guard phase == .running, var current = run else { return }
        current.bankedElapsed = elapsed
        current.remainingAtPause = remaining
        current.segmentStart = nil
        run = current
        phase = .paused
    }

    public func resume() {
        guard phase == .paused, var current = run else { return }
        let now = clock.now
        current.deadline = now.addingTimeInterval(current.remainingAtPause ?? 0)
        current.remainingAtPause = nil
        current.segmentStart = now
        run = current
        phase = .running
    }

    /// Adds time to the current run. Valid while running, paused, or elapsed —
    /// from `.elapsed` this is the "+10 min" escape hatch and resumes the run.
    public func extend(minutes: Int) {
        guard var current = run else { return }
        let seconds = TimeInterval(minutes * 60)
        current.plannedSeconds += seconds
        switch phase {
        case .running:
            current.deadline = current.deadline.addingTimeInterval(seconds)
        case .paused:
            current.remainingAtPause = (current.remainingAtPause ?? 0) + seconds
        case .elapsed:
            let now = clock.now
            current.deadline = now.addingTimeInterval(seconds)
            current.segmentStart = now
            current.remainingAtPause = nil
            phase = .running
        case .idle:
            return
        }
        run = current
    }

    /// Ends the run and reports the work time it accumulated.
    @discardableResult
    public func stop() -> (taskID: UUID, elapsed: TimeInterval)? {
        guard let current = run else { return nil }
        let spent = elapsed
        run = nil
        phase = .idle
        return (current.taskID, spent)
    }

    /// Recomputes state against the current clock. Safe to call at any frequency;
    /// `onElapsed` fires at most once per run no matter how far the clock jumped.
    @discardableResult
    public func tick() -> Bool {
        guard phase == .running, var current = run else { return false }
        guard clock.now >= current.deadline else { return false }
        // Bank work time up to the deadline, not up to now.
        if let segmentStart = current.segmentStart {
            current.bankedElapsed += max(0, current.deadline.timeIntervalSince(segmentStart))
        }
        current.segmentStart = nil
        current.remainingAtPause = 0
        run = current
        phase = .elapsed
        onElapsed?(current)
        return true
    }

    // MARK: - Persistence across launches

    /// Restores a run saved before the app quit. Returns true if the deadline
    /// passed while the app was gone, so the caller can surface the time-up UI.
    @discardableResult
    public func restore(_ saved: FocusRun, phase savedPhase: TimerPhase) -> Bool {
        run = saved
        phase = savedPhase
        guard savedPhase == .running else { return false }
        return tick()
    }
}
