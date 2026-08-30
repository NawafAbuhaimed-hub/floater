import Foundation

/// Everything Floater remembers between launches. Backed by UserDefaults, but
/// injectable so tests never touch the real domain.
public final class Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let soundEnabled = "floater.soundEnabled"
        static let takeoverEnabled = "floater.takeoverEnabled"
        static let panelOrigin = "floater.panelOrigin"
        static let activeRun = "floater.activeRun"
        static let activePhase = "floater.activePhase"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.soundEnabled: true,
            Key.takeoverEnabled: true,
        ])
    }

    public var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.soundEnabled) }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    public var takeoverEnabled: Bool {
        get { defaults.bool(forKey: Key.takeoverEnabled) }
        set { defaults.set(newValue, forKey: Key.takeoverEnabled) }
    }

    public var panelOrigin: CGPoint? {
        get {
            guard let dict = defaults.dictionary(forKey: Key.panelOrigin),
                  let x = dict["x"] as? Double, let y = dict["y"] as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else { return defaults.removeObject(forKey: Key.panelOrigin) }
            defaults.set(["x": newValue.x, "y": newValue.y], forKey: Key.panelOrigin)
        }
    }

    /// The in-flight focus run, so quitting or crashing does not lose the countdown.
    public func saveActiveRun(_ run: FocusRun?, phase: TimerPhase) {
        guard let run, phase != .idle else {
            defaults.removeObject(forKey: Key.activeRun)
            defaults.removeObject(forKey: Key.activePhase)
            return
        }
        if let data = try? JSONEncoder().encode(run) {
            defaults.set(data, forKey: Key.activeRun)
            defaults.set(phase.rawValue, forKey: Key.activePhase)
        }
    }

    public func loadActiveRun() -> (run: FocusRun, phase: TimerPhase)? {
        guard let data = defaults.data(forKey: Key.activeRun),
              let run = try? JSONDecoder().decode(FocusRun.self, from: data),
              let raw = defaults.string(forKey: Key.activePhase),
              let phase = TimerPhase(rawValue: raw) else { return nil }
        return (run, phase)
    }
}
