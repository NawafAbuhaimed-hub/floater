import SwiftUI
import FloaterCore

/// The expanded panel: add a task, start a timer on it, tick it off.
struct ExpandedView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            composer
            if model.isActive { activeCard }
            Divider().opacity(0.5)
            list
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground(cornerRadius: Theme.corner))
        .padding(6)
        .onAppear { draftFocused = true }
    }

    // MARK: - Header (also the drag handle)

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("Floater")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            PillButton(symbol: "chevron.down") { model.mode = .collapsed }
                .help("Collapse")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tertiary)
            TextField("What are you working on?", text: $model.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($draftFocused)
                .onSubmit { model.addDraftTask() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Active run

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.activeTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(model.remainingText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.urgency(remaining: model.remaining, active: true))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Theme.urgency(remaining: model.remaining, active: true))
                        .frame(width: geo.size.width * min(1, max(0, model.progress)))
                        .animation(.easeInOut(duration: 0.3), value: model.progress)
                }
            }
            .frame(height: 5)
            HStack(spacing: 6) {
                SmallButton(model.phase == .running ? "Pause" : "Resume") { model.togglePause() }
                SmallButton("+10 min") { model.extend(minutes: 10) }
                SmallButton("Stop") { model.stopTimer() }
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }

    // MARK: - Task list

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.openTasks.isEmpty {
                    emptyState
                }
                ForEach(model.openTasks, id: \.id) { task in
                    TaskRow(task: task)
                    Divider().opacity(0.25).padding(.leading, 40)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(model.completedToday > 0 ? "All clear. Nice." : "Add your first task above.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundStyle(model.completedToday > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            Text("\(model.completedToday) done today")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if model.completedToday > 0 {
                Button("Clear") { model.clearCompleted() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// One open task: tick it off, or start a 15/30/45 timer on it.
struct TaskRow: View {
    let task: TaskItem
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    private var isActive: Bool { task.id == model.activeTaskID }

    var body: some View {
        HStack(spacing: 10) {
            Button { model.complete(task) } label: {
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(hovering ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .help("Mark done")

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                if task.secondsSpent > 0 {
                    Text(task.secondsSpent.compactDuration + " focused")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)

            if isActive {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            } else if hovering {
                HStack(spacing: 3) {
                    ForEach(model.timerLengths, id: \.self) { minutes in
                        Button("\(minutes)") { model.start(task, minutes: minutes) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .frame(width: 22, height: 20)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                            .help("Focus for \(minutes) minutes")
                    }
                    Button {
                        model.delete(task)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 18, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct SmallButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(hovering ? 0.16 : 0.09)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            if model.mode == .collapsed {
                PillView()
            } else {
                ExpandedView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
