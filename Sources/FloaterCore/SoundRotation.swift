import Foundation

/// Cycles through the completion sounds in order, remembering where it got to
/// so the rotation continues across launches.
public final class SoundRotation {
    private let names: [String]
    private let prefs: Preferences

    public init(names: [String], prefs: Preferences) {
        self.names = names
        self.prefs = prefs
    }

    public var count: Int { names.count }

    /// The next sound to play, advancing the rotation. `nil` when there are none.
    public func next() -> String? {
        guard !names.isEmpty else { return nil }
        // Modulo rather than a bounds check, so removing sounds cannot leave a
        // stored index pointing past the end.
        let index = ((prefs.completionSoundIndex % names.count) + names.count) % names.count
        prefs.completionSoundIndex = index + 1
        return names[index]
    }
}
