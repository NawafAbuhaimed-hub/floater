import Foundation

/// Cycles through the completion sounds in order, remembering where it got to
/// so the rotation continues across launches.
public final class SoundRotation {
    private let names: [String]
    private let prefs: Preferences
    /// Each set ("done", "more") keeps its own position.
    private let key: String

    public init(names: [String], prefs: Preferences, key: String) {
        self.names = names
        self.prefs = prefs
        self.key = key
    }

    public var count: Int { names.count }

    /// The next sound to play, advancing the rotation. `nil` when there are none.
    public func next() -> String? {
        guard !names.isEmpty else { return nil }
        // Modulo rather than a bounds check, so removing sounds cannot leave a
        // stored index pointing past the end.
        let stored = prefs.soundIndex(forKey: key)
        let index = ((stored % names.count) + names.count) % names.count
        prefs.setSoundIndex(index + 1, forKey: key)
        return names[index]
    }
}
