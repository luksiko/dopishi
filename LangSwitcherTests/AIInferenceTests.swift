import XCTest
import AppKit
@testable import LangSwitcher

@MainActor
final class AIInferenceTests: XCTestCase {
    
    func testAIDebounceTimerCancellation() async {
        let debouncer = AIDebounceTimer()
        var executed = false
        
        debouncer.schedule(delay: 0.1) {
            executed = true
        }
        
        // Cancel immediately
        debouncer.cancel()
        
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(executed, "Cancelled debouncer task should not execute")
    }
    
    func testAIDebounceTimerExecutionAfterDelay() async {
        let debouncer = AIDebounceTimer()
        var executed = false
        
        debouncer.schedule(delay: 0.05) {
            executed = true
        }
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(executed, "Debouncer task should execute after delay")
    }
    
    func testTokenBudgetAllowsMultipleRussianWords() {
        let context = "Сегодня мы планируем обсудить новый проек"
        XCTAssertGreaterThanOrEqual(AIInferenceEngine.predictionTokenBudget(context: context, maxWords: 4), 32)
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(
            raw: context + "т с нашей командой завтра", context: context,
            wordBuffer: "проек", maxWords: 4), "т с нашей командой")
    }

    func testRejectsRepetitiveContinuationMatchingContextTail() {
        // Direct repetition of words already at the end of the context
        let context = "Привет, рад вас слышать!"
        let raw = "рад вас слышать!"
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: raw, context: context, wordBuffer: "", maxWords: 4))
    }

    func testRejectsRepeatedPhraseOccurredInRecentContext() {
        // Multi-word phrase occurred recently in sentence
        let context = "Спасибо большое за помощь! Мы очень ценим ваше участие, спасибо большое"
        let raw = "за помощь!"
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: raw, context: context, wordBuffer: "", maxWords: 4))
    }

    func testRejectsLeadingPunctuationAfterTerminalPunctuation() {
        // Do not attach comma right after exclamation mark or period
        let context = "Спасибо большое за помощь!"
        let raw = ", рад вас слышать!"
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: raw, context: context, wordBuffer: "", maxWords: 4))
    }

    func testContinuationCleaningAndTrimming() {
        let engine = AIInferenceEngine.shared
        // Test binary lookup doesn't crash
        _ = engine.findEngineBinary()
    }
    
    func testMessagesPreserveCaretBoundariesAndPreferences() throws {
        let messages = AIInferenceEngine.completionMessages(context: "Я проверяю проек", afterCaret: " завтра.", instructions: "Термины на английском")
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages[0]["content"]!.contains("Термины на английском"))
        XCTAssertEqual(messages.last?["content"], "Я проверяю проек")
        XCTAssertTrue(messages[0]["content"]!.contains(" завтра."))
        XCTAssertFalse(messages.description.contains("watch a movie"))
        XCTAssertFalse(messages.description.contains("<|im_start|>"))
    }

    func testMessagesIncludeAppAndWindowTitleContext() {
        let ruMessages = AIInferenceEngine.completionMessages(
            context: "Привет, как дела с",
            afterCaret: "",
            instructions: nil,
            appName: "Slack",
            windowTitle: "#general — Dev Team"
        )
        let ruSystem = ruMessages[0]["content"] ?? ""
        XCTAssertTrue(ruSystem.contains("Активное приложение: Slack."))
        XCTAssertTrue(ruSystem.contains("Контекст/тема окна: \"#general — Dev Team\"."))

        let enMessages = AIInferenceEngine.completionMessages(
            context: "const user = await db.",
            afterCaret: "",
            instructions: nil,
            appName: "Visual Studio Code",
            windowTitle: "auth.ts — backend"
        )
        let enSystem = enMessages[0]["content"] ?? ""
        XCTAssertTrue(enSystem.contains("Active application: Visual Studio Code."))
        XCTAssertTrue(enSystem.contains("Window context: \"auth.ts — backend\"."))
    }

    func testWordHealingAcceptsOnlyTheTypedPrefix() {
        XCTAssertEqual(AIInferenceEngine.healedContinuation(" handler correctly", wordBuffer: "handl"), "er correctly")
        XCTAssertEqual(AIInferenceEngine.healedContinuation(" событий", wordBuffer: "событ"), "ий")
        XCTAssertNil(AIInferenceEngine.healedContinuation("keyboard events", wordBuffer: "handl"))
    }

    func testPrefixAvoidsStandaloneWhitespaceTokenAndPreservesMidWord() {
        XCTAssertEqual(AIInferenceEngine.continuationPrefix("Привет мир "), "Привет мир")
        XCTAssertEqual(AIInferenceEngine.continuationPrefix("keyboard handl"), "keyboard handl")
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: ".", context: "hello", wordBuffer: "", maxWords: 4))
    }

    func testBudgetDoesNotGrowWithContextEcho() {
        XCTAssertEqual(AIInferenceEngine.predictionTokenBudget(context: String(repeating: "я ", count: 1000), maxWords: 4), 32)
    }

    func testCleanAndTrimContinuationMidWordEcho() {
        // Model echoed context + completed word
        let cleaned = AIInferenceEngine.cleanAndTrimContinuation(
            raw: "когда работает программа программистами?",
            context: "когда работает программа п",
            wordBuffer: "п",
            maxWords: 3
        )
        XCTAssertEqual(cleaned, "рограммистами?")
    }
    
    func testCleanAndTrimContinuationRawMidWord() {
        // Model produced raw continuation without repeating context
        let cleaned = AIInferenceEngine.cleanAndTrimContinuation(
            raw: "акета python? в чем",
            context: "когда работает программа п",
            wordBuffer: "п",
            maxWords: 3
        )
        XCTAssertEqual(cleaned, "акета python? в")
    }
    
    func testCleanAndTrimContinuationLeadingSpace() {
        let cleaned = AIInferenceEngine.cleanAndTrimContinuation(
            raw: " программировании?",
            context: "когда работает Cotypist о",
            wordBuffer: "о",
            maxWords: 3
        )
        XCTAssertEqual(cleaned, " программировании?")
    }
    
    func testCleanAndTrimContinuationStripsThinkingTags() {
        let cleaned = AIInferenceEngine.cleanAndTrimContinuation(
            raw: "<think>internal reasoning here</think>отлично работает",
            context: "все ",
            wordBuffer: "",
            maxWords: 3
        )
        XCTAssertEqual(cleaned, "отлично работает")
    }
    
    func testCleanAndTrimRejectsLatinTranslationForRussianContext() {
        let cleaned = AIInferenceEngine.cleanAndTrimContinuation(
            raw: "I love you very much",
            context: "Я люблю ",
            wordBuffer: "",
            maxWords: 3
        )
        XCTAssertNil(cleaned, "Model translating Russian context to English must be rejected")
    }


    func testTechnicalEnglishIsAllowedInRussianText() {
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "null перед использованием объекта", context: "Проверить на ", wordBuffer: "", maxWords: 4), "null перед использованием объекта")
    }

    func testRejectUnpromptedQuotedEntities() {
        // Hallucinated quote like «Охотнике» when neither context nor screenContext has quotes
        let result = AIInferenceEngine.cleanAndTrimContinuation(
            raw: " можно сказать о «Охотнике», ?",
            context: "Что еще",
            wordBuffer: "",
            maxWords: 4
        )
        XCTAssertNil(result, "Unprompted quoted entities must be rejected as hallucinations")
    }

    func testRejectEssayQuestionsOnShortInput() {
        let result = AIInferenceEngine.cleanAndTrimContinuation(
            raw: " можно сказать о фильме",
            context: "Что еще",
            wordBuffer: "",
            maxWords: 4
        )
        XCTAssertNil(result, "Open-ended essay questions on short input must be rejected")
    }

    func testMalformedPunctuationCleanup() {
        let result = AIInferenceEngine.cleanAndTrimContinuation(
            raw: "хорошо, ?",
            context: "Все будет ",
            wordBuffer: "",
            maxWords: 4
        )
        XCTAssertEqual(result, "хорошо?")
    }

    func testBaseModelMarkupAndRepeatedSuffixAreRemoved() {
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "<code>null</code>, чтобы избежать ошибки", context: "Проверка на ", wordBuffer: "", maxWords: 4), "null, чтобы избежать ошибки")
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "the report tomorrow morning.", context: "I will send ", wordBuffer: "", maxWords: 4, afterCaret: " tomorrow morning."), "the report")
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: " tomorrow morning.", context: "I will send ", wordBuffer: "", maxWords: 4, afterCaret: " tomorrow morning."))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "<start_of_turn>user", context: "hello ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "[User 001]", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "[User 002]", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "User [002]", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "[Model 001]", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "Model [002]", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "[002]", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "User: как дела?", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "Model: как дела?", context: "Привет ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "[User 001] как дела?", context: "Привет, ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "[User 002] как дела?", context: "Привет, ", wordBuffer: "", maxWords: 4))
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "как дела? [User 001]", context: "Привет, ", wordBuffer: "", maxWords: 4), "как дела?")
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "как дела? [User 002]", context: "Привет, ", wordBuffer: "", maxWords: 4), "как дела?")
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "как дела? User [002]", context: "Привет, ", wordBuffer: "", maxWords: 4), "как дела?")
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "как дела? Model [001]", context: "Привет, ", wordBuffer: "", maxWords: 4), "как дела?")
    }

    func testGGUFTemplateDetectionAndMalformedMetadata() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        func number(_ value: UInt64, bytes: Int) -> Data {
            Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        func string(_ value: String) -> Data { number(UInt64(value.utf8.count), bytes: 8) + Data(value.utf8) }
        let header = Data("GGUF".utf8) + number(3, bytes: 4) + number(0, bytes: 8)
        let base = header + number(1, bytes: 8) + string("general.architecture") + number(8, bytes: 4) + string("gemma4")
        try base.write(to: path)
        XCTAssertEqual(AIInferenceEngine.embeddedChatTemplate(at: path.path), false)
        var chat = header
        chat += number(2, bytes: 8)
        chat += string("tokenizer.ggml.tokens")
        chat += number(9, bytes: 4)
        chat += number(8, bytes: 4)
        chat += number(2, bytes: 8)
        chat += string("hello")
        chat += string("world")
        chat += string("tokenizer.chat_template")
        chat += number(8, bytes: 4)
        chat += string("{{ messages }}")
        try chat.write(to: path)
        XCTAssertEqual(AIInferenceEngine.embeddedChatTemplate(at: path.path), true)
        try chat.dropLast().write(to: path)
        XCTAssertNil(AIInferenceEngine.embeddedChatTemplate(at: path.path))
        try Data("not GGUF".utf8).write(to: path)
        XCTAssertNil(AIInferenceEngine.embeddedChatTemplate(at: path.path))
    }

    func testRichCaretContextAndMissingSelectionText() {
        let text = String(repeating: "Описание задачи. ", count: 40) + "Я исправил Tab. "
        let context = AccessibilityService.makeCaretContext(fieldIdentifier: "field", text: text + "После курсора", selection: CFRange(location: (text as NSString).length, length: 0), selectedText: "", maxSurroundingLength: 2048)
        XCTAssertEqual(context.textBeforeCaret, text)
        XCTAssertEqual(context.textAfterCaret, "После курсора")
        XCTAssertTrue(context.hasUsablePredictionContext)
        let selected = AccessibilityService.makeCaretContext(fieldIdentifier: "field", text: "Привет мир", selection: CFRange(location: 7, length: 3), selectedText: "", maxSurroundingLength: 2048)
        XCTAssertEqual(selected.selectedText, "мир")
        XCTAssertFalse(selected.hasUsablePredictionContext)
        XCTAssertFalse(CaretContext(fieldIdentifier: "unknown", textBeforeCaret: "", textAfterCaret: "", selectedText: "", caretLocation: 12, fullTextLength: 0).hasUsablePredictionContext)
    }

    func testSettingsManagerFieldAnchorBadgeToggle() {
        let settings = SettingsManager.shared
        let initial = settings.showFieldAnchorBadge
        
        settings.showFieldAnchorBadge = !initial
        XCTAssertEqual(settings.showFieldAnchorBadge, !initial)
        
        settings.showFieldAnchorBadge = initial
        XCTAssertEqual(settings.showFieldAnchorBadge, initial)
    }

    func testSettingsManagerStreamingToggle() {
        let settings = SettingsManager.shared
        let initial = settings.aiStreamingEnabled
        
        settings.aiStreamingEnabled = !initial
        XCTAssertEqual(settings.aiStreamingEnabled, !initial)
        
        settings.aiStreamingEnabled = initial
        XCTAssertEqual(settings.aiStreamingEnabled, initial)
    }
}


extension AIInferenceTests {
    func testGenericTypesAreNotRemovedAsHTMLTags() {
        for type in ["Array<String>", "Dictionary<String,Int>", "List<T>", "Container<b>", "Array<Array<String>>"] {
            XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: type + " для списка",
                context: "Используй ", wordBuffer: "", maxWords: 4), type + " для списка")
        }
    }

    func testNestedHTMLFormattingIsRemovedWithoutChangingGenericTypes() {
        XCTAssertEqual(AIInferenceEngine.strippingGeneratedMarkup(
            "<code><strong>Array<String></strong></code> для списка"), "Array<String> для списка")
        XCTAssertEqual(AIInferenceEngine.strippingGeneratedMarkup(
            "<span class=\"value\">null</span> перед использованием"), "null перед использованием")
    }

    func testEnglishContinuationAfterRussianParagraphIsAllowed() {
        let context = "Заметка о проекте.\nIn my opinion, "
        XCTAssertEqual(AIInferenceEngine.cleanAndTrimContinuation(raw: "this is working well",
            context: context, wordBuffer: "", maxWords: 4), "this is working well")
        let messages = AIInferenceEngine.completionMessages(context: context, afterCaret: "", instructions: nil)
        XCTAssertEqual(messages.first?["content"], AIInferenceEngine.defaultSystemPromptEn)
    }

    func testRussianParagraphStillRejectsEnglishTranslationAfterEnglishHistory() {
        let context = "Project notes in English.\r\nЯ люблю "
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "I love you very much",
            context: context, wordBuffer: "", maxWords: 4))
        let messages = AIInferenceEngine.completionMessages(context: context, afterCaret: "", instructions: nil)
        XCTAssertEqual(messages.first?["content"], AIInferenceEngine.defaultSystemPromptRu)
    }
}


extension AIInferenceTests {
    func testUnclosedFormattingTagDoesNotLeakIntoSuggestion() {
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "<code>null",
            context: "Проверка на ", wordBuffer: "", maxWords: 4))
        XCTAssertNil(AIInferenceEngine.cleanAndTrimContinuation(raw: "use <strong>this value",
            context: "You should ", wordBuffer: "", maxWords: 4))
    }
}


extension AIInferenceTests {
    func testStopReloadsTemplateMetadataWhenModelIsReplacedAtSamePath() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let engine = AIInferenceEngine()
        defer { engine.stop() }
        func number(_ value: UInt64, bytes: Int) -> Data {
            Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        func string(_ value: String) -> Data { number(UInt64(value.utf8.count), bytes: 8) + Data(value.utf8) }
        func writeModel(hasTemplate: Bool) throws {
            var data = Data("GGUF".utf8)
            data += number(3, bytes: 4)
            data += number(0, bytes: 8)
            data += number(hasTemplate ? 1 : 0, bytes: 8)
            if hasTemplate {
                data += string("tokenizer.chat_template")
                data += number(8, bytes: 4)
                data += string("{{ messages }}")
            }
            try data.write(to: path, options: .atomic)
        }
        try writeModel(hasTemplate: true)
        let initial = await engine.modelUsesChatTemplate(at: path.path)
        XCTAssertEqual(initial, true)
        try writeModel(hasTemplate: false)
        engine.stop()
        let base = await engine.modelUsesChatTemplate(at: path.path)
        XCTAssertEqual(base, false)
        try writeModel(hasTemplate: true)
        engine.stop()
        let chat = await engine.modelUsesChatTemplate(at: path.path)
        XCTAssertEqual(chat, true)
    }

    func testConcurrentModelUsesChatTemplateDeduplication() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let engine = AIInferenceEngine()
        defer { engine.stop() }
        func number(_ value: UInt64, bytes: Int) -> Data {
            Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
        }
        func string(_ value: String) -> Data { number(UInt64(value.utf8.count), bytes: 8) + Data(value.utf8) }
        var data = Data("GGUF".utf8)
        data += number(3, bytes: 4)
        data += number(0, bytes: 8)
        data += number(1, bytes: 8)
        data += string("tokenizer.chat_template")
        data += number(8, bytes: 4)
        data += string("{{ messages }}")
        try data.write(to: path, options: .atomic)

        // Launch 10 simultaneous tasks awaiting template detection
        await withTaskGroup(of: Bool?.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await engine.modelUsesChatTemplate(at: path.path)
                }
            }
            for await res in group {
                XCTAssertEqual(res, true)
            }
        }
    }

    func testEnsureRunningDetectsDeadEngine() async {
        let engine = AIInferenceEngine()
        // When no valid active model is set or engine was stopped
        let running = await engine.ensureRunning()
        XCTAssertFalse(running)
    }

    func testBaseModelContextPrefixFormatsNaturalContext() {
        let prefix = AIInferenceEngine.baseModelContextPrefix(
            context: "Привет, как твои ",
            instructions: "Write in a friendly voice.",
            screenContext: "Собеседник: Привет! Как дела?",
            appName: "Telegram",
            windowTitle: "Чат с коллегой",
            webDomain: nil
        )
        XCTAssertTrue(prefix.contains("Контекст диалога:"))
        XCTAssertTrue(prefix.contains("Собеседник: Привет! Как дела?"))
        XCTAssertTrue(prefix.contains("Стиль и правила:"))
        XCTAssertTrue(prefix.contains("Write in a friendly voice."))
    }

    func testHealedContinuationDoesNotDoubleStripRepeatedPrefix() {
        let context = "Свежий ко"
        let wordBuffer = "ко"
        let raw = "кокосовый сок"
        let healed = AIInferenceEngine.healedContinuation(raw, wordBuffer: wordBuffer)
        XCTAssertEqual(healed, "косовый сок")

        let cleaned = AIInferenceEngine.cleanAndTrimContinuation(
            raw: healed ?? raw,
            context: context,
            wordBuffer: healed != nil ? "" : wordBuffer,
            maxWords: 4
        )
        XCTAssertEqual(cleaned, "косовый сок")
    }
}
