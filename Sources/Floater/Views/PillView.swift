import FloaterCore
import SwiftUI

/// The collapsed state: a draggable capsule showing what is running and how
/// long is left. Only the buttons take clicks; the rest of the capsule is a
/// drag handle for moving the window.
struct PillView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pulse = false

    private var ringColor: Color {
        Theme.urgency(remaining: model.remaining, active: model.isActive)
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isActive ? model.activeTitle : "Nothing running")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(model.isActive ? .primary : .secondary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if model.isActive {
                if let task = model.activeTask {
                    PillButton(symbol: "checkmark", tint: Theme.accent) {
                        model.complete(task)
                    }
                    .help("Mark done")
                }
                PillButton(symbol: model.phase == .running ? "pause.fill" : "play.fill") {
                    model.togglePause()
                }
                .help(model.phase == .running ? "Pause" : "Resume")
            }
            PillButton(symbol: "chevron.up") {
                model.mode = .expanded
            }
            .help("Open task list")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                GlassBackground(cornerRadius: Theme.pillCorner)
                Capsule()
                    .strokeBorder(ringColor.opacity(pulse ? 0.9 : 0), lineWidth: 3)
                    .animation(.easeInOut(duration: 0.35), value: pulse)
            }
        )
        .scaleEffect(pulse ? 1.04 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: pulse)
        .padding(6)
        .onChange(of: model.attentionPulse) { _, _ in throb() }
    }

    private var leading: some View {
        ZStack {
            ProgressRing(progress: model.progress, color: ringColor)
            if model.isActive {
                Text(model.remainingText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(model.phase == .paused ? .secondary : .primary)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
    }

    private var subtitle: String {
        switch model.phase {
        case .running: return "focusing"
        case .paused: return "paused"
        case .elapsed: return "time's up"
        case .idle:
            if model.overdueCount > 0 {
                return "\(model.overdueCount) overdue"
            }
            let open = model.openTasks.count
            if open == 0 { return "no tasks yet" }
            return "\(open) task\(open == 1 ? "" : "s") waiting"
        }
    }

    private func throb() {
        pulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { pulse = false }
    }
}

/// A compact circular button that reads as part of the capsule.
struct PillButton: View {
    let symbol: String
    var tint: Color = .primary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Color.primary.opacity(hovering ? 0.14 : 0.07))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
