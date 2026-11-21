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

    // MARK: - Privacy Exclusions Tests

    func testPrivacyExclusionsRejectSecureFields() {
        XCTAssertEqual(store.totalSnippetCount, 0)
        
        // Secure password field via role
        store.recordAcceptedSample(
            text: "My secret master password phrase for login",
            bundleID: "com.apple.Safari",
            role: "AXSecureTextField"
        )
        XCTAssertEqual(store.totalSnippetCount, 0, "Must never record in AXSecureTextField role")

        // Secure password field via subrole
        store.recordAcceptedSample(
            text: "My secret master password phrase for login",
            bundleID: "com.google.Chrome",
            role: "AXTextField",
            subrole: "AXSecureTextField"
        )
        XCTAssertEqual(store.totalSnippetCount, 0, "Must never record in AXSecureTextField subrole")
    }

    func testPrivacyExclusionsRejectIncognitoWindowsAcrossAllBrowsers() {
        let incognitoTestCases: [(bundleID: String, windowTitle: String)] = [
            ("com.apple.Safari", "Private Browsing — Search"),
            ("com.apple.Safari", "Частный доступ — Стартовая страница"),
            ("com.google.Chrome", "Google (Incognito)"),
            ("com.google.Chrome", "Новая вкладка (Вкладка инкогнито)"),
            ("org.mozilla.firefox", "Mozilla Firefox — Private Browsing"),
            ("org.mozilla.firefox", "Википедия — Приватный просмотр"),
            ("com.brave.Browser", "New Private Tab - Brave"),
            ("com.brave.Browser", "GitHub (Incognito)"),
            ("com.brave.Browser", "Brave - Private"),
            ("com.vivaldi.Vivaldi", "Vivaldi Private Window"),
            ("com.permacomputing.comet", "Comet Browser - Incognito Session"),
            ("org.comet.comet", "Page Title - Private Window"),
            ("app.zen-browser.zen", "Zen Browser — Private Browsing"),
            ("io.github.zen_browser.zen", "Zen Browser (Private)"),
            ("com.microsoft.edgemac", "Search - InPrivate")
        ]

        for (idx, tc) in incognitoTestCases.enumerated() {
            XCTAssertTrue(
                AutoCorrectionGate.isPrivateOrIncognitoWindow(bundleID: tc.bundleID, windowTitle: tc.windowTitle),
                "AutoCorrectionGate must detect incognito for \(tc.bundleID) with title '\(tc.windowTitle)'"
            )
            store.recordAcceptedSample(
                text: "Пользовательский текст номер \(idx) который никогда не должен быть сохранен",
                bundleID: tc.bundleID,
                windowTitle: tc.windowTitle
            )
            XCTAssertEqual(store.totalSnippetCount, 0, "Must never record in incognito/private window for \(tc.bundleID) with title '\(tc.windowTitle)'")
            store.clearHistory()
        }
    }

    func testRecordAcceptedSampleStoresValidNonPrivateWriting() {
        XCTAssertEqual(store.totalSnippetCount, 0)

        // Normal Safari window
        store.recordAcceptedSample(
            text: "Мы успешно завершили реализацию архитектурного рефакторинга",
            bundleID: "com.apple.Safari",
            windowTitle: "Pull Request #42 — GitHub"
        )
        XCTAssertEqual(store.totalSnippetCount, 1)
        XCTAssertEqual(store.fetchLatestSnippet(for: "com.apple.Safari")?.text, "Мы успешно завершили реализацию архитектурного рефакторинга")

        // Normal Chrome window
        store.recordAcceptedSample(
            text: "Please find attached the latest specification and architecture document",
            bundleID: "com.google.Chrome",
            windowTitle: "Google Docs — Engineering Spec"
        )
        XCTAssertEqual(store.totalSnippetCount, 2)
    }
}
