import Foundation
import Combine

// MARK: - Completion Stats Tracker
// Tracks accepted completions, saved keystrokes, and estimated time saved.

@MainActor
final class CompletionStatsTracker: ObservableObject {

    static let shared = CompletionStatsTracker()

    private enum Keys {
        static let totalCompletions = "stats.totalCompletions"
        static let totalCharactersSaved = "stats.totalCharactersSaved"
        static let totalWordsCompleted = "stats.totalWordsCompleted"
        static let todayCompletions = "stats.todayCompletions"
        static let todayCharactersSaved = "stats.todayCharactersSaved"
        static let todayWordsCompleted = "stats.todayWordsCompleted"
        static let lastActiveDay = "stats.lastActiveDay"
    }

    private let defaults: UserDefaults

    @Published private(set) var totalCompletions: Int = 0
    @Published private(set) var totalCharactersSaved: Int = 0
    @Published private(set) var totalWordsCompleted: Int = 0

    @Published private(set) var todayCompletions: Int = 0
    @Published private(set) var todayCharactersSaved: Int = 0
    @Published private(set) var todayWordsCompleted: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadStats()
    }

    private static func todayKey(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func checkDayRollover() {
        let currentDay = Self.todayKey()
        let savedDay = defaults.string(forKey: Keys.lastActiveDay) ?? ""
        if savedDay != currentDay {
            todayCompletions = 0
            todayCharactersSaved = 0
            todayWordsCompleted = 0
            defaults.set(currentDay, forKey: Keys.lastActiveDay)
            defaults.set(0, forKey: Keys.todayCompletions)
            defaults.set(0, forKey: Keys.todayCharactersSaved)
            defaults.set(0, forKey: Keys.todayWordsCompleted)
        }
    }

    func loadStats() {
        totalCompletions = defaults.integer(forKey: Keys.totalCompletions)
        totalCharactersSaved = defaults.integer(forKey: Keys.totalCharactersSaved)
        totalWordsCompleted = defaults.integer(forKey: Keys.totalWordsCompleted)

        let currentDay = Self.todayKey()
        let savedDay = defaults.string(forKey: Keys.lastActiveDay) ?? ""
        if savedDay == currentDay {
            todayCompletions = defaults.integer(forKey: Keys.todayCompletions)
            todayCharactersSaved = defaults.integer(forKey: Keys.todayCharactersSaved)
            todayWordsCompleted = defaults.integer(forKey: Keys.todayWordsCompleted)
        } else {
            todayCompletions = 0
            todayCharactersSaved = 0
            todayWordsCompleted = 0
            defaults.set(currentDay, forKey: Keys.lastActiveDay)
        }
    }

    // MARK: - Recording

    func recordAcceptedCompletion(insertedText: String, typedPrefix: String) {
        checkDayRollover()

        let savedChars = max(1, insertedText.count - typedPrefix.count)
        let words = insertedText
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .count
        let wordsCount = max(1, words)

        totalCompletions += 1
        totalCharactersSaved += savedChars
        totalWordsCompleted += wordsCount

        todayCompletions += 1
        todayCharactersSaved += savedChars
        todayWordsCompleted += wordsCount

        defaults.set(totalCompletions, forKey: Keys.totalCompletions)
        defaults.set(totalCharactersSaved, forKey: Keys.totalCharactersSaved)
        defaults.set(totalWordsCompleted, forKey: Keys.totalWordsCompleted)

        defaults.set(todayCompletions, forKey: Keys.todayCompletions)
        defaults.set(todayCharactersSaved, forKey: Keys.todayCharactersSaved)
        defaults.set(todayWordsCompleted, forKey: Keys.todayWordsCompleted)
        defaults.set(Self.todayKey(), forKey: Keys.lastActiveDay)
    }

    // MARK: - Calculations

    /// Computes estimated time saved in seconds based on standard typing speed of 220 CPM (~3.67 chars/sec).
    static func estimatedTimeSavedSeconds(characters: Int) -> Double {
        guard characters > 0 else { return 0 }
        // 220 chars/min = 3.667 chars/sec
        return Double(characters) / 3.667
    }

    var totalTimeSavedSeconds: Double {
        Self.estimatedTimeSavedSeconds(characters: totalCharactersSaved)
    }

    var todayTimeSavedSeconds: Double {
        Self.estimatedTimeSavedSeconds(characters: todayCharactersSaved)
    }

    /// Formats seconds into human-readable duration (e.g. "18 min", "1h 12m").
    static func formatTime(seconds: Double, l10n: LocalizationManager) -> String {
        let sec = Int(seconds)
        if sec < 60 {
            return "\(sec) " + l10n.t("stats.time.sec")
        }
        let minutes = sec / 60
        if minutes < 60 {
            return "\(minutes) " + l10n.t("stats.time.min")
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if remMin == 0 {
            return "\(hours) " + l10n.t("stats.time.hr")
        }
        return "\(hours) " + l10n.t("stats.time.hr") + " \(remMin) " + l10n.t("stats.time.min")
    }

    func formattedTotalTimeSaved(l10n: LocalizationManager) -> String {
        Self.formatTime(seconds: totalTimeSavedSeconds, l10n: l10n)
    }

    func formattedTodayTimeSaved(l10n: LocalizationManager) -> String {
        Self.formatTime(seconds: todayTimeSavedSeconds, l10n: l10n)
    }

    func resetStats() {
        totalCompletions = 0
        totalCharactersSaved = 0
        totalWordsCompleted = 0
        todayCompletions = 0
        todayCharactersSaved = 0
        todayWordsCompleted = 0
        defaults.removeObject(forKey: Keys.totalCompletions)
        defaults.removeObject(forKey: Keys.totalCharactersSaved)
        defaults.removeObject(forKey: Keys.totalWordsCompleted)
        defaults.removeObject(forKey: Keys.todayCompletions)
        defaults.removeObject(forKey: Keys.todayCharactersSaved)
        defaults.removeObject(forKey: Keys.todayWordsCompleted)
    }
}
