import Foundation

/// Floater's character: a small tree sprout who reacts to how the day is
/// going. He has twelve moods, and which one he is in is decided entirely by
/// the state the app already tracks — never at random, so the same day always
/// produces the same face.
public enum MascotMood: String, CaseIterable, Sendable {
    /// A timer just started.
    case gearUp
    /// Past halfway through a run.
    case lockedIn
    /// Under two minutes left.
    case finalStretch
    /// A task was finished moments ago.
    case victory
    /// Three days or more in a row.
    case onFire
    /// Today's goal is met.
    case legend
    /// A timer is paused.
    case paused
    /// Something is past its due date.
    case nagging
    /// A task is blocked.
    case stuck
    /// Early morning or late evening.
    case sleepy
    /// Nothing running, tasks waiting, and it has been a while.
    case bored
    /// Nothing to report.
    case chilling

    /// What he says. Short — it sits in a small bubble beside him.
    public var line: String {
        switch self {
        case .gearUp: return "I am Groot."
        case .lockedIn: return "We are Groot."
        case .finalStretch: return "Oh yeah. We're doing this."
        case .victory: return "I AM GROOT!"
        case .onFire: return "Nothing goes over my head."
        case .legend: return "King of the Pirates energy."
        case .paused: return "I am Groot?"
        case .nagging: return "Something is overdue, pal."
        case .stuck: return "This one's stuck. Unstick it."
        case .sleepy: return "I am sleep."
        case .bored: return "I am bored."
        case .chilling: return "I am Groot."
        }
    }

    /// A one-word label, for tooltips and tests.
    public var name: String {
        switch self {
        case .gearUp: return "Gear up"
        case .lockedIn: return "Locked in"
        case .finalStretch: return "Final stretch"
        case .victory: return "Victory"
        case .onFire: return "On fire"
        case .legend: return "Legend"
        case .paused: return "Paused"
        case .nagging: return "Nagging"
        case .stuck: return "Stuck"
        case .sleepy: return "Sleepy"
        case .bored: return "Bored"
        case .chilling: return "Chilling"
        }
    }
}

/// Everything the mood depends on, gathered in one value so the choice is a
/// pure function and can be tested without an app.
public struct MascotInput: Equatable, Sendable {
    public var phase: TimerPhase
    /// 0...1 through the current run.
    public var progress: Double
    /// Seconds left on the current run.
    public var remaining: TimeInterval
    /// Seconds since the last task was finished, or nil if none today.
    public var secondsSinceCompletion: TimeInterval?
    /// Seconds since anything at all happened, for spotting an idle desk.
    public var secondsSinceActivity: TimeInterval
    public var streakDays: Int
    public var goalMet: Bool
    public var overdue: Int
    public var blocked: Int
    /// Tasks still to do.
    public var openTasks: Int
    /// Hour of the day, 0...23.
    public var hour: Int

    public init(
        phase: TimerPhase = .idle,
        progress: Double = 0,
        remaining: TimeInterval = 0,
        secondsSinceCompletion: TimeInterval? = nil,
        secondsSinceActivity: TimeInterval = 0,
        streakDays: Int = 0,
        goalMet: Bool = false,
        overdue: Int = 0,
        blocked: Int = 0,
        openTasks: Int = 0,
        hour: Int = 12
    ) {
        self.phase = phase
        self.progress = progress
        self.remaining = remaining
        self.secondsSinceCompletion = secondsSinceCompletion
        self.secondsSinceActivity = secondsSinceActivity
        self.streakDays = streakDays
        self.goalMet = goalMet
        self.overdue = overdue
        self.blocked = blocked
        self.openTasks = openTasks
        self.hour = hour
    }
}

extension MascotMood {
    /// How long a finish keeps him celebrating.
    public static let victoryWindow: TimeInterval = 90
    /// Under this many seconds left is the final stretch.
    public static let finalStretchSeconds: TimeInterval = 120
    /// Idle this long with work waiting and he gets bored.
    public static let boredAfter: TimeInterval = 20 * 60
    /// A streak this long sets the sprout alight.
    public static let onFireDays = 3

    /// Picks the mood. Several conditions are often true at once, so the order
    /// below is the precedence, highest first:
    ///
    /// 1. `victory` — a finish always gets celebrated, running or not.
    /// 2. `finalStretch` — the clock is nearly out.
    /// 3. `paused` — a run is on hold.
    /// 4. `lockedIn` — past halfway.
    /// 5. `gearUp` — a run just began.
    /// 6. `legend` — the day's goal is met.
    /// 7. `onFire` — a streak is going.
    /// 8. `nagging` — something is overdue.
    /// 9. `stuck` — something is blocked.
    /// 10. `sleepy` — before 7am or 9pm and after.
    /// 11. `bored` — idle a while with work waiting.
    /// 12. `chilling` — the fallback.
    ///
    /// The run moods (2, 4, 5) only apply while a timer is actually going, so
    /// an idle desk never claims to be locked in.
    public static func current(_ input: MascotInput) -> MascotMood {
        let running = input.phase == .running

        // 1. A finish is celebrated whatever the timer is doing.
        if let since = input.secondsSinceCompletion, since <= victoryWindow { return .victory }

        // 2-5. Run moods. Only a timer that is actually counting down (or held
        // on pause) gets one; .idle and .elapsed fall through to the idle moods.
        if running && input.remaining < finalStretchSeconds { return .finalStretch }
        if input.phase == .paused { return .paused }
        if running && input.progress >= 0.5 { return .lockedIn }
        if running { return .gearUp }

        // 6-12. Idle moods, most notable first.
        if input.goalMet { return .legend }
        if input.streakDays >= onFireDays { return .onFire }
        if input.overdue > 0 { return .nagging }
        if input.blocked > 0 { return .stuck }
        if input.hour < 7 || input.hour >= 21 { return .sleepy }
        if input.openTasks > 0 && input.secondsSinceActivity >= boredAfter { return .bored }
        return .chilling
    }
}
