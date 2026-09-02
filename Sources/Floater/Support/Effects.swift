import FloaterCore
import AppKit
import UserNotifications

enum Sounds {
    /// Held so the sound is not deallocated mid-playback.
    private static var player: NSSound?
    private static var rotation: SoundRotation?

    /// Every mp3 in the bundle joins the rotation, in filename order — dropping
    /// a new one into Resources/Sounds is all it takes to add it.
    static func configure(prefs: Preferences) {
        let names = (Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
        rotation = SoundRotation(names: names, prefs: prefs)
    }

    /// The next completion sound, falling back to a system one if the bundle
    /// has none.
    static func celebrate() {
        if let name = rotation?.next(),
           let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
           let sound = NSSound(contentsOf: url, byReference: true) {
            player?.stop()
            player = sound
            sound.play()
            return
        }
        NSSound(named: "Hero")?.play()
    }

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
