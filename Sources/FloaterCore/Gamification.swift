import Foundation
import SwiftData

public struct Badge: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let symbol: String
    public let earned: Bool

    public init(id: String, name: String, detail: String, symbol: String, earned: Bool) {
        self.id = id
        self.name = name
        self.detail = detail
        self.symbol = symbol
        self.earned = earned
    }
}

public enum DailyGoalKind: String, CaseIterable, Identifiable, Sendable {
    case tasks
    case minutes

    public var id: String { rawValue }
    public var title: String { self == .tasks ? "Tasks" : "Minutes" }
}

public struct GameStats: Equatable, Sendable {
    public let totalXP: Int
    public let level: Int
    public let xpIntoLevel: Int
    public let xpNeededForLevel: Int
    public let streakDays: Int
    public let completedToday: Int
    public let focusedTodaySeconds: Double
    public let goalKind: DailyGoalKind
    public let goalTarget: Int
    public let badges: [Badge]

    public var levelProgress: Double {
        xpNeededForLevel <= 0 ? 0 : min(1, Double(xpIntoLevel) / Double(xpNeededForLevel))
    }

    public var goalDone: Int {
        goalKind == .tasks ? completedToday : Int(focusedTodaySeconds / 60)
    }

    public var goalProgress: Double {
        goalTarget <= 0 ? 0 : min(1, Double(goalDone) / Double(goalTarget))
    }

    public var goalMet: Bool { goalDone >= goalTarget }
    public var earnedBadges: [Badge] { badges.filter(\.earned) }
}

/// The rules, as plain functions. Kept free of the store so each one can be
/// checked on its own rather than inferred from a screenshot.
public enum Gamification {
    /// A finished task is worth a base amount plus time actually focused on it.
    public static let baseXP = 10
    public static let xpPerFocusedMinute = 1
    public static let focusedMinutesPerXP = 5

    public static func xp(secondsFocused: Double) -> Int {
        baseXP + max(0, Int(secondsFocused / 60) / focusedMinutesPerXP) * xpPerFocusedMinute
    }

    /// Levels get steadily longer: level 1 needs 100, level 2 needs 150, and so
    /// on, so early progress is quick and later levels mean something.
    public static func xpNeeded(forLevel level: Int) -> Int {
        max(1, 100 + (max(1, level) - 1) * 50)
    }

    public static func level(forTotalXP total: Int) -> (level: Int, into: Int, needed: Int) {
        var level = 1
        var remaining = max(0, total)
        while remaining >= xpNeeded(forLevel: level) {
            remaining -= xpNeeded(forLevel: level)
            level += 1
        }
        return (level, remaining, xpNeeded(forLevel: level))
    }

    /// Consecutive days with at least one task finished, counting back from
    /// today — or from yesterday, so a streak is not declared broken before the
    /// day it would break on.
    public static func streak(completionDates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(completionDates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        var cursor = today
        if !days.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    public struct BadgeInput: Equatable, Sendable {
        public let totalCompleted: Int
        public let longestSessionMinutes: Int
        public let streakDays: Int
        public let bestDayFocusedSeconds: Double
        public let clearedAFullDay: Bool
        public let completedBefore7am: Bool
        public let completedAfterMidnight: Bool

        public init(totalCompleted: Int, longestSessionMinutes: Int, streakDays: Int,
                    bestDayFocusedSeconds: Double, clearedAFullDay: Bool,
                    completedBefore7am: Bool, completedAfterMidnight: Bool) {
            self.totalCompleted = totalCompleted
            self.longestSessionMinutes = longestSessionMinutes
            self.streakDays = streakDays
            self.bestDayFocusedSeconds = bestDayFocusedSeconds
            self.clearedAFullDay = clearedAFullDay
            self.completedBefore7am = completedBefore7am
            self.completedAfterMidnight = completedAfterMidnight
        }
    }

    public static func badges(_ input: BadgeInput) -> [Badge] {
        [
            Badge(id: "first", name: "First Blood", detail: "Finish your first task",
                  symbol: "flag.checkered", earned: input.totalCompleted >= 1),
            Badge(id: "ten", name: "Getting Going", detail: "Finish 10 tasks",
                  symbol: "checkmark.seal", earned: input.totalCompleted >= 10),
            Badge(id: "hundred", name: "Centurion", detail: "Finish 100 tasks",
                  symbol: "rosette", earned: input.totalCompleted >= 100),
            Badge(id: "deep", name: "Deep Work", detail: "Run a full 45 minute session",
                  symbol: "brain.head.profile", earned: input.longestSessionMinutes >= 45),
            Badge(id: "marathon", name: "Marathon", detail: "Focus four hours in one day",
                  symbol: "figure.run", earned: input.bestDayFocusedSeconds >= 4 * 3600),
            Badge(id: "week", name: "On Fire", detail: "Keep a seven day streak",
                  symbol: "flame", earned: input.streakDays >= 7),
            Badge(id: "month", name: "Unstoppable", detail: "Keep a thirty day streak",
                  symbol: "bolt.heart", earned: input.streakDays >= 30),
            Badge(id: "sweep", name: "Clean Sweep", detail: "Finish everything on the list in a day",
                  symbol: "sparkles", earned: input.clearedAFullDay),
            Badge(id: "early", name: "Early Bird", detail: "Finish something before 7am",
                  symbol: "sunrise", earned: input.completedBefore7am),
            Badge(id: "owl", name: "Night Owl", detail: "Finish something after midnight",
                  symbol: "moon.stars", earned: input.completedAfterMidnight),
        ]
    }
}

public extension Store {
    /// Everything the game surfaces, derived from what actually happened.
    @MainActor
    func gameStats(now: Date, calendar: Calendar = .current,
                   goalKind: DailyGoalKind, goalTarget: Int) -> GameStats {
        let finished = tasks.compactMap { task -> (date: Date, seconds: Double)? in
            guard let done = task.completedAt else { return nil }
            return (done, task.secondsSpent)
        }
        let sessions = (try? context.fetch(FetchDescriptor<FocusSessionRecord>())) ?? []

        let totalXP = finished.reduce(0) { $0 + Gamification.xp(secondsFocused: $1.seconds) }
        let progression = Gamification.level(forTotalXP: totalXP)
        let streak = Gamification.streak(completionDates: finished.map(\.date),
                                         now: now, calendar: calendar)

        let today = calendar.startOfDay(for: now)
        let todays = finished.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let focusedToday = sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .reduce(0) { $0 + $1.secondsFocused }

        // Per-day focus, for the "four hours in a day" badge.
        var focusByDay: [Date: Double] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startedAt)
            focusByDay[day, default: 0] += session.secondsFocused
        }

        let openNow = tasks.filter { !$0.isDone }.count
        let input = Gamification.BadgeInput(
            totalCompleted: finished.count,
            longestSessionMinutes: sessions.map(\.plannedMinutes).max() ?? 0,
            streakDays: streak,
            bestDayFocusedSeconds: focusByDay.values.max() ?? 0,
            clearedAFullDay: openNow == 0 && !todays.isEmpty,
            completedBefore7am: finished.contains { calendar.component(.hour, from: $0.date) < 7 },
            completedAfterMidnight: finished.contains {
                let hour = calendar.component(.hour, from: $0.date)
                return hour >= 0 && hour < 4
            }
        )
        _ = today

        return GameStats(
            totalXP: totalXP,
            level: progression.level,
            xpIntoLevel: progression.into,
            xpNeededForLevel: progression.needed,
            streakDays: streak,
            completedToday: todays.count,
            focusedTodaySeconds: focusedToday,
            goalKind: goalKind,
            goalTarget: goalTarget,
            badges: Gamification.badges(input)
        )
    }
}
