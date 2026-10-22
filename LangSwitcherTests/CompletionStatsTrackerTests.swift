import XCTest
@testable import LangSwitcher

@MainActor
final class CompletionStatsTrackerTests: XCTestCase {

    func testRecordAcceptedCompletion() {
        let suiteName = "test.completion.stats.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let tracker = CompletionStatsTracker(defaults: testDefaults)

        XCTAssertEqual(tracker.totalCompletions, 0)
        XCTAssertEqual(tracker.totalCharactersSaved, 0)
        XCTAssertEqual(tracker.totalWordsCompleted, 0)

        tracker.recordAcceptedCompletion(insertedText: "Hello, world! How are you?", typedPrefix: "Hel")

        XCTAssertEqual(tracker.totalCompletions, 1)
        XCTAssertEqual(tracker.todayCompletions, 1)
        // "Hello, world! How are you?".count (26) - "Hel".count (3) = 23 saved characters
        XCTAssertEqual(tracker.totalCharactersSaved, 23)
        XCTAssertEqual(tracker.todayCharactersSaved, 23)
        XCTAssertEqual(tracker.totalWordsCompleted, 5)
        XCTAssertEqual(tracker.todayWordsCompleted, 5)
    }

    func testEstimatedTimeCalculation() {
        // 220 chars at 220 CPM = 60 seconds
        let seconds = CompletionStatsTracker.estimatedTimeSavedSeconds(characters: 220)
        XCTAssertEqual(seconds, 60.0, accuracy: 0.1)

        XCTAssertEqual(CompletionStatsTracker.estimatedTimeSavedSeconds(characters: 0), 0.0)
    }

    func testFormattedTimeStrings() {
        let l10n = LocalizationManager.shared

        let secText = CompletionStatsTracker.formatTime(seconds: 45, l10n: l10n)
        XCTAssertTrue(secText.contains("45"))

        let minText = CompletionStatsTracker.formatTime(seconds: 180, l10n: l10n)
        XCTAssertTrue(minText.contains("3"))

        let hrText = CompletionStatsTracker.formatTime(seconds: 3600 + 720, l10n: l10n)
        XCTAssertTrue(hrText.contains("1"))
        XCTAssertTrue(hrText.contains("12"))
    }

    func testResetStats() {
        let suiteName = "test.completion.reset.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let tracker = CompletionStatsTracker(defaults: testDefaults)
        tracker.recordAcceptedCompletion(insertedText: "Testing completion", typedPrefix: "Test")

        XCTAssertGreaterThan(tracker.totalCompletions, 0)
        tracker.resetStats()

        XCTAssertEqual(tracker.totalCompletions, 0)
        XCTAssertEqual(tracker.totalCharactersSaved, 0)
        XCTAssertEqual(tracker.totalWordsCompleted, 0)
        XCTAssertEqual(tracker.todayCompletions, 0)
    }
}
