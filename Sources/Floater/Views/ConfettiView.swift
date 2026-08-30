import FloaterCore
import SwiftUI

/// Confetti that bursts out of the pill and falls across the whole screen.
/// Rendered in a single Canvas so a few hundred pieces stay cheap.
struct ConfettiView: View {
    /// Launch point in this view's coordinate space (top-left origin).
    let origin: CGPoint
    var duration: Double = 1.9

    private static let palette: [Color] = [
        Color(red: 0.19, green: 0.82, blue: 0.35),
        Color(red: 1.00, green: 0.62, blue: 0.04),
        Color(red: 0.35, green: 0.62, blue: 1.00),
        Color(red: 1.00, green: 0.27, blue: 0.42),
        Color(red: 0.75, green: 0.45, blue: 1.00),
        Color(red: 1.00, green: 0.84, blue: 0.20),
    ]

    private struct Piece {
        let angle: Double
        let speed: Double
        let size: CGSize
        let color: Color
        let spin: Double
        let phase: Double
        let drift: Double
    }

    private let pieces: [Piece]
    @State private var launchedAt = Date()

    init(origin: CGPoint, duration: Double = 1.9, count: Int = 160) {
        self.origin = origin
        self.duration = duration
        var generator = SystemRandomNumberGenerator()
        pieces = (0..<count).map { _ in
            Piece(
                // Biased upward so it reads as a burst, not a spill.
                angle: Double.random(in: -Double.pi * 0.92 ... -Double.pi * 0.08, using: &generator),
                speed: Double.random(in: 260...820, using: &generator),
                size: CGSize(
                    width: Double.random(in: 5...11, using: &generator),
                    height: Double.random(in: 7...15, using: &generator)
                ),
                color: Self.palette.randomElement(using: &generator) ?? .green,
                spin: Double.random(in: -9...9, using: &generator),
                phase: Double.random(in: 0...(2 * Double.pi), using: &generator),
                drift: Double.random(in: 20...70, using: &generator)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { gc, _ in
                let t = context.date.timeIntervalSince(launchedAt)
                guard t < duration else { return }
                let gravity = 900.0

                for piece in pieces {
                    let vx = cos(piece.angle) * piece.speed
                    let vy = sin(piece.angle) * piece.speed
                    let sway = sin(t * 3 + piece.phase) * piece.drift * t
                    let x = origin.x + vx * t + sway
                    let y = origin.y + vy * t + 0.5 * gravity * t * t

                    let fade = t > duration * 0.55
                        ? max(0, 1 - (t - duration * 0.55) / (duration * 0.45))
                        : 1
                    guard fade > 0.01 else { continue }

                    var transform = gc
                    transform.opacity = fade
                    transform.translateBy(x: x, y: y)
                    transform.rotate(by: .radians(piece.spin * t))
                    let rect = CGRect(
                        x: -piece.size.width / 2, y: -piece.size.height / 2,
                        width: piece.size.width, height: piece.size.height
                    )
                    transform.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(piece.color)
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// The "task done" flourish: confetti plus a short-lived badge near the pill.
struct CelebrationOverlay: View {
    let origin: CGPoint
    let taskTitle: String
    @State private var showBadge = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ConfettiView(origin: origin)
            badge
                .position(x: origin.x, y: max(40, origin.y - 54))
                .opacity(showBadge ? 1 : 0)
                .scaleEffect(showBadge ? 1 : 0.7)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: showBadge)
        }
        .onAppear {
            showBadge = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                withAnimation(.easeOut(duration: 0.35)) { showBadge = false }
            }
        }
    }

    private var badge: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(taskTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .strikethrough(color: .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(GlassBackground(cornerRadius: 20))
        .frame(maxWidth: 320)
        .allowsHitTesting(false)
    }
}
