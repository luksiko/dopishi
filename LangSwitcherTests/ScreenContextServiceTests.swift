import XCTest
@testable import LangSwitcher

@MainActor
final class ScreenContextServiceTests: XCTestCase {
    
    // MARK: - Role Filtering Tests
    
    func testIgnoredRoles() {
        XCTAssertTrue(ScreenContextService.isIgnoredRole("AXButton"))
        XCTAssertTrue(ScreenContextService.isIgnoredRole("AXScrollBar"))
        XCTAssertTrue(ScreenContextService.isIgnoredRole("AXSlider"))
        XCTAssertTrue(ScreenContextService.isIgnoredRole("AXToolbar"))
        XCTAssertTrue(ScreenContextService.isIgnoredRole("AXMenu"))
        
        XCTAssertFalse(ScreenContextService.isIgnoredRole("AXStaticText"))
        XCTAssertFalse(ScreenContextService.isIgnoredRole("AXTextArea"))
        XCTAssertFalse(ScreenContextService.isIgnoredRole("AXTextField"))
        XCTAssertFalse(ScreenContextService.isIgnoredRole("AXGroup"))
    }
    
    // MARK: - UI Noise & Timestamp Tests
    
    func testUINoiseText() {
        XCTAssertTrue(ScreenContextService.isUINoiseText("Send"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("send"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("Attach"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("Отправить"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("Закрыть"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("  ok  "))
        XCTAssertTrue(ScreenContextService.isUINoiseText("42"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("!"))
        XCTAssertTrue(ScreenContextService.isUINoiseText("..."))
        
        XCTAssertFalse(ScreenContextService.isUINoiseText("Привет, во сколько сегодня встреча?"))
        XCTAssertFalse(ScreenContextService.isUINoiseText("Can we reschedule the sync to 3 PM?"))
    }
    
    func testTimestampAndDateFiltering() {
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("14:25"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("9:05 AM"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("23:59:59"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("Today"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("yesterday"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("Сегодня"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("Вчера"))
        XCTAssertTrue(ScreenContextService.isTimestampOrDate("just now"))
        
        XCTAssertFalse(ScreenContextService.isTimestampOrDate("Встретимся в 14:00 возле офиса"))
        XCTAssertFalse(ScreenContextService.isTimestampOrDate("Today is a good day to deploy"))
    }
    
    // MARK: - Privacy & Sanitization Tests
    
    func testPrivacySanitization() {
        // Drop credit cards
        XCTAssertNil(ScreenContextService.sanitizeMessage("Here is my card 4111 2222 3333 4444 thanks"))
        
        // Drop secret tokens
        XCTAssertNil(ScreenContextService.sanitizeMessage("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.token"))
        XCTAssertNil(ScreenContextService.sanitizeMessage("My key is sk-1234567890abcdef1234567890"))
        XCTAssertNil(ScreenContextService.sanitizeMessage("ghp_1234567890abcdef1234567890abcdef"))
        
        // Drop password lines
        XCTAssertNil(ScreenContextService.sanitizeMessage("password: secretPassword123"))
        XCTAssertNil(ScreenContextService.sanitizeMessage("пароль: 12345678"))
        XCTAssertNil(ScreenContextService.sanitizeMessage("pin: 1234"))
        XCTAssertNil(ScreenContextService.sanitizeMessage("cvv: 789"))
        XCTAssertNil(ScreenContextService.sanitizeMessage("secret: mySecretToken"))
        
        // Redact email
        let emailText = ScreenContextService.sanitizeMessage("Please send document to alex@example.com before EOD")
        XCTAssertNotNil(emailText)
        XCTAssertTrue(emailText!.contains("[email]"))
        XCTAssertFalse(emailText!.contains("alex@example.com"))
        
        // Redact phone number
        let phoneText = ScreenContextService.sanitizeMessage("Call me at +1 234 567 8901 tomorrow")
        XCTAssertNotNil(phoneText)
        XCTAssertTrue(phoneText!.contains("[phone]"))
        XCTAssertFalse(phoneText!.contains("234 567 8901"))
        
        // Plain text passes intact
        let plain = ScreenContextService.sanitizeMessage("Привет, готовимся к релизу?")
        XCTAssertEqual(plain, "Привет, готовимся к релизу?")
    }
    
    // MARK: - Filter & Format Tests
    
    func testFilterAndFormat() {
        let items: [(text: String, y: CGFloat, x: CGFloat)] = [
            (text: "Третье сообщение", y: 300, x: 100),
            (text: "Первое сообщение", y: 100, x: 100),
            (text: "Второе сообщение", y: 200, x: 100),
            (text: "Второе сообщение", y: 205, x: 100) // Duplicate
        ]
        
        let result = ScreenContextService.filterAndFormat(
            items: items,
            windowTitle: "Work Chat",
            appBundleID: "com.apple.Notes",
            appName: "Notes",
            maxCharacters: 500,
            maxMessages: 5
        )
        
        XCTAssertNotNil(result)
        guard let res = result else { return }
        
        XCTAssertEqual(res.appBundleID, "com.apple.Notes")
        XCTAssertEqual(res.windowTitle, "Work Chat")
        XCTAssertEqual(res.messages, [
            "Первое сообщение",
            "Второе сообщение",
            "Третье сообщение"
        ])
        
        XCTAssertTrue(res.formattedContext.contains("[Context from active window (Work Chat)]:"))
        XCTAssertTrue(res.formattedContext.contains("- Первое сообщение"))
        XCTAssertTrue(res.formattedContext.contains("- Второе сообщение"))
        XCTAssertTrue(res.formattedContext.contains("- Третье сообщение"))
    }
    
    func testMessagePruningWithoutHeaderTruncation() {
        let items: [(text: String, y: CGFloat, x: CGFloat)] = [
            (text: "Очень длинное первое сообщение для проверки переполнения лимита символов", y: 100, x: 100),
            (text: "Короткое сообщение 2", y: 200, x: 100),
            (text: "Свежее сообщение 3", y: 300, x: 100)
        ]
        
        // Strict character limit that requires dropping the first message
        let result = ScreenContextService.filterAndFormat(
            items: items,
            windowTitle: "Chat",
            appBundleID: "com.apple.Notes",
            appName: "Notes",
            maxCharacters: 100,
            maxMessages: 5
        )
        
        XCTAssertNotNil(result)
        guard let res = result else { return }
        
        // Header must remain intact
        XCTAssertTrue(res.formattedContext.hasPrefix("[Context from active window (Chat)]:"))
        // First long message should be dropped
        XCTAssertFalse(res.messages.contains("Очень длинное первое сообщение для проверки переполнения лимита символов"))
        // Recent messages retained
        XCTAssertTrue(res.messages.contains("Свежее сообщение 3"))
        XCTAssertLessThanOrEqual(res.formattedContext.count, 100)
    }
    
    // MARK: - Excluded Apps Security Guard
    
    func testExcludedAppsSecurity() {
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("com.apple.Terminal"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("com.googlecode.iterm2"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("com.mitchellh.ghostty"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("dev.warp.Warp-Main"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("com.1password.1password"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("com.bitwarden.desktop"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("org.keepassxc.keepassxc"))
        XCTAssertTrue(AutoCorrectionGate.defaultExcludedBundleIDs.contains("com.apple.keychainaccess"))
    }
    
    // MARK: - Prompt Formatting With Screen Context
    
    func testCompletionMessagesWithScreenContext() {
        let messages = AIInferenceEngine.completionMessages(
            context: "Да, во сколько",
            afterCaret: "",
            instructions: "Be brief",
            screenContext: "[Context from active window (Alexey)]: \n- Привет, сможешь сегодня созвониться?"
        )
        
        XCTAssertEqual(messages.count, 2)
        let systemPrompt = messages[0]["content"] ?? ""
        XCTAssertTrue(systemPrompt.contains("[Context from active window (Alexey)]:"))
        XCTAssertTrue(systemPrompt.contains("- Привет, сможешь сегодня созвониться?"))
        XCTAssertTrue(systemPrompt.contains("Be brief"))
        
        let userPrompt = messages[1]["content"] ?? ""
        XCTAssertEqual(userPrompt, "Да, во сколько")
    }
    
    // MARK: - Speaker Attribution Tests
    
    func testDetectSpeaker() {
        let colMin: CGFloat = 100
        let colMax: CGFloat = 600 // col width = 500, midX = 350
        
        // Left bubble (incoming): x = 120, width = 150 -> midX = 195 (< 350)
        let leftBubble = CGRect(x: 120, y: 100, width: 150, height: 40)
        XCTAssertEqual(ScreenContextService.detectSpeaker(elementFrame: leftBubble, columnMinX: colMin, columnMaxX: colMax), .incoming)
        
        // Right bubble (outgoing): x = 400, width = 180 -> midX = 490 (> 350)
        let rightBubble = CGRect(x: 400, y: 150, width: 180, height: 40)
        XCTAssertEqual(ScreenContextService.detectSpeaker(elementFrame: rightBubble, columnMinX: colMin, columnMaxX: colMax), .outgoing)
        
        // Wide notice / document line: width = 450 (> 80% of 500)
        let wideBubble = CGRect(x: 110, y: 200, width: 450, height: 40)
        XCTAssertEqual(ScreenContextService.detectSpeaker(elementFrame: wideBubble, columnMinX: colMin, columnMaxX: colMax), .neutral)
        
        // Nil frame
        XCTAssertEqual(ScreenContextService.detectSpeaker(elementFrame: nil, columnMinX: colMin, columnMaxX: colMax), .neutral)
    }
    
    func testSpeakerAttributedFormatting() {
        let items: [(text: String, y: CGFloat, x: CGFloat, speaker: ScreenContextService.Speaker)] = [
            (text: "Привет, во сколько сегодня созваниваемся?", y: 100, x: 120, speaker: .incoming),
            (text: "Освобожусь к 16:00", y: 200, x: 400, speaker: .outgoing),
            (text: "Отлично, скинешь ссылку на звонок?", y: 300, x: 120, speaker: .incoming)
        ]
        
        let result = ScreenContextService.filterAndFormat(
            attributedItems: items,
            windowTitle: "Dmitry",
            appBundleID: "ru.keepcoder.Telegram",
            appName: "Telegram",
            maxCharacters: 500,
            maxMessages: 5
        )
        
        XCTAssertNotNil(result)
        guard let res = result else { return }
        
        XCTAssertTrue(res.formattedContext.contains("Partner: Привет, во сколько сегодня созваниваемся?"))
        XCTAssertTrue(res.formattedContext.contains("You: Освобожусь к 16:00"))
        XCTAssertTrue(res.formattedContext.contains("Partner: Отлично, скинешь ссылку на звонок?"))
    }
    
    // MARK: - Cache Invalidation
    
    func testCacheInvalidate() {
        ScreenContextService.shared.invalidateCache()
        // Calling invalidate on empty or initialized cache should succeed cleanly
        ScreenContextService.shared.invalidateCache()
    }
    
    // MARK: - Web Browser Detection
    
    func testBrowserAppDetection() {
        XCTAssertTrue(ScreenContextService.isBrowserApp(bundleID: "com.apple.Safari"))
        XCTAssertTrue(ScreenContextService.isBrowserApp(bundleID: "com.google.Chrome"))
        XCTAssertTrue(ScreenContextService.isBrowserApp(bundleID: "com.operasoftware.Opera"))
        XCTAssertTrue(ScreenContextService.isBrowserApp(bundleID: "company.thebrowser.Browser"))
        XCTAssertTrue(ScreenContextService.isBrowserApp(bundleID: "com.brave.Browser"))
        
        XCTAssertFalse(ScreenContextService.isBrowserApp(bundleID: "ru.keepcoder.Telegram"))
        XCTAssertFalse(ScreenContextService.isBrowserApp(bundleID: "com.apple.MobileSMS"))
        XCTAssertFalse(ScreenContextService.isBrowserApp(bundleID: "com.apple.Notes"))
    }

    // MARK: - Chat App Detection

    func testChatAppDetection() {
        XCTAssertTrue(ScreenContextService.isChatApp(bundleID: "ru.keepcoder.Telegram"))
        XCTAssertTrue(ScreenContextService.isChatApp(bundleID: "org.telegram.desktop"))
        XCTAssertTrue(ScreenContextService.isChatApp(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertTrue(ScreenContextService.isChatApp(bundleID: "com.hnc.Discord"))
        XCTAssertTrue(ScreenContextService.isChatApp(bundleID: "net.whatsapp.WhatsApp"))
        XCTAssertTrue(ScreenContextService.isChatApp(bundleID: "com.apple.MobileSMS"))

        XCTAssertFalse(ScreenContextService.isChatApp(bundleID: "com.apple.Safari"))
        XCTAssertFalse(ScreenContextService.isChatApp(bundleID: "com.apple.finder"))
        XCTAssertFalse(ScreenContextService.isChatApp(bundleID: "com.sublimetext.4"))
    }

    func testChatDialogueHeader() {
        let items: [(text: String, y: CGFloat, x: CGFloat)] = [
            (text: "Привет!", y: 100, x: 200)
        ]
        let result = ScreenContextService.filterAndFormat(
            items: items,
            windowTitle: "Alex",
            appBundleID: "ru.keepcoder.Telegram",
            appName: "Telegram"
        )
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.formattedContext.contains("[Context from active dialogue (Alex)]:"))
    }
    
    // MARK: - Question Conditioning Tests
    
    func testDetectPendingQuestion() {
        // 1. Partner asked a question -> true
        let messagesWithQuestion: [(text: String, speaker: ScreenContextService.Speaker)] = [
            ("Привет!", .incoming),
            ("Ты уже в офисе?", .incoming)
        ]
        XCTAssertTrue(ScreenContextService.detectPendingQuestion(messages: messagesWithQuestion))
        
        // 1b. Question with trailing smileys, brackets or quotes -> true
        XCTAssertTrue(ScreenContextService.detectPendingQuestion(messages: [("Ты где?))", .incoming)]))
        XCTAssertTrue(ScreenContextService.detectPendingQuestion(messages: [("Во сколько созвонимся? :)", .incoming)]))
        XCTAssertTrue(ScreenContextService.detectPendingQuestion(messages: [("«Ты уже в офисе?»", .incoming)]))
        
        // 2. Partner asked question, but user already replied -> false
        let messagesAlreadyAnswered: [(text: String, speaker: ScreenContextService.Speaker)] = [
            ("Ты уже в офисе?", .incoming),
            ("Да, на месте", .outgoing)
        ]
        XCTAssertFalse(ScreenContextService.detectPendingQuestion(messages: messagesAlreadyAnswered))
        
        // 3. Partner message without question mark -> false
        let messagesStatement: [(text: String, speaker: ScreenContextService.Speaker)] = [
            ("Привет, отправил тебе документы.", .incoming)
        ]
        XCTAssertFalse(ScreenContextService.detectPendingQuestion(messages: messagesStatement))
        
        // 4. Empty list -> false
        XCTAssertFalse(ScreenContextService.detectPendingQuestion(messages: []))
    }
    
    func testCompletionMessagesWithQuestionConditioning() {
        // Russian question conditioning
        let ruMessages = AIInferenceEngine.completionMessages(
            context: "Давай в ",
            afterCaret: "",
            instructions: nil,
            screenContext: "[Context from active window (Dmitry)]:\nPartner: Во сколько созвонимся?",
            hasPendingQuestion: true
        )
        let ruSystem = ruMessages[0]["content"] ?? ""
        XCTAssertTrue(ruSystem.contains("Собеседник задал вопрос. Кратко и естественно ответь на него от первого лица в 2-4 слова."))
        
        // English question conditioning
        let enMessages = AIInferenceEngine.completionMessages(
            context: "I will be ",
            afterCaret: "",
            instructions: nil,
            screenContext: "[Context from active window (Alex)]:\nPartner: Where are you?",
            hasPendingQuestion: true
        )
        let enSystem = enMessages[0]["content"] ?? ""
        XCTAssertTrue(enSystem.contains("The partner asked a question. Answer it concisely and naturally in first person in 2-4 words."))
        
        // Without pending question -> no question answering instruction
        let regularMessages = AIInferenceEngine.completionMessages(
            context: "Привет, ",
            afterCaret: "",
            instructions: nil,
            screenContext: nil,
            hasPendingQuestion: false
        )
        let regSystem = regularMessages[0]["content"] ?? ""
        XCTAssertFalse(regSystem.contains("Собеседник задал вопрос"))
    }

    func testExtractScreenContextAsyncSecurityExclusion() async {
        let service = ScreenContextService()
        // If an app is in excluded bundle IDs, async extraction immediately returns nil
        let result = await service.extractScreenContextAsync(
            frontmostApp: nil,
            focusedElement: nil,
            excludedBundleIDs: Set(["com.apple.keychainaccess", "com.agilebits.onepassword"])
        )
        // With nil frontmostApp / excluded app in test host, safely returns nil
        XCTAssertNil(result)
    }
}
