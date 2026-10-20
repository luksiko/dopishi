import XCTest
import AppKit
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
                             refresh: AutocompletionRefresh) -> AutoCorrectionService {
        let settings = SettingsManager.shared
        return AutoCorrectionService(settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings),
            overlayController: popup, ghostTextController: ghost, completionRefresh: refresh)
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
}
