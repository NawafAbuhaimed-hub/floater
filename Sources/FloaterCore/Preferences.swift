import Foundation

/// The slice of `UserDefaults` that `Preferences` needs. Abstracting it keeps
/// tests entirely in memory instead of writing preference files to disk.
public protocol KeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

public final class InMemoryStore: KeyValueStore {
    private var values: [String: Any] = [:]
    public init() {}
    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
    public func removeObject(forKey key: String) { values[key] = nil }
}

/// Everything Floater remembers between launches.
public final class Preferences {
    private let store: KeyValueStore

    private enum Key {
        static let soundEnabled = "floater.soundEnabled"
        static let takeoverEnabled = "floater.takeoverEnabled"
        static let panelOrigin = "floater.panelOrigin"
        static let followUpDestination = "floater.followUpDestination"
        static let collapsedSize = "floater.collapsedSize"
        static let expandedSize = "floater.expandedSize"
        static let activeRun = "floater.activeRun"
        static let activePhase = "floater.activePhase"
    }

    public init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// Both toggles default to on, so an absent value reads as `true`.
    public var soundEnabled: Bool {
        get { store.object(forKey: Key.soundEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.soundEnabled) }
    }

    public var takeoverEnabled: Bool {
        get { store.object(forKey: Key.takeoverEnabled) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.takeoverEnabled) }
    }

    /// The destination used for the last follow-up, so the common case is one click.
    public var followUpDestination: FollowUpDestination {
        get {
            guard let raw = store.object(forKey: Key.followUpDestination) as? String,
                  let value = FollowUpDestination(rawValue: raw) else { return .calendar }
            return value
        }
        set { store.set(newValue.rawValue, forKey: Key.followUpDestination) }
    }

    public var panelOrigin: CGPoint? {
        get {
            guard let dict = store.object(forKey: Key.panelOrigin) as? [String: Any],
                  let x = dict["x"] as? Double, let y = dict["y"] as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            guard let newValue else { return store.removeObject(forKey: Key.panelOrigin) }
            store.set(["x": newValue.x, "y": newValue.y], forKey: Key.panelOrigin)
        }
    }

    /// Sizes the user dragged the panel to, remembered per mode.
    public var collapsedSize: CGSize? {
        get { size(forKey: Key.collapsedSize) }
        set { setSize(newValue, forKey: Key.collapsedSize) }
    }

    public var expandedSize: CGSize? {
        get { size(forKey: Key.expandedSize) }
        set { setSize(newValue, forKey: Key.expandedSize) }
    }

    private func size(forKey key: String) -> CGSize? {
        guard let dict = store.object(forKey: key) as? [String: Any],
              let w = dict["w"] as? Double, let h = dict["h"] as? Double else { return nil }
        return CGSize(width: w, height: h)
    }

    private func setSize(_ value: CGSize?, forKey key: String) {
        guard let value else { return store.removeObject(forKey: key) }
        store.set(["w": value.width, "h": value.height], forKey: key)
    }

    /// The in-flight focus run, so quitting or crashing does not lose the countdown.
    public func saveActiveRun(_ run: FocusRun?, phase: TimerPhase) {
        guard let run, phase != .idle else {
            store.removeObject(forKey: Key.activeRun)
            store.removeObject(forKey: Key.activePhase)
            return
        }
        if let data = try? JSONEncoder().encode(run) {
            store.set(data, forKey: Key.activeRun)
            store.set(phase.rawValue, forKey: Key.activePhase)
        }
    }

    public func loadActiveRun() -> (run: FocusRun, phase: TimerPhase)? {
        guard let data = store.object(forKey: Key.activeRun) as? Data,
              let run = try? JSONDecoder().decode(FocusRun.self, from: data),
              let raw = store.object(forKey: Key.activePhase) as? String,
              let phase = TimerPhase(rawValue: raw) else { return nil }
        return (run, phase)
    }
}
