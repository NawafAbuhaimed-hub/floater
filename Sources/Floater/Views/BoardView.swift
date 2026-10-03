import FloaterCore
import SwiftUI

/// The pipeline board. Columns are either the four statuses or the user's
/// categories; dragging a card between columns sets whichever the columns
/// represent.
struct BoardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            modeRow
            Divider().opacity(0.4)
            // Both axes are pinned to the available space. Without the explicit
            // maxHeight the columns' intrinsic height drove the enclosing stack
            // taller than the window and pushed the header off the top, leaving
            // no way back out of the board.
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 8) {
                    if model.pipelineByCategory {
                        ForEach(model.categories, id: \.id) { category in
                            column(
                                title: category.label,
                                tint: Theme.color(hex: category.colorHex),
                                tasks: model.tasks(in: category)
                            ) { model.setCategory(category, for: $0) }
                        }
                        column(title: "Uncategorised", tint: .secondary,
                               tasks: model.tasks(in: nil)) { model.setCategory(nil, for: $0) }
                    } else {
                        ForEach(TaskStatus.allCases) { status in
                            column(
                                title: status.title,
                                tint: Theme.color(for: status),
                                tasks: model.tasks(with: status)
                            ) { model.setStatus(status, for: $0) }
                        }
                    }
                }
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var modeRow: some View {
        HStack(spacing: 6) {
            Text("Columns")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Picker("", selection: $model.pipelineByCategory) {
                Text("Status").tag(false)
                Text("Category").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func column(
        title: String,
        tint: Color,
        tasks: [TaskItem],
        onDrop: @escaping (TaskItem) -> Void
    ) -> some View {
        BoardColumn(title: title, tint: tint, tasks: tasks, onDrop: onDrop)
    }
}

private struct BoardColumn: View {
    let title: String
    let tint: Color
    let tasks: [TaskItem]
    let onDrop: (TaskItem) -> Void

    @EnvironmentObject private var model: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)

            // Each column scrolls on its own, so a long column cannot stretch
            // the board.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(tasks, id: \.id) { task in
                        BoardCard(task: task)
                            .draggable(task.id.uuidString)
                    }
                    if tasks.isEmpty {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundStyle(.quaternary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 168)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(targeted ? tint.opacity(0.14) : Color.primary.opacity(0.04))
        )
        .dropDestination(for: String.self) { items, _ in
            // Cards carry their task id as text; anything else is ignored.
            guard let raw = items.first, let id = UUID(uuidString: raw),
                  let task = model.tasks.first(where: { $0.id == id }) else { return false }
            onDrop(task)
            return true
        } isTargeted: { targeted = $0 }
    }
}

private struct BoardCard: View {
    let task: TaskItem
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.title)
                .font(.system(size: 11.5))
                .lineLimit(3)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: task.status.symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.color(for: task.status))
                if let category = model.category(of: task), !model.pipelineByCategory {
                    Text(category.label)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.color(hex: category.colorHex))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                DueChip(task: task, compact: true)
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .contentShape(Rectangle())
        .onTapGesture { model.select(task) }
        .contextMenu {
            ForEach(TaskStatus.allCases) { status in
                Button { model.setStatus(status, for: task) } label: {
                    Label(status.title, systemImage: status.symbol)
                }
                .disabled(task.status == status)
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(task) }
        }
    }
}

/// "Due today", "Fri 12", "2d late" — coloured by how late it is.
struct DueChip: View {
    let task: TaskItem
    var compact: Bool = false
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let due = task.dueDate {
            let state = model.dueState(of: task)
            Text(Self.label(due, state: state, now: Date(), compact: compact))
                .font(.system(size: compact ? 9 : 10, weight: state == .overdue ? .semibold : .regular))
                .foregroundStyle(Theme.color(for: state))
                .lineLimit(1)
        }
    }

    static func label(_ due: Date, state: DueState, now: Date, compact: Bool) -> String {
        let calendar = Calendar.current
        switch state {
        case .today: return compact ? "today" : "Due today"
        case .overdue:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: due),
                                               to: calendar.startOfDay(for: now)).day ?? 0
            return days <= 0 ? "late" : "\(days)d late"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE d"
            return (compact ? "" : "Due ") + formatter.string(from: due)
        }
    }
}
