import FloaterCore
import AppKit
import SwiftUI

/// The small card that appears beside the pill after a task is finished.
struct FollowUpPromptView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false
    @State private var customDate = Date().addingTimeInterval(3600)

    private var pending: AppModel.PendingFollowUp? { model.pendingFollowUp }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            destinationPicker
            if showingPicker {
                customPicker
            } else {
                presets
            }
            if let error = model.followUpError {
                errorRow(error.message, permission: error.isPermissionProblem)
            }
            if let logError = model.completionLogError {
                errorRow("Calendar log: " + logError, permission: false)
            }
        }
        .padding(13)
        .background(GlassBackground(cornerRadius: 14))
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("Follow up?")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(pending?.taskTitle ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button { model.dismissFollowUp() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Not now")
        }
    }

    private var destinationPicker: some View {
        HStack(spacing: 3) {
            ForEach(FollowUpDestination.allCases) { destination in
                let selected = model.followUpDestination == destination
                Button { model.followUpDestination = destination } label: {
                    HStack(spacing: 4) {
                        Image(systemName: destination.symbol)
                            .font(.system(size: 9, weight: .semibold))
                        Text(destination.title)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(selected ? 0.14 : 0.05)))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var presets: some View {
        HStack(spacing: 4) {
            ForEach(Array(FollowUpOffset.presets.enumerated()), id: \.offset) { _, offset in
                Button {
                    Task { await model.scheduleFollowUp(offset) }
                } label: {
                    VStack(spacing: 0) {
                        Text(offset.title)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(shortDate(model.previewDate(for: offset)))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(model.isSchedulingFollowUp)
            }
            Button {
                customDate = model.previewDate(for: .tomorrow)
                showingPicker = true
                model.pinFollowUpPrompt()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Pick a date and time")
            Spacer(minLength: 0)
        }
    }

    private var customPicker: some View {
        HStack(spacing: 6) {
            DatePicker("", selection: $customDate)
                .datePickerStyle(.compact)
                .labelsHidden()
                .scaleEffect(0.9, anchor: .leading)
                .frame(width: 168)
            Button("Add") {
                Task { await model.scheduleFollowUp(.exact(customDate)) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.accent.opacity(0.2)))
            .disabled(model.isSchedulingFollowUp)
            Spacer(minLength: 0)
        }
    }

    private func errorRow(_ message: String, permission: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.color(for: .blocked))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if permission {
                Button("Open Settings") { openPrivacySettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d, HH:mm"
        return formatter.string(from: date)
    }

    private func openPrivacySettings() {
        let pane = model.followUpDestination == .calendar ? "Calendars" : "Reminders"
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)")
        if let url { NSWorkspace.shared.open(url) }
    }
}
