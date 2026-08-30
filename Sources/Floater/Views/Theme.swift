import FloaterCore
import SwiftUI

enum Theme {
    static let corner: CGFloat = 16
    static let pillCorner: CGFloat = 28

    /// Ring colour escalates as the clock runs out.
    static func urgency(remaining: TimeInterval, active: Bool) -> Color {
        guard active else { return .secondary }
        if remaining <= 30 { return Color(red: 1.0, green: 0.27, blue: 0.23) }
        if remaining <= 120 { return Color(red: 1.0, green: 0.62, blue: 0.04) }
        return Color(red: 0.19, green: 0.82, blue: 0.35)
    }

    static let accent = Color(red: 0.19, green: 0.82, blue: 0.35)
}

/// The frosted capsule / card the panel content sits on.
struct GlassBackground: View {
    var cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }
}

struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
    }
}

extension TimeInterval {
    /// "1h 12m", "45m", "30s" — for time banked against a task.
    var compactDuration: String {
        let total = Int(self.rounded())
        if total >= 3600 {
            let h = total / 3600, m = (total % 3600) / 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        if total >= 60 { return "\(total / 60)m" }
        return "\(total)s"
    }
}
