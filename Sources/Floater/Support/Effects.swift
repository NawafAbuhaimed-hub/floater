import FloaterCore
import AppKit
import UserNotifications

/// System sounds — no bundled assets to ship or keep in sync.
enum Sounds {
    static func celebrate() { NSSound(named: "Hero")?.play() }
    static func timeUp() { NSSound(named: "Submarine")?.play() }
    static func tap() { NSSound(named: "Pop")?.play() }
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
