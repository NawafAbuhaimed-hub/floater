import FloaterCore
import AppKit
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
    static let streak = Color(red: 1.00, green: 0.58, blue: 0.13)

    /// Category colours are stored as hex so they survive in SwiftData.
    static func color(hex: String) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
            .scanHexInt64(&value)
        guard value > 0 else { return .secondary }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func color(for state: DueState) -> Color {
        switch state {
        case .none: return .secondary
        case .upcoming: return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .today: return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .overdue: return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }

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
            // No stroke and no SwiftUI shadow. A shadow drawn inside the view is
            // clipped at the window bounds, and a soft gradient cut off mid-fall
            // reads as a hard dark line along the edge. The panel's native window
            // shadow is drawn by the window server outside those bounds instead,
            // so it can never be clipped.
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
    @State private var dragging = false
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
                .onChanged { _ in
                    // The pointer's screen position is the only measurement that
                    // stays valid while the window is being resized underneath it.
                    let point = NSEvent.mouseLocation
                    resizeWindow?(point, dragging ? .changed : .began)
                    dragging = true
                }
                .onEnded { _ in
                    dragging = false
                    resizeWindow?(NSEvent.mouseLocation, .ended)
                }
        )
        .help("Drag to resize")
    }
}
