import FloaterCore
import SwiftUI

/// Level, streak and the day's goal, in one compact row above the task list.
struct ProgressStrip: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingBadges = false

    var body: some View {
        if let stats = model.stats {
            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    level(stats)
                    streak(stats)
                    Spacer(minLength: 0)
                    goalRing(stats)
                    Button { showingBadges.toggle() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "rosette").font(.system(size: 10))
                            Text("\(stats.earnedBadges.count)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Badges")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)

                if showingBadges { badgeShelf(stats) }
            }
            .background(Color.primary.opacity(0.03))
        }
    }

    private func level(_ stats: GameStats) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("Lv \(stats.level)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text("\(stats.xpIntoLevel)/\(stats.xpNeededForLevel) XP")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * stats.levelProgress)
                        .animation(.easeOut(duration: 0.4), value: stats.levelProgress)
                }
            }
            .frame(width: 92, height: 4)
        }
    }

    @ViewBuilder
    private func streak(_ stats: GameStats) -> some View {
        if stats.streakDays > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.streak)
                Text("\(stats.streakDays)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .help("\(stats.streakDays) day streak")
        }
    }

    private func goalRing(_ stats: GameStats) -> some View {
        Menu {
            Picker("Goal", selection: $model.goalKind) {
                ForEach(DailyGoalKind.allCases) { Text($0.title).tag($0) }
            }
            Divider()
            ForEach(targets(for: model.goalKind), id: \.self) { value in
                Button("\(value) \(model.goalKind == .tasks ? "tasks" : "minutes")") {
                    model.goalTarget = value
                }
            }
        } label: {
            ZStack {
                ProgressRing(progress: stats.goalProgress,
                             color: stats.goalMet ? Theme.accent : Theme.color(for: .today),
                             lineWidth: 3)
                if stats.goalMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("\(stats.goalDone)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
            }
            .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Daily goal: \(stats.goalDone) of \(stats.goalTarget)")
    }

    private func targets(for kind: DailyGoalKind) -> [Int] {
        kind == .tasks ? [3, 5, 8, 12] : [60, 120, 180, 240]
    }

    private func badgeShelf(_ stats: GameStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(stats.badges) { badge in
                    VStack(spacing: 2) {
                        Image(systemName: badge.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(badge.earned ? AnyShapeStyle(Theme.streak) : AnyShapeStyle(.quaternary))
                        Text(badge.name)
                            .font(.system(size: 8))
                            .foregroundStyle(badge.earned ? .secondary : .quaternary)
                            .lineLimit(1)
                    }
                    .frame(width: 58)
                    .help(badge.earned ? badge.name : "Locked — \(badge.detail)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
