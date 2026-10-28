import XCTest
import AppKit
import SwiftUI
@testable import LangSwitcher

@MainActor
final class AutoCorrectionTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    var textConverter: TextConverter!
    var spellCheckService: SpellCheckService!
    
    override func setUp() {
        super.setUp()
        settingsManager = SettingsManager.shared
        textConverter = TextConverter(settingsManager: settingsManager)
        spellCheckService = SpellCheckService.shared
        
        // Ensure standard EN and RU layouts are enabled for testing
        settingsManager.enabledLayouts = [
            KeyboardLayout(id: "com.apple.keylayout.ABC", localizedName: "ABC", languageCode: "en"),
            KeyboardLayout(id: "com.apple.keylayout.RussianWin", localizedName: "Russian - PC", languageCode: "ru")
        ]
        settingsManager.autoCorrectionEnabled = true
        settingsManager.autoCorrectionUseSpellCheck = true
    }
    
    func testWrongLayoutWordCorrection_GhbdtnToPrivet() {
        let input = "ghbdtn"
        
        // 1. Should detect wrong layout
        XCTAssertTrue(textConverter.looksLikeWrongLayout(input))
        
        // 2. Should convert correctly
        guard let result = textConverter.convertSelectedTextWithInfo(input) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(result.text, "привет")
        
        // 3. Converted word should be valid Russian
        XCTAssertTrue(spellCheckService.isValidWord(result.text, language: "ru"))
        
        // 4. Original word should NOT be valid English
        XCTAssertFalse(spellCheckService.isValidWord(input, language: "en"))
    }
    
    func testWrongLayoutWordCorrection_RuddshToHello() {
        let input = "руддщ"
        
        // 1. Should detect wrong layout
        XCTAssertTrue(textConverter.looksLikeWrongLayout(input))
        
        // 2. Should convert correctly
        guard let result = textConverter.convertSelectedTextWithInfo(input) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(result.text, "hello")
        
        // 3. Converted word should be valid English
        XCTAssertTrue(spellCheckService.isValidWord(result.text, language: "en"))
        
        // 4. Original word should NOT be valid Russian
        XCTAssertFalse(spellCheckService.isValidWord(input, language: "ru"))
    }
    
    func testWrongLayoutWordCorrection_FgeshToAuto() {
        let input = "фгещ"
        
        // 1. Should detect wrong layout
        XCTAssertTrue(textConverter.looksLikeWrongLayout(input))
        
        // 2. Should convert correctly to "auto"
        guard let result = textConverter.convertSelectedTextWithInfo(input) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(result.text, "auto")
        
        // 3. Converted word should be valid English
        XCTAssertTrue(spellCheckService.isValidWord(result.text, language: "en"))
        
        // 4. Original word should NOT be valid in any enabled language (neither en nor ru)
        let sourceLangs = ["en", "ru"]
        XCTAssertFalse(spellCheckService.isValidWordInAnyLanguage(input, languages: sourceLangs))
    }
    
    func testWrongLayoutWordCorrection_SqkkuseToCorrect() {
        let input = "сщккусе"
        
        // 1. Should detect wrong layout
        XCTAssertTrue(textConverter.looksLikeWrongLayout(input))
        
        // 2. Should convert correctly to "correct"
        guard let result = textConverter.convertSelectedTextWithInfo(input) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(result.text, "correct")
        
        // 3. Converted word should be valid English
        XCTAssertTrue(spellCheckService.isValidWord(result.text, language: "en"))
        
        // 4. Original word should NOT be valid in any enabled language
        let sourceLangs = ["en", "ru"]
        XCTAssertFalse(spellCheckService.isValidWordInAnyLanguage(input, languages: sourceLangs))
    }
    
    func testValidEnglishWordIsNotCorrectedAsWrongLayout() {
        let validEnglishWords = ["apple", "window", "keyboard", "computer"]
        
        for word in validEnglishWords {
            // Even if conversion produces characters, the spell check prevents false positive:
            // The word is valid in the source language!
            let isValidInEn = spellCheckService.isValidWord(word, language: "en")
            XCTAssertTrue(isValidInEn, "\(word) should be recognized as valid English")
        }
    }
    
    func testValidRussianWordIsNotCorrectedAsWrongLayout() {
        let validRussianWords = ["яблоко", "окно", "клавиатура", "компьютер"]
        
        for word in validRussianWords {
            let isValidInRu = spellCheckService.isValidWord(word, language: "ru")
            XCTAssertTrue(isValidInRu, "\(word) should be recognized as valid Russian")
        }
    }

    func testTwoInitialCapitalsAutoCorrection() {
        // 1. "ПРивет" is a Russian word vetoed by dictionary from being wrong layout
        let vetoedWord = "ПРивет"
        XCTAssertFalse(textConverter.looksLikeWrongLayout(vetoedWord))
        guard let fixedVetoed = textConverter.fixTwoInitialCapitals(vetoedWord) else {
            XCTFail("Two initial capitals fix returned nil for \(vetoedWord)")
            return
        }
        XCTAssertEqual(fixedVetoed, "Привет")
        XCTAssertTrue(spellCheckService.isValidWord(fixedVetoed, language: "ru"))

        // 2. "ПРобую" is a valid Russian word (though not in top-1000 veto wordlist)
        let nonVetoedWord = "ПРобую"
        guard let fixedNonVetoed = textConverter.fixTwoInitialCapitals(nonVetoedWord) else {
            XCTFail("Two initial capitals fix returned nil for \(nonVetoedWord)")
            return
        }
        XCTAssertEqual(fixedNonVetoed, "Пробую")
        XCTAssertTrue(spellCheckService.isValidWord(fixedNonVetoed, language: "ru"))

        // When converting "ПРобую" to US layout it produces "GHj,e.", which is NOT valid English
        if let converted = textConverter.convertSelectedTextWithInfo(nonVetoedWord) {
            XCTAssertFalse(spellCheckService.isValidWord(converted.text, language: "en"))
        }

        // 3. English word "THis"
        let englishWord = "THis"
        guard let fixedEnglish = textConverter.fixTwoInitialCapitals(englishWord) else {
            XCTFail("Two initial capitals fix returned nil for \(englishWord)")
            return
        }
        XCTAssertEqual(fixedEnglish, "This")
        XCTAssertTrue(spellCheckService.isValidWord(fixedEnglish, language: "en"))
    }

    func testTwoInitialCapitalsOnWrongLayoutConversion() {
        // "GHbdtny" in US layout corresponds to "ПРиветн" or similar
        // Let's test "GHbdtn" -> converts to "ПРивет"
        let input = "GHbdtn"
        XCTAssertTrue(textConverter.looksLikeWrongLayout(input))

        guard let result = textConverter.convertSelectedTextWithInfo(input) else {
            XCTFail("Conversion failed")
            return
        }
        XCTAssertEqual(result.text, "ПРивет")

        // With fixTwoInitialCapitals, it becomes "Привет"
        let fixed = textConverter.fixTwoInitialCapitals(result.text)
        XCTAssertEqual(fixed, "Привет")
        XCTAssertTrue(spellCheckService.isValidWord(fixed!, language: "ru"))
    }

    func testUserReportedSentenceWords() {
        let wordsWithExpected: [(input: String, expected: String)] = [
            ("ns", "ты"),
            ("cyjdf", "снова"),
            ("gthtcnfk", "перестал"),
            ("gjnjve", "потому"),
            ("xnj", "что"),
            ("cvtybk", "сменил"),
            ("zpsr", "язык"),
            ("yf", "на"),
            ("fyukbqcrbq", "английский"),
            (",jkmit", "больше"),
            ("yt", "не"),
            ("cnfk", "стал"),
            ("vtyz", "меня"),
            ("bcghfdkznm", "исправлять")
        ]
        
        for item in wordsWithExpected {
            XCTAssertTrue(textConverter.looksLikeWrongLayout(item.input), "Should detect wrong layout for '\(item.input)'")
            let conv = textConverter.convertSelectedTextWithInfo(item.input)
            XCTAssertEqual(conv?.text, item.expected, "Should convert '\(item.input)' to '\(item.expected)'")
            if let converted = conv?.text {
                XCTAssertTrue(spellCheckService.isValidWord(converted, language: "ru"), "'\(converted)' should be valid Russian")
            }
        }
        
        // Comma key produces 'б' in Russian layout from ABC layout
        let enabled = settingsManager.enabledLayouts.map(\.id)
        XCTAssertTrue(CorrectionToken.isAlternativeLetter(",", source: "com.apple.keylayout.ABC", targets: enabled))
        XCTAssertFalse(CorrectionToken.isAlternativeLetter(",", source: "com.apple.keylayout.RussianWin", targets: enabled))
    }
}

final class ServiceRecoveryTests: XCTestCase {
    func testDisabledNeverStartsEvenWithoutPermission() {
        XCTAssertEqual(ServiceRecovery.action(enabled: false, trusted: false, valid: true, running: true), .disable)
    }
    func testRevokedPermissionStopsExistingTap() {
        XCTAssertEqual(ServiceRecovery.action(enabled: true, trusted: false, valid: true, running: true), .waitForPermission)
    }
    func testGrantingPermissionStartsMissingTap() {
        XCTAssertEqual(ServiceRecovery.action(enabled: true, trusted: true, valid: false, running: false), .start)
    }
    func testInvalidPortIsRecreatedEvenIfReportedEnabled() {
        XCTAssertEqual(ServiceRecovery.action(enabled: true, trusted: true, valid: false, running: true), .start)
    }
    func testSystemDisabledTapIsReenabled() {
        XCTAssertEqual(ServiceRecovery.action(enabled: true, trusted: true, valid: true, running: false), .enable)
    }
    func testHealthyTapIsNotRestarted() {
        XCTAssertEqual(ServiceRecovery.action(enabled: true, trusted: true, valid: true, running: true), .none)
    }
    func testInstanceLockExcludesSecondAndReleasesAfterExit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var first: AppInstanceLock? = try AppInstanceLock(url: url)
        XCTAssertTrue(first!.acquired)
        let second = try AppInstanceLock(url: url)
        XCTAssertFalse(second.acquired)
        first = nil
        let third = try AppInstanceLock(url: url)
        XCTAssertTrue(third.acquired)
        withExtendedLifetime(second) {}
    }
    @MainActor func testCopyDiscoveryDeduplicatesAndDropsMissingPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        XCTAssertEqual(ServiceStatus.uniqueCopies([root, alias, root.appendingPathComponent("missing")]), [root.resolvingSymlinksInPath()])
    }
}

final class CheckedTextReplacementTests: XCTestCase {
    func testBoundaryClassificationUsesActualLayoutMappings() {
        let targets = ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"]
        XCTAssertTrue(CorrectionToken.isAlternativeLetter(";", source: targets[0], targets: targets))
        XCTAssertTrue(CorrectionToken.isAlternativeLetter("'", source: targets[0], targets: targets))
        XCTAssertFalse(CorrectionToken.isAlternativeLetter("!", source: targets[0], targets: targets))
        XCTAssertFalse(CorrectionToken.isAlternativeLetter(" ", source: targets[0], targets: targets))
        XCTAssertFalse(CorrectionToken.isAlternativeLetter(";", source: targets[1], targets: targets))
    }

    func testWrongLayoutSemicolonStaysInsideWord() {
        let token = CorrectionToken.split("ghjljk;fq", ambiguous: { $0 == ";" }, validConversion: { _ in true })
        XCTAssertEqual(token.word, "ghjljk;fq")
        XCTAssertEqual(LayoutMapper.convert(text: token.word, from: "com.apple.keylayout.ABC",
                                           to: "com.apple.keylayout.RussianWin"), "продолжай")
    }
    func testSentencePunctuationAndFinalLetterKey() {
        let sentence = CorrectionToken.split("ghbdtn.", ambiguous: { $0 == "." }, validConversion: { $0 == "ghbdtn" })
        XCTAssertEqual(sentence.word, "ghbdtn")
        XCTAssertEqual(sentence.punctuation, ".")
        let word = CorrectionToken.split("ve;", ambiguous: { $0 == ";" }, validConversion: { $0 == "ve;" })
        XCTAssertEqual(word.word, "ve;")
        XCTAssertEqual(word.punctuation, "")
    }
    func testReplacementPreservesLeadingSpacesAndOtherText() {
        let text = "before  ghjljk;fq after"
        let caret = ("before  ghjljk;fq" as NSString).length
        let range = AccessibilityService.verifiedSuffixRange(text: text,
            selection: CFRange(location: caret, length: 0), expected: "ghjljk;fq")
        XCTAssertNotNil(range)
        XCTAssertEqual((text as NSString).replacingCharacters(in: range!, with: "продолжай"), "before  продолжай after")
    }
    func testChangedTextSelectionAndStaleBufferCancelReplacement() {
        XCTAssertNil(AccessibilityService.verifiedSuffixRange(text: "hello x", selection: CFRange(location: 7, length: 0), expected: "hello "))
        XCTAssertNil(AccessibilityService.verifiedSuffixRange(text: "hello", selection: CFRange(location: 5, length: 2), expected: "hello"))
        XCTAssertNil(AccessibilityService.verifiedSuffixRange(text: "ahello", selection: CFRange(location: 6, length: 0), expected: "hello"))
        XCTAssertNil(AccessibilityService.verifiedSuffixRange(text: "hi", selection: CFRange(location: 999, length: 0), expected: "hi"))
    }
    func testUTF16CaretPreservesEmojiAndWhitespace() {
        let text = "👨‍👩‍👧‍👦  ghbdtn "
        let range = AccessibilityService.verifiedSuffixRange(text: text,
            selection: CFRange(location: text.utf16.count, length: 0), expected: "ghbdtn ")!
        XCTAssertEqual((text as NSString).replacingCharacters(in: range, with: "привет "), "👨‍👩‍👧‍👦  привет ")
    }
    func testPressCopyMenuItemSafety() {
        let system = AXUIElementCreateSystemWide()
        XCTAssertFalse(AccessibilityService.pressCopyMenuItem(in: system))
    }
}

final class ReplacementSessionTests: XCTestCase {
    func testPendingEditRejectsOverlappingAcceptAndCorrection() {
        var session = ReplacementSession()
        let operation = session.begin()!
        XCTAssertNil(session.begin())
        session.finish(operation)
        XCTAssertNotNil(session.begin())
    }
    func testOldCallbackCannotUnlockNewEditAfterRestart() {
        var session = ReplacementSession()
        let old = session.begin()!
        session.cancel()
        let current = session.begin()!
        session.finish(old)
        XCTAssertTrue(session.isCurrent(current))
        XCTAssertTrue(session.isBusy)
        session.finish(current)
        XCTAssertFalse(session.isBusy)
    }
}


@MainActor
final class AutocompletionRefreshTests: XCTestCase {
    private func makeService(popup: AutocompletionOverlayController,
                             ghost: GhostTextOverlayController,
                             refresh: AutocompletionRefresh,
                             acceptanceHandler: AutoCorrectionService.AcceptanceHandler? = nil) -> AutoCorrectionService {
        let settings = SettingsManager.shared
        return AutoCorrectionService(settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings),
            overlayController: popup, ghostTextController: ghost, completionRefresh: refresh,
            acceptanceHandler: acceptanceHandler)
    }

    private func showSuggestions(_ popup: AutocompletionOverlayController,
                                 _ ghost: GhostTextOverlayController) {
        let candidate = AutocompletionCandidate(word: "hello", targetLayoutID: "com.apple.keylayout.US")
        let caret = CGRect(x: 100, y: 200, width: 1, height: 18)
        popup.show(candidates: [candidate], caretRect: caret, acceptKeyHint: "Tab", onSelect: { _ in })
        ghost.show(candidate: candidate, suffix: "llo", caretRect: caret)
    }

    func testTypingImmediatelyDiscardsOldCandidates() throws {
        let popup = AutocompletionOverlayController()
        let ghost = GhostTextOverlayController()
        let service = makeService(popup: popup, ghost: ghost, refresh: AutocompletionRefresh())
        defer { service.stop() }
        showSuggestions(popup, ghost)
        let key = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x01, keyDown: true))
        key.flags = []
        XCTAssertFalse(service.interceptKeyIfOverlayVisible(event: key))
        XCTAssertFalse(popup.isVisible)
        XCTAssertNil(popup.selectedCandidate)
        XCTAssertFalse(ghost.isVisible)
        XCTAssertNil(ghost.currentCandidate)
        let tab = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true))
        tab.flags = []
        XCTAssertFalse(service.interceptKeyIfOverlayVisible(event: tab))
    }

    func testFailedAcceptanceDoesNotConsumeShortcut() throws {
        let settings = SettingsManager.shared
        let savedAcceptKey = settings.autoCompletionAcceptKey
        let savedAcceptAllKey = settings.autoCompletionAcceptAllKey
        let savedNumberShortcuts = settings.autoCompletionUseNumberShortcuts
        defer {
            settings.autoCompletionAcceptKey = savedAcceptKey
            settings.autoCompletionAcceptAllKey = savedAcceptAllKey
            settings.autoCompletionUseNumberShortcuts = savedNumberShortcuts
        }
        settings.autoCompletionAcceptKey = .tab
        settings.autoCompletionAcceptAllKey = .shiftTab
        settings.autoCompletionUseNumberShortcuts = true

        for (keyCode, flags) in [(UInt16(0x30), CGEventFlags()),
                                 (UInt16(0x30), CGEventFlags.maskShift),
                                 (UInt16(0x12), CGEventFlags())] {
            let popup = AutocompletionOverlayController()
            let ghost = GhostTextOverlayController()
            let service = makeService(popup: popup, ghost: ghost, refresh: AutocompletionRefresh())
            defer { service.stop() }
            // Visible candidates with no captured replacement target model a stale
            // presentation. Acceptance must fail without touching another editor.
            showSuggestions(popup, ghost)
            let key = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true))
            key.flags = flags
            XCTAssertFalse(service.interceptKeyIfOverlayVisible(event: key),
                           "A failed insertion must leave the shortcut available to the editor")
            XCTAssertFalse(popup.isVisible)
            XCTAssertFalse(ghost.isVisible)
        }
    }

    func testTabWithoutSuggestionPassesThrough() throws {
        let popup = AutocompletionOverlayController()
        let ghost = GhostTextOverlayController()
        let service = makeService(popup: popup, ghost: ghost, refresh: AutocompletionRefresh())
        defer { service.stop() }
        let tab = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true))
        tab.flags = []
        XCTAssertFalse(service.interceptKeyIfOverlayVisible(event: tab))
    }

    func testEscapeCancelsPendingRefresh() async throws {
        let popup = AutocompletionOverlayController()
        let ghost = GhostTextOverlayController()
        let refresh = AutocompletionRefresh()
        let service = makeService(popup: popup, ghost: ghost, refresh: refresh)
        defer { service.stop() }
        showSuggestions(popup, ghost)
        let reopened = expectation(description: "Dismissed completion must not reappear")
        reopened.isInverted = true
        refresh.schedule { reopened.fulfill() }
        let escape = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true))
        escape.flags = []
        XCTAssertTrue(service.interceptKeyIfOverlayVisible(event: escape))
        XCTAssertFalse(popup.isVisible)
        XCTAssertFalse(ghost.isVisible)
        await fulfillment(of: [reopened], timeout: 0.1)
    }

    func testNewerRefreshReplacesPendingRefresh() async {
        let refresh = AutocompletionRefresh()
        var calls: [String] = []
        let completed = expectation(description: "Latest prefix refreshed")
        refresh.schedule { calls.append("old") }
        refresh.schedule { calls.append("new"); completed.fulfill() }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(calls, ["new"])
    }
}

extension CheckedTextReplacementTests {
    func testUnknownWordRetainsSentencePunctuation() {
        let token = CorrectionToken.split("ghbdtnxxx.", ambiguous: { $0 == "." }, validConversion: { _ in false })
        XCTAssertEqual(token.word, "ghbdtnxxx")
        XCTAssertEqual(token.punctuation, ".")
        XCTAssertEqual(LayoutMapper.convert(text: token.word, from: "com.apple.keylayout.ABC",
            to: "com.apple.keylayout.RussianWin")! + token.punctuation, "приветччч.")
    }

    func testFinalLetterKeyBeforePunctuationStaysInRecognizedWord() {
        let token = CorrectionToken.split("yj;.", ambiguous: { ";.".contains($0) },
                                         validConversion: { ["yj;", "yj"].contains($0) })
        XCTAssertEqual(token.word, "yj;")
        XCTAssertEqual(token.punctuation, ".")
    }

    func testPunctuationOnlyBufferIsPreserved() {
        let token = CorrectionToken.split("...", ambiguous: { $0 == "." }, validConversion: { _ in false })
        XCTAssertEqual(token.word, "...")
        XCTAssertEqual(token.punctuation, "")
    }
}


extension CheckedTextReplacementTests {
    func testProtectedFieldsNeverReachTokenAnalysisOrLoggingConverters() {
        for focus in [("AXSecureTextField", nil as String?), ("AXTextField", "AXSecureTextField")] {
            let allowed = AutoCorrectionGate.allowsAutoCorrection(role: focus.0,
                subrole: focus.1, bundleID: "com.example.Editor", excludedBundleIDs: [])
            let token = CorrectionToken.analyze("dummySecret;", whenAllowed: allowed,
                ambiguous: { _ in XCTFail("Protected text reached key analysis"); return true },
                validConversion: { _ in XCTFail("Protected text reached conversion/logging"); return true })
            XCTAssertNil(token)
        }
    }

    func testExcludedAndUnknownFieldsNeverReachTokenAnalysis() {
        let excluded = "com.example.Excluded"
        let policies = [
            AutoCorrectionGate.allowsAutoCorrection(role: "AXTextArea", subrole: nil,
                bundleID: excluded, excludedBundleIDs: [excluded]),
            AutoCorrectionGate.allowsAutoCorrection(role: nil, subrole: nil, bundleID: nil)
        ]
        for allowed in policies {
            XCTAssertNil(CorrectionToken.analyze("dummySecret.", whenAllowed: allowed,
                ambiguous: { _ in XCTFail("Denied text reached key analysis"); return true },
                validConversion: { _ in XCTFail("Denied text reached conversion"); return true }))
        }
    }

    func testQuotedWrongLayoutWordsPreserveBothQuotationMarks() {
        let source = "com.apple.keylayout.ABC"
        let target = "com.apple.keylayout.RussianWin"
        for quote in ["\"", "'"] {
            let input = quote + "ghbdtn" + quote
            let token = CorrectionToken.split(input,
                ambiguous: { CorrectionToken.isAlternativeLetter($0, source: source, targets: [source, target]) },
                validConversion: { $0 == "ghbdtn" })
            XCTAssertEqual(token.prefix, quote)
            XCTAssertEqual(token.word, "ghbdtn")
            XCTAssertEqual(token.punctuation, quote)
            let text = LayoutMapper.convert(text: token.word, from: source, to: target)!
            XCTAssertEqual(token.prefix + text + token.punctuation, quote + "привет" + quote)
        }
    }

    func testOpeningQuoteIsPreservedBeforeFirstWordOfPhrase() {
        let token = CorrectionToken.split("\"ghbdtn", ambiguous: { $0 == "\"" },
                                         validConversion: { $0 == "ghbdtn" })
        XCTAssertEqual(token.prefix, "\"")
        XCTAssertEqual(token.word, "ghbdtn")
        XCTAssertEqual(token.punctuation, "")
    }

    func testRecognizedInitialLetterKeyRemainsPartOfWord() {
        let input = "\"nj"
        let token = CorrectionToken.split(input, ambiguous: { $0 == "\"" },
                                         validConversion: { $0 == input })
        XCTAssertEqual(token.prefix, "")
        XCTAssertEqual(token.word, input)
        XCTAssertEqual(LayoutMapper.convert(text: token.word, from: "com.apple.keylayout.ABC",
                                           to: "com.apple.keylayout.RussianWin"), "Это")
    }

    func testQuotesAloneAreNotRemoved() {
        let token = CorrectionToken.split("\"\"", ambiguous: { $0 == "\"" }, validConversion: { _ in false })
        XCTAssertEqual(token.prefix + token.word + token.punctuation, "\"\"")
    }
}

extension ReplacementSessionTests {
    func testAcceptedCompletionCommitsBeforeNextPhysicalCharacter() {
        var session = ReplacementSession()
        var editorText = "hel"
        let consumed = session.performImmediately {
            editorText = "hello "
            return true
        }
        // The event tap only swallows Space after the replacement is committed.
        XCTAssertTrue(consumed)
        XCTAssertEqual(editorText, "hello ")
        XCTAssertFalse(session.isBusy)
        editorText += "w"
        XCTAssertEqual(editorText, "hello w")
    }

    func testFailedCompletionLeavesSpaceAvailableToEditor() {
        var session = ReplacementSession()
        var editorText = "hel"
        let consumed = session.performImmediately { false }
        XCTAssertFalse(consumed)
        XCTAssertFalse(session.isBusy)
        if !consumed { editorText += " " }
        editorText += "w"
        XCTAssertEqual(editorText, "hel w")
    }

    func testImmediateAcceptanceCannotOverlapPendingCorrection() {
        var session = ReplacementSession()
        let pending = session.begin()!
        XCTAssertFalse(session.performImmediately {
            XCTFail("Acceptance must not overlap an existing edit")
            return true
        })
        XCTAssertTrue(session.isCurrent(pending))
        session.finish(pending)
    }
}


extension CheckedTextReplacementTests {
    func testInitialELetterSurvivesSentencePunctuation() {
        let source = "com.apple.keylayout.ABC"
        let target = "com.apple.keylayout.RussianWin"
        for (input, expected) in [("\"njn.", "Этот."), ("'njn.", "этот."), ("\"njn...", "Этот...")] {
            let token = CorrectionToken.split(input,
                ambiguous: { CorrectionToken.isAlternativeLetter($0, source: source, targets: [source, target]) },
                validConversion: { ["\"njn", "'njn"].contains($0) })
            let converted = LayoutMapper.convert(text: token.word, from: source, to: target)!
            XCTAssertEqual(token.prefix + converted + token.punctuation, expected)
        }
    }

    func testUnchangedTextIsNotReportedAsSuccessfulReplacement() {
        let original = "before lf "
        let range = NSRange(location: 7, length: 3)
        XCTAssertFalse(AccessibilityService.replacementWasApplied(original: original, range: range,
            replacement: "да ", observed: original))
        XCTAssertFalse(AccessibilityService.replacementWasApplied(original: original, range: range,
            replacement: "да ", observed: nil))
        XCTAssertTrue(AccessibilityService.replacementWasApplied(original: original, range: range,
            replacement: "да ", observed: "before да "))
        XCTAssertFalse(AccessibilityService.replacementWasApplied(original: original, range: range,
            replacement: "да ", observed: "before да x"))
    }

    func testTwoLetterWordAfterSpacePreservesSentenceAndSpacing() {
        let text = "тест lf "
        let range = AccessibilityService.verifiedSuffixRange(text: text,
            selection: CFRange(location: text.utf16.count, length: 0), expected: "lf ")!
        XCTAssertTrue(AccessibilityService.replacementWasApplied(original: text, range: range,
            replacement: "да ", observed: "тест да "))
    }
}

extension AutoCorrectionTests {
    func testTwoLetterCorrectionDoesNotDependOnThreeLetterCompletionThreshold() throws {
        let saved = settingsManager.autoCompletionMinPrefixLength
        defer { settingsManager.autoCompletionMinPrefixLength = saved }
        settingsManager.autoCompletionMinPrefixLength = 3
        XCTAssertTrue(textConverter.shouldAutoCorrect("lf"))
        let result = try XCTUnwrap(textConverter.autoCorrectWord("lf"))
        XCTAssertEqual(result.text, "да")
        XCTAssertTrue(spellCheckService.isValidWord(result.text, language: "ru"))
        XCTAssertFalse(spellCheckService.isValidWord("lf", language: "en"))
    }
}

// MARK: - Sprint 1: Caret Context, Snooze, & Acceptance in Parts Tests

final class Sprint1FeatureTests: XCTestCase {
    
    @MainActor
    func testCaretContextEqualityAndFields() {
        let ctx1 = CaretContext(
            fieldIdentifier: "app.test:123:456",
            textBeforeCaret: "Hello ",
            textAfterCaret: " world",
            selectedText: "",
            caretLocation: 6,
            fullTextLength: 12
        )
        let ctx2 = CaretContext(
            fieldIdentifier: "app.test:123:456",
            textBeforeCaret: "Hello ",
            textAfterCaret: " world",
            selectedText: "",
            caretLocation: 6,
            fullTextLength: 12
        )
        let ctx3 = CaretContext(
            fieldIdentifier: "app.test:123:789",
            textBeforeCaret: "Hello ",
            textAfterCaret: " world",
            selectedText: "",
            caretLocation: 6,
            fullTextLength: 12
        )
        
        XCTAssertEqual(ctx1, ctx2)
        XCTAssertNotEqual(ctx1, ctx3)
        XCTAssertEqual(ctx1.fieldIdentifier, "app.test:123:456")
        XCTAssertEqual(ctx1.textBeforeCaret, "Hello ")
        XCTAssertEqual(ctx1.textAfterCaret, " world")
        XCTAssertEqual(ctx1.selectedText, "")
        XCTAssertEqual(ctx1.caretLocation, 6)
        XCTAssertEqual(ctx1.fullTextLength, 12)
    }
    
    @MainActor
    func testAcceptAllKeySeparationFromAcceptWordKey() {
        let settings = SettingsManager.shared
        settings.autoCompletionAcceptKey = .tab
        settings.autoCompletionAcceptAllKey = .shiftTab
        
        let tabKeyCode: UInt16 = 0x30
        
        // 1. Plain Tab
        let plainTabFlags = CGEventFlags()
        XCTAssertTrue(settings.isAutocompletionAcceptKey(keyCode: tabKeyCode, flags: plainTabFlags),
                      "Plain Tab should match acceptKey (.tab)")
        XCTAssertFalse(settings.isAutocompletionAcceptAllKey(keyCode: tabKeyCode, flags: plainTabFlags),
                       "Plain Tab should NOT match acceptAllKey (.shiftTab)")
        
        // 2. Shift + Tab
        let shiftTabFlags = CGEventFlags.maskShift
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: tabKeyCode, flags: shiftTabFlags),
                       "Shift+Tab should NOT match acceptKey (.tab)")
        XCTAssertTrue(settings.isAutocompletionAcceptAllKey(keyCode: tabKeyCode, flags: shiftTabFlags),
                      "Shift+Tab should match acceptAllKey (.shiftTab)")
    }
    
    @MainActor
    func testAcceptAllKeyCmdReturnAndOptionTab() {
        let settings = SettingsManager.shared
        
        // Cmd+Return
        settings.autoCompletionAcceptAllKey = .cmdReturn
        let returnKeyCode: UInt16 = 0x24
        let cmdFlags = CGEventFlags.maskCommand
        XCTAssertTrue(settings.isAutocompletionAcceptAllKey(keyCode: returnKeyCode, flags: cmdFlags))
        XCTAssertFalse(settings.isAutocompletionAcceptAllKey(keyCode: returnKeyCode, flags: CGEventFlags()))
        
        // Option+Tab
        settings.autoCompletionAcceptAllKey = .optionTab
        let tabKeyCode: UInt16 = 0x30
        let optFlags = CGEventFlags.maskAlternate
        XCTAssertTrue(settings.isAutocompletionAcceptAllKey(keyCode: tabKeyCode, flags: optFlags))
        XCTAssertFalse(settings.isAutocompletionAcceptAllKey(keyCode: tabKeyCode, flags: CGEventFlags()))
    }
    
    @MainActor
    func testMultiWordCandidateSplittingLogic() {
        let candidate = AutocompletionCandidate(
            word: "how are you doing",
            targetLayoutID: "com.apple.keylayout.US",
            isCrossLayout: false,
            score: 100
        )
        
        let words = candidate.word.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        XCTAssertEqual(words.count, 4)
        
        // Accepting next word:
        let firstWord = words[0] + " "
        let remainder = words.dropFirst().joined(separator: " ")
        XCTAssertEqual(firstWord, "how ")
        XCTAssertEqual(remainder, "are you doing")
        
        // Accepting next word from remainder:
        let nextWords = remainder.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let secondWord = nextWords[0] + " "
        let nextRemainder = nextWords.dropFirst().joined(separator: " ")
        XCTAssertEqual(secondWord, "are ")
        XCTAssertEqual(nextRemainder, "you doing")
    }
    
    @MainActor
    func testCaretContextSafeWithEmojiAndUTF16Offsets() {
        // "Привет 🎉 мир" has emoji which takes 2 UTF-16 code units
        let fullText = "Привет 🎉 мир"
        let utf16Count = fullText.utf16.count
        
        let caret16 = 9 // right after 🎉 
        let idxBefore = String.Index(utf16Offset: 0, in: fullText)
        let idxCaret = String.Index(utf16Offset: caret16, in: fullText)
        let textBefore = String(fullText[idxBefore..<idxCaret])
        
        XCTAssertEqual(textBefore, "Привет 🎉")
        XCTAssertEqual(utf16Count, fullText.utf16.count)
    }
    
    @MainActor
    func testPhraseAcceptancePlanWithEmptyBufferAndAnchor() {
        let planWithBuffer = PhraseAcceptancePlan(buffer: "hel", continuationAnchor: nil, insertion: "hello ")
        XCTAssertEqual(planWithBuffer.expected, "hel")
        XCTAssertEqual(planWithBuffer.replacement, "hello ")
        
        let planContinuation = PhraseAcceptancePlan(buffer: "", continuationAnchor: "hello ", insertion: "world ")
        XCTAssertEqual(planContinuation.expected, "hello ")
        XCTAssertEqual(planContinuation.replacement, "hello world ")
        
        let planContinuationDirect = PhraseAcceptancePlan(buffer: "", continuationAnchor: nil, insertion: "world ")
        XCTAssertEqual(planContinuationDirect.expected, "")
        XCTAssertEqual(planContinuationDirect.replacement, "world ")
    }
}


final class VerifiedPasteAndContinuationTests: XCTestCase {
    func testFocusChangeDuringClipboardPreparationCancelsPaste() {
        var posted: [pid_t] = []
        XCTAssertFalse(AccessibilityService.dispatchVerifiedPaste(to: 123,
            verifySelection: { false }, post: { posted.append($0) }))
        XCTAssertTrue(posted.isEmpty)
    }

    func testPasteDeliveryUsesCapturedProcess() {
        var posted: [pid_t] = []
        XCTAssertTrue(AccessibilityService.dispatchVerifiedPaste(to: 123,
            verifySelection: { true }, post: { posted.append($0) }))
        XCTAssertEqual(posted, [123])
    }

    func testSuccessfulPasteRemainsSuccessfulWhenTypingContinues() {
        let range = NSRange(location: 0, length: 3)
        XCTAssertTrue(AccessibilityService.replacementWasApplied(original: "lf ", range: range,
            replacement: "да ", observed: "да x", allowFollowingInput: true))
        XCTAssertFalse(AccessibilityService.replacementWasApplied(original: "lf ", range: range,
            replacement: "да ", observed: "lf x", allowFollowingInput: true))
        XCTAssertTrue(AccessibilityService.replacementWasApplied(original: "lf suffix", range: range,
            replacement: "да ", observed: "да xsuffix", allowFollowingInput: true))
        XCTAssertFalse(AccessibilityService.replacementWasApplied(original: "lf suffix", range: range,
            replacement: "да ", observed: "да xchanged", allowFollowingInput: true))
    }

    func testPasteCanCompleteBeforeNextPhysicalInputAndOnlyOnce() {
        var applied = false
        var receipts: [Bool] = []
        let confirmation = PasteConfirmation(applied: { applied }, finish: { receipts.append($0) })
        confirmation.check()
        XCTAssertTrue(receipts.isEmpty)
        applied = true
        confirmation.check() // Same check made at the start of the event callback.
        XCTAssertEqual(receipts, [true])
        confirmation.check(final: true)
        XCTAssertEqual(receipts, [true])
    }

    func testUnappliedPasteTimesOutAsFailure() {
        var receipts: [Bool] = []
        let confirmation = PasteConfirmation(applied: { false }, finish: { receipts.append($0) })
        confirmation.check(final: true)
        XCTAssertEqual(receipts, [false])
    }

    func testConsecutivePhraseAcceptsPreserveAlreadyAcceptedWords() throws {
        var text = "ho"
        var buffer = "ho"
        var anchor: String?
        for insertion in ["how ", "are ", "you"] {
            let plan = PhraseAcceptancePlan(buffer: buffer, continuationAnchor: anchor, insertion: insertion)
            let range = try XCTUnwrap(AccessibilityService.verifiedSuffixRange(text: text,
                selection: CFRange(location: text.utf16.count, length: 0), expected: plan.expected))
            text = (text as NSString).replacingCharacters(in: range, with: plan.replacement)
            buffer = ""
            anchor = insertion
        }
        XCTAssertEqual(text, "how are you")
    }

    func testTypedPrefixTakesPrecedenceOverOldContinuationAnchor() {
        let plan = PhraseAcceptancePlan(buffer: "ne", continuationAnchor: "old ", insertion: "new")
        XCTAssertEqual(plan.expected, "ne")
        XCTAssertEqual(plan.replacement, "new")
    }
}


extension VerifiedPasteAndContinuationTests {
    func testRestartFinalizesOldPasteBeforeNewReceipt() {
        var receipts: [String] = []
        let old = PasteConfirmation(applied: { false }, finish: { receipts.append("old:\($0)") })
        old.check(final: true)
        let current = PasteConfirmation(applied: { true }, finish: { receipts.append("new:\($0)") })
        current.check()
        old.check(final: true)
        XCTAssertEqual(receipts, ["old:false", "new:true"])
    }
}


final class CaretContextUTF16Tests: XCTestCase {
    func testEmojiAndCombiningMarksBeforeCyrillicSelection() {
        let prefix = "a👨‍👩‍👧‍👦e\u{301}🇺🇦"
        let text = prefix + "Привет" + "尾"
        let context = AccessibilityService.makeCaretContext(fieldIdentifier: "field", text: text,
            selection: CFRange(location: prefix.utf16.count, length: "Привет".utf16.count), selectedText: "Привет")
        XCTAssertEqual(context.textBeforeCaret, prefix)
        XCTAssertEqual(context.textAfterCaret, "尾")
        XCTAssertEqual(context.selectedText, "Привет")
        XCTAssertEqual(context.caretLocation, prefix.utf16.count)
        XCTAssertEqual(context.fullTextLength, text.utf16.count)
    }

    func testSmallContextWindowDoesNotSplitEmoji() {
        let family = "👨‍👩‍👧‍👦"
        let flag = "🇺🇦"
        let context = AccessibilityService.makeCaretContext(fieldIdentifier: "field", text: family + flag,
            selection: CFRange(location: family.utf16.count, length: 0), selectedText: "", maxSurroundingLength: 1)
        XCTAssertEqual(context.textBeforeCaret, family)
        XCTAssertEqual(context.textAfterCaret, flag)
    }

    func testInvalidRangesAndWindowLengthsAreClampedWithoutOverflow() {
        let end = AccessibilityService.makeCaretContext(fieldIdentifier: "field", text: "да😀",
            selection: CFRange(location: Int.max, length: Int.max), selectedText: "", maxSurroundingLength: Int.max)
        XCTAssertEqual(end.textBeforeCaret, "да😀")
        XCTAssertEqual(end.textAfterCaret, "")
        XCTAssertEqual(end.caretLocation, 4)
        let start = AccessibilityService.makeCaretContext(fieldIdentifier: "field", text: "да😀",
            selection: CFRange(location: -1, length: -1), selectedText: "", maxSurroundingLength: -1)
        XCTAssertEqual(start.caretLocation, 0)
        XCTAssertEqual(start.textBeforeCaret, "")
        XCTAssertEqual(start.textAfterCaret, "")
    }
}


extension VerifiedPasteAndContinuationTests {
    func testDelayedSelectionDoesNotPasteUntilAcknowledged() {
        var acknowledged = false
        var receipts: [Bool] = []
        let selection = PasteConfirmation(applied: { acknowledged }, finish: { receipts.append($0) })
        selection.check()
        selection.check()
        XCTAssertTrue(receipts.isEmpty)
        acknowledged = true
        selection.check()
        selection.check(final: true)
        XCTAssertEqual(receipts, [true])
    }

    func testPhysicalInputCancelsSelectionEvenIfItHasBecomeReady() {
        var ready = false
        var receipts: [Bool] = []
        let selection = PasteConfirmation(applied: { ready }, finish: { receipts.append($0) })
        selection.check()
        ready = true
        selection.cancel()
        selection.check(final: true)
        XCTAssertEqual(receipts, [false])
    }
}

extension AutoCorrectionTests {
    func testApplicationVocabularySurvivesSystemDictionaryOmissions() throws {
        for (input, expected) in [("hfcrkflrb", "раскладки"), ("rkfdbfnehs", "клавиатуры")] {
            let result = try XCTUnwrap(textConverter.convertSelectedTextWithInfo(input))
            XCTAssertEqual(result.text, expected)
            XCTAssertTrue(spellCheckService.isValidWord(result.text, language: "ru"))
            XCTAssertFalse(spellCheckService.isValidWord(input, language: "en"))
        }
        XCTAssertTrue(spellCheckService.isValidWord("РАСКЛАДКИ", language: "ru-RU"))
        XCTAssertFalse(spellCheckService.isValidWord("раскладкыыы", language: "ru"))
        XCTAssertFalse(spellCheckService.isValidWord("раскладки", language: "en"))
    }

    func testAutocompletionShortcutsAndEscapeSettings() {
        // Test .cmdSection acceptAllKey matching
        settingsManager.autoCompletionAcceptAllKey = .cmdSection
        XCTAssertTrue(settingsManager.isAutocompletionAcceptAllKey(keyCode: 0x0A, flags: .maskCommand))
        XCTAssertTrue(settingsManager.isAutocompletionAcceptAllKey(keyCode: 0x32, flags: .maskCommand))
        XCTAssertFalse(settingsManager.isAutocompletionAcceptAllKey(keyCode: 0x0A, flags: []))
        XCTAssertFalse(settingsManager.isAutocompletionAcceptAllKey(keyCode: 0x24, flags: .maskCommand))

        // Test force-activate matching
        settingsManager.autoCompletionForceActivateEnabled = true
        settingsManager.autoCompletionForceActivateKeyCode = 0x0A
        settingsManager.autoCompletionForceActivateModifiers = NSEvent.ModifierFlags.control.rawValue
        XCTAssertTrue(settingsManager.isAutocompletionForceActivateKey(keyCode: 0x0A, flags: .maskControl))
        XCTAssertFalse(settingsManager.isAutocompletionForceActivateKey(keyCode: 0x0A, flags: .maskCommand))
        
        settingsManager.autoCompletionForceActivateEnabled = false
        XCTAssertFalse(settingsManager.isAutocompletionForceActivateKey(keyCode: 0x0A, flags: .maskControl))

        // Test escape action setting
        settingsManager.autoCompletionEscapeAction = .pauseFewSeconds
        XCTAssertEqual(settingsManager.autoCompletionEscapeAction, .pauseFewSeconds)
        settingsManager.autoCompletionEscapeAction = .dismissOnly
        XCTAssertEqual(settingsManager.autoCompletionEscapeAction, .dismissOnly)

        // Test trailing space and punctuation toggles
        settingsManager.autoCompletionIncludeTrailingSpace = true
        XCTAssertTrue(settingsManager.autoCompletionIncludeTrailingSpace)
        settingsManager.autoCompletionIncludeTrailingSpace = false
        XCTAssertFalse(settingsManager.autoCompletionIncludeTrailingSpace)

        settingsManager.autoCompletionIncludeTrailingPunctuation = true
        XCTAssertTrue(settingsManager.autoCompletionIncludeTrailingPunctuation)
    }
}

@MainActor
final class CompletionInsertionPlanTests: XCTestCase {
    func testMidWordAcceptanceOnlyInsertsMissingTail() {
        let plan = PhraseAcceptancePlan(buffer: "проек", continuationAnchor: nil, insertion: "проект ")
        XCTAssertEqual(plan.appendingSuffix, "т ")
    }

    func testRepeatedTabPreservesWordBoundaryWithoutTrailingSpace() {
        let plan = PhraseAcceptancePlan(buffer: "", continuationAnchor: "hello", insertion: "world")
        XCTAssertEqual(plan.appendingSuffix, " world")
    }

    func testCrossLayoutCompletionRequiresVerifiedReplacement() {
        let plan = PhraseAcceptancePlan(buffer: "ghbdtn", continuationAnchor: nil, insertion: "привет ")
        XCTAssertNil(plan.appendingSuffix)
    }

    func testContinuationAfterAcceptedWordOnlyInsertsNextWord() {
        let plan = PhraseAcceptancePlan(buffer: "", continuationAnchor: "hello ", insertion: "world ")
        XCTAssertEqual(plan.appendingSuffix, "world ")
    }
}

extension VerifiedPasteAndContinuationTests {
    func testAppendingCompletionDoesNotRequireWritableAXSelection() {
        XCTAssertFalse(AccessibilityService.requiresSelectionWrite(
            original: CFRange(location: 5, length: 0), replacementRange: NSRange(location: 5, length: 0)))
        XCTAssertTrue(AccessibilityService.requiresSelectionWrite(
            original: CFRange(location: 5, length: 0), replacementRange: NSRange(location: 0, length: 5)))
        XCTAssertFalse(AccessibilityService.requiresSelectionWrite(
            original: CFRange(location: 0, length: 5), replacementRange: NSRange(location: 0, length: 5)))
    }
}

extension VerifiedPasteAndContinuationTests {
    func testContinuationReceiptAllowsTypingAfterPasteWithoutLosingRightContext() {
        XCTAssertTrue(AccessibilityService.continuationWasApplied(original: "hello suffix",
            observed: "hello world xsuffix", caretBefore: 6, caretAfter: 13, inserted: "world "))
        XCTAssertFalse(AccessibilityService.continuationWasApplied(original: "hello suffix",
            observed: "hello xsuffix", caretBefore: 6, caretAfter: 7, inserted: "world "))
        XCTAssertFalse(AccessibilityService.continuationWasApplied(original: "hello suffix",
            observed: "hello world xchanged", caretBefore: 6, caretAfter: 13, inserted: "world "))
    }

    func testUnconfirmedDispatchedPasteNeverReplaysAcceptanceShortcut() {
        var outcomes: [CompletionPasteOutcome] = []
        let receipt = PasteConfirmation(applied: { false }, finish: {
            outcomes.append($0 ? .applied : .unconfirmed)
        })
        receipt.check(final: true)
        receipt.check(final: true)
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertFalse(outcomes[0].shouldReplayShortcut)
        XCTAssertFalse(CompletionPasteOutcome.applied.shouldReplayShortcut)
        XCTAssertTrue(CompletionPasteOutcome.notDispatched.shouldReplayShortcut)
    }

    func testWebContinuationCanConfirmThroughCaretWhenAXValueIsUnavailable() {
        XCTAssertTrue(AccessibilityService.continuationWasApplied(original: nil, observed: nil,
            caretBefore: 10, caretAfter: 17, inserted: "привет "))
        XCTAssertFalse(AccessibilityService.continuationWasApplied(original: nil, observed: nil,
            caretBefore: 10, caretAfter: 10, inserted: "привет "))
        XCTAssertFalse(AccessibilityService.continuationWasApplied(original: "hello", observed: "hello",
            caretBefore: 5, caretAfter: 11, inserted: " world"))
        XCTAssertTrue(AccessibilityService.continuationWasApplied(original: "hello", observed: "hello world",
            caretBefore: 5, caretAfter: 11, inserted: " world"))
    }
}


extension AutocompletionRefreshTests {
    func testHeldAcceptanceKeyIsConsumedUntilReleaseEvenAfterSuggestionDisappears() throws {
        let settings = SettingsManager.shared
        let saved = (settings.autoCompletionAcceptKey, settings.autoCompletionAcceptAllKey)
        defer {
            settings.autoCompletionAcceptKey = saved.0
            settings.autoCompletionAcceptAllKey = saved.1
        }
        settings.autoCompletionAcceptKey = .tab
        settings.autoCompletionAcceptAllKey = .shiftTab
        let popup = AutocompletionOverlayController()
        let ghost = GhostTextOverlayController()
        var acceptances = 0
        let service = makeService(popup: popup, ghost: ghost, refresh: AutocompletionRefresh(),
            acceptanceHandler: { _, _, _, _ in acceptances += 1; return true })
        defer { service.stop() }
        for flags: CGEventFlags in [[], .maskShift] {
            showSuggestions(popup, ghost)
            let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true))
            down.flags = flags
            XCTAssertTrue(service.interceptCompletionKeyEvent(down))
            popup.hide()
            ghost.hide()
            let repeated = try XCTUnwrap(down.copy())
            repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            repeated.flags = [] // Modifier changes must not release ownership.
            for _ in 0..<3 { XCTAssertTrue(service.interceptCompletionKeyEvent(repeated)) }
            let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: false))
            XCTAssertTrue(service.interceptCompletionKeyEvent(up))
            XCTAssertFalse(service.interceptCompletionKeyEvent(down))
            XCTAssertFalse(service.interceptCompletionKeyEvent(repeated))
            XCTAssertFalse(service.interceptCompletionKeyEvent(up))
        }
        XCTAssertEqual(acceptances, 2)
    }

    func testVisibleGhostHonorsWordSettingAndRetainsFailureKey() throws {
        let settings = SettingsManager.shared
        let saved = (settings.autoCompletionAcceptKey, settings.autoCompletionAcceptAllKey,
                     settings.autoCompletionAcceptEntirePhrase, settings.autoCompletionIncludeTrailingSpace)
        defer {
            settings.autoCompletionAcceptKey = saved.0
            settings.autoCompletionAcceptAllKey = saved.1
            settings.autoCompletionAcceptEntirePhrase = saved.2
            settings.autoCompletionIncludeTrailingSpace = saved.3
        }
        settings.autoCompletionAcceptKey = .tab
        settings.autoCompletionAcceptAllKey = .shiftTab
        settings.autoCompletionIncludeTrailingSpace = false
        let popup = AutocompletionOverlayController()
        let ghost = GhostTextOverlayController()
        var received: [(Bool, Bool, UInt16?)] = []
        let service = makeService(popup: popup, ghost: ghost, refresh: AutocompletionRefresh(),
            acceptanceHandler: { _, space, entire, failureEvent in
                received.append((space, entire, failureEvent.map { UInt16($0.getIntegerValueField(.keyboardEventKeycode)) }))
                return true
            })
        defer { service.stop() }
        for entire in [false, true] {
            settings.autoCompletionAcceptEntirePhrase = entire
            showSuggestions(popup, ghost)
            let tab = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true))
            tab.flags = []
            XCTAssertTrue(service.interceptKeyIfOverlayVisible(event: tab))
            XCTAssertEqual(received.last?.0, false)
            XCTAssertEqual(received.last?.1, entire)
            XCTAssertEqual(received.last?.2, 0x30)
        }
        settings.autoCompletionAcceptEntirePhrase = false
        showSuggestions(popup, ghost)
        let full = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true))
        full.flags = .maskShift
        XCTAssertTrue(service.interceptKeyIfOverlayVisible(event: full))
        XCTAssertEqual(received.last?.1, true)
    }
}

@MainActor
final class CompletionControlRegressionTests: XCTestCase {
    func testGlobalToggleRetainsKeyboardMonitoringWhenTypingFeaturesAreOff() {
        let settings = SettingsManager.shared
        let saved = (settings.autoCorrectionEnabled, settings.autoCompletionEnabled, settings.autoCompletionToggleGlobalEnabled)
        defer {
            settings.autoCorrectionEnabled = saved.0
            settings.autoCompletionEnabled = saved.1
            settings.autoCompletionToggleGlobalEnabled = saved.2
        }
        settings.autoCorrectionEnabled = false
        settings.autoCompletionEnabled = false
        settings.autoCompletionToggleGlobalEnabled = true
        XCTAssertTrue(settings.needsKeyboardMonitoring)
        XCTAssertEqual(ServiceRecovery.action(enabled: settings.needsKeyboardMonitoring,
            trusted: true, valid: true, running: true), .none)
        settings.autoCompletionToggleGlobalEnabled = false
        XCTAssertFalse(settings.needsKeyboardMonitoring)
    }

    func testRecordingEnablesShortcutIncludingUnmodifiedA() {
        var code: UInt16 = 0
        var modifiers: UInt = 0
        var enabled = false
        let recorder = AutocompletionKeyRecorderView(
            keyCode: Binding(get: { code }, set: { code = $0 }),
            modifiers: Binding(get: { modifiers }, set: { modifiers = $0 }),
            canClear: true, enabled: Binding(get: { enabled }, set: { enabled = $0 }))
        recorder.recordShortcut(keyCode: 0x0A, modifiers: NSEvent.ModifierFlags.control.rawValue)
        XCTAssertTrue(enabled)
        XCTAssertEqual(code, 0x0A)
        enabled = false
        recorder.recordShortcut(keyCode: 0, modifiers: 0)
        XCTAssertTrue(enabled)
        XCTAssertEqual(code, 0)
        XCTAssertEqual(modifiers, 0)
    }

    func testPerAppPauseExpiresAndNeverChangesCorrectionExclusions() {
        let exclusions = SettingsManager.shared.excludedAppBundleIDs
        let now = Date(timeIntervalSince1970: 1000)
        var pauses = CompletionAppPauses()
        XCTAssertTrue(pauses.toggle(bundleID: "com.apple.Terminal", now: now))
        XCTAssertTrue(pauses.isPaused(bundleID: "com.apple.Terminal", now: now.addingTimeInterval(299)))
        XCTAssertFalse(pauses.isPaused(bundleID: "other.app", now: now))
        XCTAssertFalse(pauses.isPaused(bundleID: "com.apple.Terminal", now: now.addingTimeInterval(300)))
        XCTAssertFalse(pauses.toggle(bundleID: "com.apple.Terminal", now: now.addingTimeInterval(1)))
        XCTAssertEqual(SettingsManager.shared.excludedAppBundleIDs, exclusions)
    }

    func testForcedInputKeepsCompletedWordsOutOfPrefix() {
        let spaced = CompletionTypingContext(beforeCaret: "hello world ")
        XCTAssertEqual(spaced.prefix, "")
        XCTAssertEqual(spaced.previousWord, "world")
        let typing = CompletionTypingContext(beforeCaret: "hello wor")
        XCTAssertEqual(typing.prefix, "wor")
        XCTAssertEqual(typing.previousWord, "hello")
        XCTAssertEqual(CompletionTypingContext(beforeCaret: "hello.").prefix, "")
        XCTAssertEqual(CompletionTypingContext(beforeCaret: "").prefix, "")
    }

    func testWordAcceptanceDefersAttachedPunctuationWithoutAddingSpace() {
        let plan = CompletionAcceptanceText(candidate: "готово, продолжаем", typedPrefix: "гот",
            entirePhrase: false, appendSpace: true, includePunctuation: false)
        XCTAssertEqual(plan.insertion, "готово")
        XCTAssertEqual(plan.remaining, ", продолжаем")
        let punctuation = CompletionAcceptanceText(candidate: plan.remaining!, typedPrefix: "",
            entirePhrase: false, appendSpace: true, includePunctuation: false)
        XCTAssertEqual(punctuation.insertion, ", ")
        XCTAssertEqual(punctuation.remaining, "продолжаем")
        let tail = PhraseAcceptancePlan(buffer: "", continuationAnchor: plan.insertion, insertion: punctuation.insertion)
        XCTAssertEqual(tail.appendingSuffix, ", ")
    }

    func testSingleWordPunctuationAlsoRespectsSetting() {
        let plan = CompletionAcceptanceText(candidate: "done!", typedPrefix: "do",
            entirePhrase: false, appendSpace: true, includePunctuation: false)
        XCTAssertEqual(plan.insertion, "done")
        XCTAssertEqual(plan.remaining, "!")
    }

    func testEnabledPunctuationAndFullPhraseKeepExpectedText() {
        let word = CompletionAcceptanceText(candidate: "done, next", typedPrefix: "do",
            entirePhrase: false, appendSpace: true, includePunctuation: true)
        XCTAssertEqual(word.insertion, "done, ")
        XCTAssertEqual(word.remaining, "next")
        let full = CompletionAcceptanceText(candidate: "done, next", typedPrefix: "do",
            entirePhrase: true, appendSpace: false, includePunctuation: false)
        XCTAssertEqual(full.insertion, "done, next")
        XCTAssertNil(full.remaining)
    }

    func testLeadingSpacePreservedInCompletionAcceptanceTextAndPhrasePlan() {
        let plan = CompletionAcceptanceText(candidate: " правильно написать", typedPrefix: "",
            entirePhrase: false, appendSpace: true, includePunctuation: false)
        XCTAssertEqual(plan.insertion, " правильно ")
        XCTAssertEqual(plan.remaining, "написать")

        let phrasePlan = PhraseAcceptancePlan(buffer: "Как", continuationAnchor: nil, insertion: plan.insertion)
        XCTAssertEqual(phrasePlan.expected, "Как")
        XCTAssertEqual(phrasePlan.replacement, "Как правильно ")
        XCTAssertEqual(phrasePlan.appendingSuffix, " правильно ")
    }
}


extension CompletionInsertionPlanTests {
    func testRepeatedWordAcceptancePreservesBoundaryBeforeNumber() {
        let first = CompletionAcceptanceText(candidate: "встреча 2026 года", typedPrefix: "встр",
            entirePhrase: false, appendSpace: false, includePunctuation: true)
        let second = CompletionAcceptanceText(candidate: first.remaining!, typedPrefix: "",
            entirePhrase: false, appendSpace: false, includePunctuation: true)
        let plan = PhraseAcceptancePlan(buffer: "", continuationAnchor: first.insertion, insertion: second.insertion)
        XCTAssertEqual(plan.replacement, "встреча 2026")
        XCTAssertEqual(plan.appendingSuffix, " 2026")
    }

    func testQuotedWordAndSymbolKeepWordBoundary() {
        for token in ["\"hello\"", "_value", "😀"] {
            let plan = PhraseAcceptancePlan(buffer: "", continuationAnchor: "next", insertion: token)
            XCTAssertEqual(plan.appendingSuffix, " " + token)
        }
    }

    func testDeferredPunctuationRemainsAttachedWhenTakingRemainder() {
        let plan = PhraseAcceptancePlan(buffer: "", continuationAnchor: "готово", insertion: ", продолжаем")
        XCTAssertEqual(plan.appendingSuffix, ", продолжаем")
        let spaced = PhraseAcceptancePlan(buffer: "", continuationAnchor: "встреча ", insertion: "2026")
        XCTAssertEqual(spaced.appendingSuffix, "2026")
    }
}


extension CompletionInsertionPlanTests {
    func testCompletedWordAcceptsPendingPunctuationInsteadOfEmptyPaste() {
        for (candidate, appendSpace, expected) in [
            ("работает, продолжаем", true, ", "),
            ("работает, продолжаем", false, ","),
            ("работает , продолжаем", true, ", "),
            ("работает!", false, "!")
        ] {
            let text = CompletionAcceptanceText(candidate: candidate, typedPrefix: "работает",
                entirePhrase: false, appendSpace: appendSpace, includePunctuation: false)
            let plan = PhraseAcceptancePlan(buffer: "работает", continuationAnchor: nil, insertion: text.insertion)
            XCTAssertEqual(plan.appendingSuffix, expected)
            XCTAssertEqual(text.remaining, candidate.hasSuffix("продолжаем") ? "продолжаем" : nil)
        }
    }

    func testPunctuationAfterIncompleteWordStillRequiresSeparateAcceptance() {
        let text = CompletionAcceptanceText(candidate: "работает, продолжаем", typedPrefix: "работ",
            entirePhrase: false, appendSpace: true, includePunctuation: false)
        let plan = PhraseAcceptancePlan(buffer: "работ", continuationAnchor: nil, insertion: text.insertion)
        XCTAssertEqual(plan.appendingSuffix, "ает")
        XCTAssertEqual(text.remaining, ", продолжаем")
    }
}

final class WebKitTextMarkerExtractionTests: XCTestCase {
    func testCaretBoundsFallsBackToMarkerBoundsWhenRangeIsNil() {
        let markerRect = CGRect(x: 150, y: 300, width: 1, height: 16)
        let resolved = AccessibilityService.resolveCaretBounds(
            selectedRange: nil,
            primaryScreenMaxY: 900,
            rangeBounds: { _ in nil },
            markerBounds: { markerRect }
        )
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.origin.x, 150)
        XCTAssertEqual(resolved?.origin.y, 900 - 300 - 16)
    }

    func testMarkerBoundsRejectedIfWideSelection() {
        let wideRect = CGRect(x: 150, y: 300, width: 50, height: 16)
        let resolved = AccessibilityService.resolveCaretBounds(
            selectedRange: nil,
            primaryScreenMaxY: 900,
            rangeBounds: { _ in nil },
            markerBounds: { wideRect }
        )
        XCTAssertNil(resolved)
    }

    func testCaretContextFromSurroundingText() {
        let context = CaretContext(
            fieldIdentifier: "webkit:123",
            textBeforeCaret: "hello ",
            textAfterCaret: "world",
            selectedText: "",
            caretLocation: 6,
            fullTextLength: 11
        )
        XCTAssertEqual(context.fieldIdentifier, "webkit:123")
        XCTAssertEqual(context.textBeforeCaret, "hello ")
        XCTAssertEqual(context.textAfterCaret, "world")
        XCTAssertEqual(context.caretLocation, 6)
        XCTAssertEqual(context.fullTextLength, 11)
    }
}

@MainActor
final class AuxiliaryHUDInterceptionTests: XCTestCase {
    func testAuxiliaryHUDsInterceptKeyEventsSynchronously() throws {
        let settings = SettingsManager.shared
        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings)
        )
        let dummyAnchor = CGRect(x: 100, y: 100, width: 10, height: 10)

        // Ensure initially hidden
        SmartRepliesController.shared.hide()
        WordAlternativesController.shared.hide()
        ThesaurusController.shared.hide()

        let escEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true))
        escEvent.flags = []
        let num1Event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x12, keyDown: true)) // Key "1"
        num1Event.flags = []
        let enterEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true)) // Enter
        enterEvent.flags = []

        // 1. Without active HUDs, events pass through
        XCTAssertFalse(service.interceptCompletionKeyEvent(escEvent))
        XCTAssertFalse(service.interceptCompletionKeyEvent(num1Event))

        // 2. Smart Replies HUD
        let replies = SmartRepliesEngine.generateReplies(for: "Are you free today?")
        SmartRepliesController.shared.show(replies: replies, anchor: dummyAnchor)
        XCTAssertTrue(SmartRepliesController.shared.isVisible)

        // Intercepts numeric selection
        XCTAssertTrue(service.interceptCompletionKeyEvent(num1Event))
        XCTAssertFalse(SmartRepliesController.shared.isVisible) // selected and closed

        // Intercepts escape
        SmartRepliesController.shared.show(replies: replies, anchor: dummyAnchor)
        XCTAssertTrue(SmartRepliesController.shared.isVisible)
        XCTAssertTrue(service.interceptCompletionKeyEvent(escEvent))
        XCTAssertFalse(SmartRepliesController.shared.isVisible)

        // 3. Word Alternatives HUD
        let alts = [WordAlternativesEngine.Alternative(id: 1, text: "apple"),
                    WordAlternativesEngine.Alternative(id: 2, text: "banana")]
        WordAlternativesController.shared.show(alternatives: alts, anchor: dummyAnchor) { _ in }
        XCTAssertTrue(WordAlternativesController.shared.isVisible)

        // Intercepts numeric selection
        XCTAssertTrue(service.interceptCompletionKeyEvent(num1Event))
        XCTAssertFalse(WordAlternativesController.shared.isVisible)

        // Intercepts escape
        WordAlternativesController.shared.show(alternatives: alts, anchor: dummyAnchor) { _ in }
        XCTAssertTrue(WordAlternativesController.shared.isVisible)
        XCTAssertTrue(service.interceptCompletionKeyEvent(escEvent))
        XCTAssertFalse(WordAlternativesController.shared.isVisible)

        // 4. Thesaurus HUD
        let candidates = ThesaurusEngine.candidates(for: "быстрый")
        ThesaurusController.shared.show(word: "быстрый", candidates: candidates, anchor: dummyAnchor)
        XCTAssertTrue(ThesaurusController.shared.isVisible)

        // Intercepts Enter confirmation
        XCTAssertTrue(service.interceptCompletionKeyEvent(enterEvent))
        XCTAssertFalse(ThesaurusController.shared.isVisible)

        // Intercepts escape
        ThesaurusController.shared.show(word: "быстрый", candidates: candidates, anchor: dummyAnchor)
        XCTAssertTrue(ThesaurusController.shared.isVisible)
        XCTAssertTrue(service.interceptCompletionKeyEvent(escEvent))
        XCTAssertFalse(ThesaurusController.shared.isVisible)
    }

    func testConsecutiveTabPressesInterceptedDuringMultiWordAcceptance() throws {
        let settings = SettingsManager.shared
        let savedAcceptKey = settings.autoCompletionAcceptKey
        let savedEntirePhrase = settings.autoCompletionAcceptEntirePhrase
        let savedTrailingSpace = settings.autoCompletionIncludeTrailingSpace
        defer {
            settings.autoCompletionAcceptKey = savedAcceptKey
            settings.autoCompletionAcceptEntirePhrase = savedEntirePhrase
            settings.autoCompletionIncludeTrailingSpace = savedTrailingSpace
        }
        settings.autoCompletionAcceptKey = .tab
        settings.autoCompletionAcceptEntirePhrase = false
        settings.autoCompletionIncludeTrailingSpace = true

        let popup = AutocompletionOverlayController()
        let ghost = GhostTextOverlayController()
        var acceptedWords: [String] = []

        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings),
            overlayController: popup,
            ghostTextController: ghost,
            completionRefresh: AutocompletionRefresh(),
            acceptanceHandler: { candidate, appendSpace, entirePhrase, _ in
                let plan = CompletionAcceptanceText(
                    candidate: candidate.word,
                    typedPrefix: "",
                    entirePhrase: entirePhrase,
                    appendSpace: appendSpace,
                    includePunctuation: true
                )
                acceptedWords.append(plan.insertion)
                if let remaining = plan.remaining, !remaining.isEmpty {
                    let remCand = AutocompletionCandidate(word: remaining, targetLayoutID: candidate.targetLayoutID)
                    let caret = CGRect(x: 120, y: 200, width: 2, height: 16)
                    ghost.show(candidate: remCand, suffix: remaining, caretRect: caret)
                    popup.show(candidates: [remCand], caretRect: caret, acceptKeyHint: "⇥", onSelect: { _ in })
                } else {
                    ghost.hide()
                    popup.hide()
                }
                return true
            }
        )
        defer { service.stop() }

        let initialCandidate = AutocompletionCandidate(word: "первое второе", targetLayoutID: "com.apple.keylayout.Russian")
        let caret = CGRect(x: 100, y: 200, width: 2, height: 16)
        ghost.show(candidate: initialCandidate, suffix: "первое второе", caretRect: caret)
        popup.show(candidates: [initialCandidate], caretRect: caret, acceptKeyHint: "⇥", onSelect: { _ in })

        let tabDown = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: true))
        tabDown.flags = []
        let tabUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x30, keyDown: false))
        tabUp.flags = []

        // First Tab accepts "первое " and leaves "второе" visible in both ghost and popup
        XCTAssertTrue(service.interceptCompletionKeyEvent(tabDown))
        XCTAssertTrue(service.interceptCompletionKeyEvent(tabUp))
        XCTAssertEqual(acceptedWords, ["первое "])
        XCTAssertTrue(ghost.isVisible)
        XCTAssertTrue(popup.isVisible)
        XCTAssertEqual(popup.selectedCandidate?.word, "второе")

        // Second Tab immediately accepts "второе " without leaking Tab to switch focus
        XCTAssertTrue(service.interceptCompletionKeyEvent(tabDown))
        XCTAssertTrue(service.interceptCompletionKeyEvent(tabUp))
        XCTAssertEqual(acceptedWords, ["первое ", "второе "])
        XCTAssertFalse(ghost.isVisible)
        XCTAssertFalse(popup.isVisible)
    }

    func testAutoCorrectionRevertOnBackspace() throws {
        UserDictionary.shared.removeAll()
        defer { UserDictionary.shared.removeAll() }

        let settings = SettingsManager.shared
        let savedRevert = settings.autoCorrectionRevertOnBackspace
        defer { settings.autoCorrectionRevertOnBackspace = savedRevert }
        settings.autoCorrectionRevertOnBackspace = true

        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings)
        )
        defer { service.stop() }

        service.recordAppliedCorrection(
            originalWord: "прошка",
            replacedWord: "крошка",
            fullExpected: "прошка ",
            fullReplacement: "крошка "
        )

        XCTAssertNotNil(service.pendingRevertCorrection)
        XCTAssertFalse(UserDictionary.shared.contains("прошка"))

        let backspaceDown = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: true))
        backspaceDown.flags = []
        let backspaceUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x33, keyDown: false))
        backspaceUp.flags = []

        // Backspace should be intercepted and consumed
        XCTAssertTrue(service.interceptCompletionKeyEvent(backspaceDown))
        XCTAssertTrue(service.interceptCompletionKeyEvent(backspaceUp))

        // Word should be learned to UserDictionary
        XCTAssertTrue(UserDictionary.shared.contains("прошка"))
        XCTAssertNil(service.pendingRevertCorrection)

        // Subsequent backspace should NOT be intercepted (normal editing resumes)
        XCTAssertFalse(service.interceptCompletionKeyEvent(backspaceDown))
    }

    func testAutoCorrectionRevertOnOptionZ() throws {
        UserDictionary.shared.removeAll()
        defer { UserDictionary.shared.removeAll() }

        let settings = SettingsManager.shared
        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings)
        )
        defer { service.stop() }

        service.recordAppliedCorrection(
            originalWord: "слово",
            replacedWord: "олово",
            fullExpected: "слово ",
            fullReplacement: "олово "
        )

        XCTAssertNotNil(service.pendingRevertCorrection)
        XCTAssertFalse(UserDictionary.shared.contains("слово"))

        let optZDown = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x06, keyDown: true))
        optZDown.flags = [.maskAlternate]
        let optZUp = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x06, keyDown: false))
        optZUp.flags = [.maskAlternate]

        // Option+Z should be intercepted and consumed
        XCTAssertTrue(service.interceptCompletionKeyEvent(optZDown))
        XCTAssertTrue(service.interceptCompletionKeyEvent(optZUp))

        // Word should be learned to UserDictionary
        XCTAssertTrue(UserDictionary.shared.contains("слово"))
        XCTAssertNil(service.pendingRevertCorrection)
    }

    func testRetypingCorrectedWordAutoLearnsToUserDictionary() {
        UserDictionary.shared.removeAll()
        defer { UserDictionary.shared.removeAll() }

        let settings = SettingsManager.shared
        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings)
        )
        defer { service.stop() }

        // Simulate an applied auto-correction
        service.recordAppliedCorrection(
            originalWord: "прошка",
            replacedWord: "крошка",
            fullExpected: "прошка ",
            fullReplacement: "крошка "
        )

        XCTAssertFalse(UserDictionary.shared.contains("прошка"))
        XCTAssertNotNil(service.lastAutoCorrection)

        // Simulate user re-typing "прошка"
        let retypedLearned = service.checkAndLearnRetypedWord("прошка")
        XCTAssertTrue(retypedLearned)

        // "прошка" should now be automatically learned into UserDictionary!
        XCTAssertTrue(UserDictionary.shared.contains("прошка"))
        XCTAssertNil(service.lastAutoCorrection)

        // Now that "прошка" is in UserDictionary, TypoCorrectionEngine must veto it!
        let typoCorrection = TypoCorrectionEngine.correctTypo("прошка")
        XCTAssertNil(typoCorrection, "TypoCorrectionEngine must not touch words in UserDictionary")

        // And TextConverter must also veto it!
        let converter = TextConverter(settingsManager: settings)
        XCTAssertFalse(converter.looksLikeWrongLayout("прошка"), "TextConverter must not convert words in UserDictionary")
    }

    func testUserDictionaryHelpers() {
        UserDictionary.shared.removeAll()
        defer { UserDictionary.shared.removeAll() }

        XCTAssertTrue(UserDictionary.shared.canLearn("новоеслово"))
        XCTAssertFalse(UserDictionary.shared.canLearn("а")) // single letter rejected
        XCTAssertFalse(UserDictionary.shared.canLearn("123")) // non-letters rejected

        XCTAssertTrue(UserDictionary.shared.learn("новоеслово"))
        XCTAssertFalse(UserDictionary.shared.canLearn("новоеслово")) // already learned
        XCTAssertEqual(UserDictionary.shared.learnedWordsList.first, "новоеслово")

        UserDictionary.shared.forget("новоеслово")
        XCTAssertFalse(UserDictionary.shared.contains("новоеслово"))
    }

    func testProgrammaticSwitchActiveWindow() {
        KeyboardLayoutDetector.lastProgrammaticSwitchTime = Date()
        XCTAssertTrue(KeyboardLayoutDetector.isProgrammaticSwitchActive)

        // Expired switch window
        KeyboardLayoutDetector.lastProgrammaticSwitchTime = Date().addingTimeInterval(-1.0)
        XCTAssertFalse(KeyboardLayoutDetector.isProgrammaticSwitchActive)

        KeyboardLayoutDetector.lastProgrammaticSwitchTime = nil
        XCTAssertFalse(KeyboardLayoutDetector.isProgrammaticSwitchActive)
    }

    func testTruncatedBufferPrefixReconciliationPreventsDoubleInitialLetter() {
        // When user types 'И' + 'егова', if layout switch resets buffer mid-word,
        // textBeforeWord will be 'И' and bufferedWord is 'егова'.
        let bufferedWord = "егова"
        let textBeforeWord = "И"

        var effectiveBufferedWord = bufferedWord
        var effectiveTextBeforeWord = textBeforeWord
        if let lastChar = effectiveTextBeforeWord.last, lastChar.isLetter || lastChar.isNumber {
            let missingPrefix = String(effectiveTextBeforeWord.reversed().prefix(while: { $0.isLetter || $0.isNumber }).reversed())
            effectiveTextBeforeWord = String(effectiveTextBeforeWord.dropLast(missingPrefix.count))
            effectiveBufferedWord = missingPrefix + effectiveBufferedWord
        }

        XCTAssertEqual(effectiveBufferedWord, "Иегова")
        XCTAssertEqual(effectiveTextBeforeWord, "")

        // Full word "Иегова" is valid Russian and must not be flagged as typo
        let typo = TypoCorrectionEngine.correctTypo(effectiveBufferedWord)
        XCTAssertNil(typo, "Valid word 'Иегова' must not be corrected as a typo")

        // In AutoCorrectionService, valid word in source language prevents layout conversion:
        let isSourceValid = SpellCheckService.shared.isValidWordInAnyLanguage(effectiveBufferedWord, languages: ["ru", "en"])
        XCTAssertTrue(isSourceValid, "'Иегова' is valid Russian, so layout conversion will be skipped")
    }

    func testEffectiveBackspaceCountProtectsPrecedingSpace() {
        // Case 1: Trailing space IS committed in the editor
        let textWithSpace = "у негго "
        let caretWithSpace = CFRange(location: (textWithSpace as NSString).length, length: 0)
        let count1 = AccessibilityService.effectiveBackspaceCount(text: textWithSpace, selection: caretWithSpace, expected: "негго ")
        XCTAssertEqual(count1, 6)
        XCTAssertFalse(AccessibilityService.isTailOfLargerWord(text: textWithSpace, selection: caretWithSpace, expected: "негго "))

        // Case 2: Trailing space is NOT yet committed in the editor (or delayed)
        // Backspaces must be adjusted to 5 so that the space between 'у' and 'негго' is NOT deleted!
        let textWithoutSpace = "у негго"
        let caretWithoutSpace = CFRange(location: (textWithoutSpace as NSString).length, length: 0)
        let count2 = AccessibilityService.effectiveBackspaceCount(text: textWithoutSpace, selection: caretWithoutSpace, expected: "негго ")
        XCTAssertEqual(count2, 5, "Must only delete 5 characters ('негго'), preserving the space after 'у' to avoid 'унего'")
        XCTAssertFalse(AccessibilityService.isTailOfLargerWord(text: textWithoutSpace, selection: caretWithoutSpace, expected: "негго "))

        // Case 3: Editor text has a preceding letter ('И' + 'егова') without trailing space
        let textWithLetterPrefix = "Иегова"
        let caretLetter = CFRange(location: (textWithLetterPrefix as NSString).length, length: 0)
        XCTAssertTrue(AccessibilityService.isTailOfLargerWord(text: textWithLetterPrefix, selection: caretLetter, expected: "егова "),
                      "Must detect 'егова' is a tail of 'Иегова' even when trailing space is not in editor")

        // Case 4: Text does not match at all -> nil (avoids corrupting text)
        let mismatchedText = "у другое"
        let caretMismatch = CFRange(location: (mismatchedText as NSString).length, length: 0)
        let count4 = AccessibilityService.effectiveBackspaceCount(text: mismatchedText, selection: caretMismatch, expected: "негго ")
        XCTAssertNil(count4, "Must return nil when editor matches neither full expected nor trimmed word")
    }

    @MainActor
    func testKeystrokeBufferingDuringActiveCorrection() {
        let settings = SettingsManager.shared
        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings)
        )

        let source = CGEventSource(stateID: .hidSystemState)
        guard let letterEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x27, keyDown: true),
              let cmdZEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x06, keyDown: true),
              let backspaceEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true),
              let escapeEvent = CGEvent(keyboardEventSource: source, virtualKey: 0x35, keyDown: true) else {
            XCTFail("Failed to create test CGEvents")
            return
        }
        cmdZEvent.flags = .maskCommand

        // 1. When correction is NOT active: handleEventDuringActiveCorrection returns false
        XCTAssertFalse(service.handleEventDuringActiveCorrection(letterEvent))

        // 2. Start a replacement session via internal begin (or performCheckedReplacement mock)
        // Simulate buffering directly
        service.bufferEventDuringCorrection(letterEvent)

        // 3. Command shortcut cancels correction and is not consumed
        let handledCmd = service.handleEventDuringActiveCorrection(cmdZEvent)
        XCTAssertFalse(handledCmd, "Command shortcut must not be consumed; must cancel correction and pass through")

        // 4. Backspace cancels correction and is not consumed
        service.bufferEventDuringCorrection(letterEvent)
        let handledBackspace = service.handleEventDuringActiveCorrection(backspaceEvent)
        XCTAssertFalse(handledBackspace, "Backspace must not be consumed; must cancel correction and pass through")

        // 5. Escape cancels correction and is not consumed
        service.bufferEventDuringCorrection(letterEvent)
        let handledEscape = service.handleEventDuringActiveCorrection(escapeEvent)
        XCTAssertFalse(handledEscape, "Escape must not be consumed; must cancel correction and pass through")

        // 6. Cancel and flush cleans up all buffers safely
        service.cancelActiveCorrectionAndFlush()
    }
}
