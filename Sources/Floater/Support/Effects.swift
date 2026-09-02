import FloaterCore
import AppKit
import UserNotifications

enum Sounds {
    /// Held so the sound is not deallocated mid-playback.
    private static var player: NSSound?
    /// One rotation per sound set: "done" on completion, "more" on extending.
    private static var rotations: [String: SoundRotation] = [:]

    /// Sets are directories inside the bundle, so dropping an mp3 into
    /// Resources/Sounds/<set> is all it takes to add one.
    static func configure(prefs: Preferences) {
        for set in ["done", "more"] {
            let names = (Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: set) ?? [])
                .map { $0.deletingPathExtension().lastPathComponent }
                .sorted()
            rotations[set] = SoundRotation(names: names, prefs: prefs, key: set)
        }
    }

    /// The next sound from a set, falling back to a system one if it is empty.
    private static func play(set: String, fallback: String) {
        if let name = rotations[set]?.next(),
           let url = Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: set),
           let sound = NSSound(contentsOf: url, byReference: true) {
            player?.stop()
            player = sound
            sound.play()
            return
        }
        NSSound(named: fallback)?.play()
    }

    static func celebrate() { play(set: "done", fallback: "Hero") }

    /// Played when more time is added to a task.
    static func moreTime() { play(set: "more", fallback: "Pop") }

    static func timeUp() { NSSound(named: "Submarine")?.play() }
}

/// Local notifications. Every call is best-effort: an unsigned or unbundled
/// build simply gets no banner, and the pill + overlay still do their job.
enum Notifier {
    private static var authorized = false
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, _ in
                DispatchQueue.main.async { authorized = granted }
            }
    }

    static func timeUp(taskTitle: String, minutes: Int) {
        guard available, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Time's up"
        content.body = "\(minutes) min on \"\(taskTitle)\" — did you finish?"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
