import FloaterCore
import SwiftUI

/// The expanded panel: add a task, set its status, start a timer on it, take
/// notes. The header doubles as the drag handle.
struct ExpandedView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if model.tab == .tasks {
                composer
                if model.isActive { activeCard }
                Divider().opacity(0.5)
                taskList
                footer
            } else {
                notesPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground(cornerRadius: Theme.corner))
        .overlay(alignment: .bottomTrailing) {
            ResizeGrip().padding(5)
        }
        .padding(6)
        .onAppear { draftFocused = model.tab == .tasks }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accent)
            TabSwitcher(selection: $model.tab)
            Spacer(minLength: 4)
            PillButton(symbol: "chevron.down") { model.mode = .collapsed }
                .help("Collapse")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Tasks

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

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.tasks.isEmpty {
                    emptyState
                }
                ForEach(model.tasks, id: \.id) { task in
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
            Text("Add your first task above.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 10))
                .foregroundStyle(model.completedToday > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
            Text("\(model.completedToday) done today")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if model.doneCount > 0 {
                Button("Clear done") { model.clearCompleted() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .padding(.trailing, 16) // clear of the resize grip
    }

    // MARK: - Notes

    private var notesPane: some View {
        ZStack(alignment: .topLeading) {
            NoteEditor(text: $model.scratchpad)
            if model.scratchpad.isEmpty {
                Text("Anything that isn't a task — links, thoughts, numbers to remember.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .padding(.bottom, 14)
    }
}

/// Tasks | Notes.
struct TabSwitcher: View {
    @Binding var selection: AppModel.Tab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppModel.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.primary.opacity(selection == tab ? 0.12 : 0))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One task: status dot, title, timer chips, and an inline note.
struct TaskRow: View {
    let task: TaskItem
    @EnvironmentObject private var model: AppModel
    @State private var hovering = false

    private var isActive: Bool { task.id == model.activeTaskID }
    private var isNoteOpen: Bool { model.expandedTaskID == task.id }
    private var statusColor: Color { Theme.color(for: task.status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isNoteOpen { noteSection }
        }
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(TaskStatus.allCases) { status in
                Button {
                    model.setStatus(status, for: task)
                } label: {
                    Label(status.title, systemImage: status.symbol)
                }
                .disabled(task.status == status)
            }
            Divider()
            Button(isNoteOpen ? "Hide note" : "Add note") { model.toggleNote(for: task) }
            Button("Delete", role: .destructive) { model.delete(task) }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            Button { model.advanceStatus(task) } label: {
                Image(systemName: task.status.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(statusColor)
                    .frame(width: 17)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Reopen" : "Change status")

            Button { model.toggleNote(for: task) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .strikethrough(task.isDone, color: .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open note")

            trailingControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    /// The status label is always on screen — a task with no timer and no note
    /// still has to show what state it is in.
    private var subtitle: some View {
        HStack(spacing: 4) {
            Text(task.status.title)
                .foregroundStyle(statusColor)
                .fontWeight(.medium)
            if task.secondsSpent > 0 {
                Text("·").foregroundStyle(.quaternary)
                Text(task.secondsSpent.compactDuration + " focused")
                    .foregroundStyle(.tertiary)
            }
            if !task.note.isEmpty {
                Text("·").foregroundStyle(.quaternary)
                Image(systemName: "note.text")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isActive {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        } else if hovering {
            HStack(spacing: 3) {
                if !task.isDone {
                    Button {
                        model.complete(task)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Theme.accent.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Mark done")
                    ForEach(model.timerLengths, id: \.self) { minutes in
                        Button("\(minutes)") { model.start(task, minutes: minutes) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .frame(width: 22, height: 20)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                            .help("Focus for \(minutes) minutes")
                    }
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

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusPicker(current: task.status) { model.setStatus($0, for: task) }
            NoteEditor(
                text: Binding(
                    get: { task.note },
                    set: { model.noteChanged($0, for: task) }
                ),
                minHeight: 68,
                placeholder: "Notes for this task…"
            )
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 11)
    }
}

/// Four colored chips, one per status.
struct StatusPicker: View {
    let current: TaskStatus
    let onSelect: (TaskStatus) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TaskStatus.allCases) { status in
                let selected = status == current
                let color = Theme.color(for: status)
                Button { onSelect(status) } label: {
                    HStack(spacing: 4) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(status.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(color.opacity(selected ? 0.22 : 0.07))
                            .overlay(
                                Capsule().strokeBorder(color.opacity(selected ? 0.7 : 0), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A transparent, borderless text editor with a placeholder.
struct NoteEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 0
    var placeholder: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(minHeight > 0 ? 0.05 : 0))
            TextEditor(text: $text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, minHeight > 0 ? 6 : 12)
                .padding(.vertical, minHeight > 0 ? 4 : 8)
            if text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, minHeight > 0 ? 11 : 17)
                    .padding(.vertical, minHeight > 0 ? 12 : 16)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight > 0 ? minHeight : nil, maxHeight: minHeight > 0 ? minHeight : .infinity)
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
