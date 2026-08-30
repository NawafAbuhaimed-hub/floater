import Foundation

public extension TimeInterval {
    /// "1h 12m", "45m", "30s" — for time banked against a task.
    var compactDuration: String {
        let total = Int(self.rounded())
        if total >= 3600 {
            let hours = total / 3600, minutes = (total % 3600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }
}
