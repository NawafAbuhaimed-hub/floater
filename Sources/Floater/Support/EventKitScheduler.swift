import FloaterCore
import EventKit
import Foundation

/// Writes follow-ups into Calendar or Reminders.
///
/// Calendar access is requested in full rather than write-only: listing the
/// user's calendars — so they can send follow-ups to a specific one, e.g. a
/// Google calendar rather than whatever macOS picked as the default — requires
/// read access.
final class EventKitScheduler: FollowUpScheduling {
    private let store = EKEventStore()

    func requestAccess(to destination: FollowUpDestination) async -> Bool {
        if authorized(destination) { return true }
        do {
            switch destination {
            case .calendar: return try await store.requestFullAccessToEvents()
            case .reminders: return try await store.requestFullAccessToReminders()
            }
        } catch {
            return false
        }
    }

    private func authorized(_ destination: FollowUpDestination) -> Bool {
        EKEventStore.authorizationStatus(for: destination == .calendar ? .event : .reminder) == .fullAccess
    }

    func availableTargets(for destination: FollowUpDestination) async -> [FollowUpTarget] {
        // Deliberately not gated on `authorizationStatus`: immediately after the
        // user grants access, the cached status can still read notDetermined in
        // this process, which silently produced an empty calendar list. Asking
        // the store directly returns nothing when access is genuinely missing.
        let entity: EKEntityType = destination == .calendar ? .event : .reminder
        let fallback = destination == .calendar
            ? store.defaultCalendarForNewEvents
            : store.defaultCalendarForNewReminders()
        return store.calendars(for: entity)
            .filter(\.allowsContentModifications)
            .map {
                FollowUpTarget(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceName: $0.source?.title ?? "",
                    isSystemDefault: $0.calendarIdentifier == fallback?.calendarIdentifier
                )
            }
            .sorted { ($0.sourceName, $0.title) < ($1.sourceName, $1.title) }
    }

    func schedule(_ request: ScheduleRequest) async throws -> String {
        switch request.destination {
        case .calendar:
            return try scheduleEvent(request)
        case .reminders:
            return try scheduleReminder(request)
        }
    }

    /// The chosen calendar, falling back to the system default when none is set
    /// or the chosen one has since disappeared.
    private func target(_ request: ScheduleRequest) -> EKCalendar? {
        if let id = request.targetID,
           let match = store.calendar(withIdentifier: id),
           match.allowsContentModifications {
            return match
        }
        return request.destination == .calendar
            ? store.defaultCalendarForNewEvents
            : store.defaultCalendarForNewReminders()
    }

    private func scheduleEvent(_ request: ScheduleRequest) throws -> String {
        guard let calendar = target(request) else {
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

    private func scheduleReminder(_ request: ScheduleRequest) throws -> String {
        guard let list = target(request) else {
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

    /// Removes a previously created event or reminder. An item that is already
    /// gone is not an error — the calendar simply agrees with us.
    func remove(id: String, destination: FollowUpDestination) async throws {
        do {
            switch destination {
            case .calendar:
                guard let event = store.event(withIdentifier: id) else { return }
                try store.remove(event, span: .thisEvent, commit: true)
            case .reminders:
                guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
                try store.remove(reminder, commit: true)
            }
        } catch {
            throw FollowUpError.underlying(error.localizedDescription)
        }
    }
}
