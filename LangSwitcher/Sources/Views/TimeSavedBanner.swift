import SwiftUI

// MARK: - Time Saved Banner
// Displays estimated time saved, keystrokes conserved, and words completed.

struct TimeSavedBanner: View {
    @EnvironmentObject var l10n: LocalizationManager
    @ObservedObject private var stats = CompletionStatsTracker.shared

    @State private var showAllTime: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundStyle(.tint)
                    Text(l10n.t("stats.banner.title"))
                        .font(.subheadline)
                        .bold()
                }

                Spacer()

                Picker("", selection: $showAllTime) {
                    Text(l10n.t("stats.scope.today")).tag(false)
                    Text(l10n.t("stats.scope.allTime")).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            HStack(spacing: 12) {
                // 1. Time Saved
                StatCard(
                    icon: "clock.arrow.circlepath",
                    title: l10n.t("stats.card.timeSaved"),
                    value: showAllTime ? stats.formattedTotalTimeSaved(l10n: l10n) : stats.formattedTodayTimeSaved(l10n: l10n),
                    color: .blue
                )

                // 2. Keystrokes Saved
                StatCard(
                    icon: "keyboard",
                    title: l10n.t("stats.card.keystrokes"),
                    value: formatNumber(showAllTime ? stats.totalCharactersSaved : stats.todayCharactersSaved),
                    color: .green
                )

                // 3. Words Completed
                StatCard(
                    icon: "text.word.spacing",
                    title: l10n.t("stats.card.words"),
                    value: formatNumber(showAllTime ? stats.totalWordsCompleted : stats.todayWordsCompleted),
                    color: .purple
                )
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}
