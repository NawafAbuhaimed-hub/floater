import FloaterCore
import SwiftUI

/// The full-screen takeover when a timer runs out. Deliberately hard to ignore,
/// but every button gets you out in one click.
struct TimeUpView: View {
    let taskTitle: String
    let minutes: Int
    let onDone: () -> Void
    let onExtend: () -> Void
    let onStop: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.25), value: appeared)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 74, height: 74)
                    Image(systemName: "timer")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .scaleEffect(appeared ? 1 : 0.6)
                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: appeared)

                VStack(spacing: 6) {
                    Text("Time's up")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("\(minutes) min on \u{201C}\(taskTitle)\u{201D}")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 380)
                }

                HStack(spacing: 10) {
                    TakeoverButton(title: "Done", symbol: "checkmark", prominent: true, action: onDone)
                    TakeoverButton(title: "+10 min", symbol: "plus", action: onExtend)
                    TakeoverButton(title: "Stop", symbol: "stop.fill", action: onStop)
                }
                .padding(.top, 4)
            }
            .padding(36)
            .background(GlassBackground(cornerRadius: 24))
            .frame(maxWidth: 460)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

struct TakeoverButton: View {
    let title: String
    let symbol: String
    var prominent: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(
                    prominent
                        ? Theme.accent.opacity(hovering ? 1 : 0.88)
                        : Color.primary.opacity(hovering ? 0.18 : 0.1)
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
