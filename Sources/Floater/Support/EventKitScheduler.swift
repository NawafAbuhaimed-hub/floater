import FloaterCore
import EventKit
import Foundation

/// Writes follow-ups into Calendar or Reminders.
///
/// Calendar access is requested write-only — Floater only ever creates events
/// and never reads your calendar, so that is the least it can ask for.
final class EventKitScheduler: FollowUpScheduling {
    private let store = EKEventStore()

    func requestAccess(to destination: FollowUpDestination) async -> Bool {
        do {
            switch destination {
            case .calendar:
                if #available(macOS 14.0, *) {
                    return try await store.requestWriteOnlyAccessToEvents()
                }
                return try await store.requestAccess(to: .event)
            case .reminders:
                if #available(macOS 14.0, *) {
                    return try await store.requestFullAccessToReminders()
                }
                return try await store.requestAccess(to: .reminder)
            }
        } catch {
            return false
        }
    }

    func schedule(_ request: FollowUpRequest) async throws -> String {
        switch request.destination {
        case .calendar:
            return try scheduleEvent(request)
        case .reminders:
            return try scheduleReminder(request)
        }
    }

    private func scheduleEvent(_ request: FollowUpRequest) throws -> String {
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw FollowUpError.noDefaultList(.calendar)
        }
        let event = EKEvent(eventStore: store)
        event.title = request.title
        event.notes = request.notes
        event.startDate = request.date
        event.endDate = request.date.addingTimeInterval(request.duration)
        event.calendar = calendar
        event.addAlarm(EKAlarm(relativeOffset: 0))
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw FollowUpError.underlying(error.localizedDescription)
        }
        return event.eventIdentifier ?? ""
    }

    private func scheduleReminder(_ request: FollowUpRequest) throws -> String {
        guard let list = store.defaultCalendarForNewReminders() else {
            throw FollowUpError.noDefaultList(.reminders)
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = request.title
        reminder.notes = request.notes
        reminder.calendar = list
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: request.date
        )
        reminder.addAlarm(EKAlarm(absoluteDate: request.date))
        do {
            try store.save(reminder, commit: true)
        } catch {
            throw FollowUpError.underlying(error.localizedDescription)
        }
        return reminder.calendarItemIdentifier
    }
}
