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

    static func color(for status: TaskStatus) -> Color {
        switch status {
        case .notStarted: return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .inProgress: return Color(red: 0.04, green: 0.52, blue: 1.00)
        case .blocked: return Color(red: 1.00, green: 0.27, blue: 0.23)
        case .done: return accent
        }
    }
}

/// The frosted capsule / card the panel content sits on.
struct GlassBackground: View {
    var cornerRadius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            // A white rim reads as a highlight in both appearances. `Color.primary`
            // resolves to black in light mode, which drew a hard black hairline.
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
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



/// The diagonal grip in the bottom-right corner. Dragging it resizes the panel.
struct ResizeGrip: View {
    @Environment(\.resizeWindow) private var resizeWindow
    @State private var last: CGSize = .zero
    @State private var hovering = false

    var body: some View {
        Canvas { context, size in
            let color = Color.primary.opacity(hovering ? 0.55 : 0.28)
            for offset in stride(from: CGFloat(0), through: 8, by: 4) {
                var path = Path()
                path.move(to: CGPoint(x: size.width - offset, y: size.height))
                path.addLine(to: CGPoint(x: size.width, y: size.height - offset))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
        }
        .frame(width: 14, height: 14)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let delta = CGSize(
                        width: value.translation.width - last.width,
                        height: value.translation.height - last.height
                    )
                    last = value.translation
                    resizeWindow?(delta)
                }
                .onEnded { _ in last = .zero }
        )
        .help("Drag to resize")
    }
}
