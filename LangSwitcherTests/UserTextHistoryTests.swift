import XCTest
@testable import LangSwitcher

@MainActor
final class UserTextHistoryTests: XCTestCase {
    
    private var tempDBPath: String!
    private var store: UserTextHistoryStore!
    
    override func setUp() {
        super.setUp()
        tempDBPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_uth_\(UUID().uuidString).sqlite").path
        store = UserTextHistoryStore(databasePath: tempDBPath)
    }
    
    override func tearDown() {
        if let path = tempDBPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }
    
    // MARK: - Sanitizer Tests
    
    func testSanitizationRejectsTooShortText() {
        XCTAssertNil(UserTextHistoryStore.sanitize(text: "short"))
        XCTAssertNil(UserTextHistoryStore.sanitize(text: "two words"))
        XCTAssertNil(UserTextHistoryStore.sanitize(text: "   1 2 3   "))
    }
    
    func testSanitizationDropsCreditCards() {
        let textWithCard = "Мой номер карты 4111 2222 3333 4444 для оплаты счета"
        XCTAssertNil(UserTextHistoryStore.sanitize(text: textWithCard))
    }
    
    func testSanitizationDropsSecretTokens() {
        let jwt = "eyJhGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0"
        let textWithToken = "Here is the auth token \(jwt) for testing"
        XCTAssertNil(UserTextHistoryStore.sanitize(text: textWithToken))
        
        let githubToken = "ghp_123456789012345678901234567890123456"
        XCTAssertNil(UserTextHistoryStore.sanitize(text: "Use token \(githubToken) to access"))
    }
    
    func testSanitizationRedactsEmailAddresses() {
        let textWithEmail = "Пожалуйста отправьте отчет на alexey@example.com до конца дня"
        let sanitized = UserTextHistoryStore.sanitize(text: textWithEmail)
        XCTAssertNotNil(sanitized)
        XCTAssertFalse(sanitized!.contains("alexey@example.com"))
        XCTAssertTrue(sanitized!.contains("[email]"))
        XCTAssertTrue(sanitized!.contains("отправьте отчет"))
    }
    
    func testSanitizationAllowsNormalWriting() {
        let naturalTextRu = "Привет, мы сегодня закончили разработку новой функции для проекта"
        XCTAssertEqual(UserTextHistoryStore.sanitize(text: naturalTextRu), naturalTextRu)
        
        let naturalTextEn = "Please let me know once the pull request has been reviewed"
        XCTAssertEqual(UserTextHistoryStore.sanitize(text: naturalTextEn), naturalTextEn)
    }
    
    // MARK: - Store Operations Tests
    
    func testStoreInsertsAndFetchesSnippets() {
        XCTAssertEqual(store.totalSnippetCount, 0)
        
        store.recordSnippet(
            text: "Сегодня мы обсуждаем архитектурные изменения",
            bundleID: "com.apple.dt.Xcode"
        )
        
        XCTAssertEqual(store.totalSnippetCount, 1)
        let snippets = store.fetchSnippets(for: "com.apple.dt.Xcode")
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets.first?.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(snippets.first?.text, "Сегодня мы обсуждаем архитектурные изменения")
        XCTAssertEqual(snippets.first?.language, "ru")
    }
    
    func testStoreDeduplicatesAndExtendsSnippets() {
        store.recordSnippet(
            text: "Мы продолжаем разработку этой функции",
            bundleID: "com.slack.Slack"
        )
        XCTAssertEqual(store.totalSnippetCount, 1)
        
        // Exact duplicate is ignored
        store.recordSnippet(
            text: "Мы продолжаем разработку этой функции",
            bundleID: "com.slack.Slack"
        )
        XCTAssertEqual(store.totalSnippetCount, 1)
        
        // Extension of prefix updates snippet without creating duplicate row
        store.recordSnippet(
            text: "Мы продолжаем разработку этой функции прямо сейчас",
            bundleID: "com.slack.Slack"
        )
        XCTAssertEqual(store.totalSnippetCount, 1)
        let latest = store.fetchLatestSnippet(for: "com.slack.Slack")
        XCTAssertEqual(latest?.text, "Мы продолжаем разработку этой функции прямо сейчас")
    }
    
    func testStoreGeneratesStylePrompt() {
        store.recordSnippet(
            text: "Релиз запланирован на следующую неделю",
            bundleID: "ru.keepcoder.Telegram"
        )
        store.recordSnippet(
            text: "Проверьте пожалуйста мерж реквест в репозитории",
            bundleID: "ru.keepcoder.Telegram"
        )
        
        let prompt = store.stylePrompt(for: "ru.keepcoder.Telegram", limit: 2)
        XCTAssertNotNil(prompt)
        XCTAssertTrue(prompt!.contains("User's personal writing style examples:"))
        XCTAssertTrue(prompt!.contains("Релиз запланирован"))
        XCTAssertTrue(prompt!.contains("Проверьте пожалуйста"))
    }
    
    func testStoreClearsHistory() {
        store.recordSnippet(text: "Первая тестовая запись для проверки очистки", bundleID: "test.app")
        XCTAssertEqual(store.totalSnippetCount, 1)
        
        store.clearHistory()
        XCTAssertEqual(store.totalSnippetCount, 0)
        XCTAssertTrue(store.fetchSnippets().isEmpty)
    }
    
    func testSettingsManagerIncludesStylePromptWhenEnabled() {
        let settings = SettingsManager.shared
        let original = settings.aiPersonalizationEnabled
        defer {
            settings.aiPersonalizationEnabled = original
            UserTextHistoryStore.shared.clearHistory()
        }
        
        settings.aiPersonalizationEnabled = true
        // Store a snippet in the shared instance
        UserTextHistoryStore.shared.recordSnippet(
            text: "Мы обязательно протестируем все сценарии перед выкаткой",
            bundleID: "test.integration.app"
        )
        
        let instructions = settings.aiInstructions(for: "test.integration.app")
        XCTAssertTrue(instructions.contains("User's personal writing style examples:"))
        XCTAssertTrue(instructions.contains("Мы обязательно протестируем"))
        
        // Disabled personalization excludes style prompt
        settings.aiPersonalizationEnabled = false
        let instructionsDisabled = settings.aiInstructions(for: "test.integration.app")
        XCTAssertFalse(instructionsDisabled.contains("User's personal writing style examples:"))
    }
    
    func testStoreGeneratesLanguageFilteredStylePrompt() {
        store.recordSnippet(
            text: "Это пример исключительно на русском языке",
            bundleID: "test.multilang.app"
        )
        store.recordSnippet(
            text: "This is an example written strictly in English language",
            bundleID: "test.multilang.app"
        )
        
        let ruPrompt = store.stylePrompt(for: "test.multilang.app", language: "ru")
        XCTAssertNotNil(ruPrompt)
        XCTAssertTrue(ruPrompt!.contains("исключительно на русском"))
        XCTAssertFalse(ruPrompt!.contains("strictly in English"))
        
        let enPrompt = store.stylePrompt(for: "test.multilang.app", language: "en")
        XCTAssertNotNil(enPrompt)
        XCTAssertTrue(enPrompt!.contains("strictly in English"))
        XCTAssertFalse(enPrompt!.contains("исключительно на русском"))
    }
    
    func testAutocompletionAdaptiveStoreBatchSentenceLearning() {
        let store = AutocompletionAdaptiveStore.shared
        let words = ["continuous", "integration", "pipeline", "execution"]
        store.recordSentenceWords(words)
        
        XCTAssertGreaterThan(store.frequencyScore(for: "integration"), 0)
        XCTAssertGreaterThan(store.bigramBonus(for: "integration", after: "continuous"), 0)
    }
}
