import FloaterCore
import EventKit
import Foundation

/// Reads today's calendar so the status can tell a packed day from a quiet one.
/// Silent when access has not been granted: an empty day is the safe reading.
final class EventKitCalendarReader: CalendarReading, @unchecked Sendable {
    private let store = EKEventStore()

    func today(now: Date) async -> DayEvents {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return .none
        }
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return .none }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return .none }

        let events = store.events(
            matching: store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        )
        // All-day entries are not meetings and would make every day look packed.
        let meetings = events.filter { !$0.isAllDay }
        let next = meetings
            .compactMap { $0.startDate }
            .filter { $0 > now }
            .min()

        return DayEvents(
            total: meetings.count,
            inMeetingNow: meetings.contains { ($0.startDate ... $0.endDate).contains(now) },
            minutesToNext: next.map { Int($0.timeIntervalSince(now) / 60) }
        )
    }
}
