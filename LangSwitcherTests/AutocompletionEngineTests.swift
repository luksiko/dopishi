import XCTest
import Carbon
@testable import LangSwitcher

@MainActor
final class AutocompletionEngineTests: XCTestCase {
    
    private var engine: AutocompletionEngine!
    private var enabledLayouts: [KeyboardLayout]!
    
    override func setUp() {
        super.setUp()
        engine = AutocompletionEngine()
        enabledLayouts = [
            KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en"),
            KeyboardLayout(id: "com.apple.keylayout.Russian", localizedName: "Russian", languageCode: "ru")
        ]
    }
    
    override func tearDown() {
        engine = nil
        enabledLayouts = nil
        super.tearDown()
    }
    
    func testSuggestReturnsPrefixMatchesInActiveLanguage() {
        let results = engine.suggest(
            for: "hel",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: enabledLayouts,
            maxSuggestions: 4,
            includeCrossLayout: false
        )
        
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: { $0.word.lowercased().hasPrefix("hel") }))
        XCTAssertFalse(results.first?.isCrossLayout ?? true)
    }
    
    func testSuggestShortPrefixReturnsEmpty() {
        let results = engine.suggest(
            for: "h",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: enabledLayouts
        )
        
        XCTAssertTrue(results.isEmpty)
    }
    
    func testSuggestCrossLayoutEnglishToRussian() {
        let results = engine.suggest(
            for: "ghbd",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: enabledLayouts,
            maxSuggestions: 4,
            includeCrossLayout: true
        )
        
        XCTAssertFalse(results.isEmpty)
        let candidate = results.first { $0.word.lowercased().hasPrefix("прив") }
        XCTAssertNotNil(candidate)
        XCTAssertTrue(candidate?.isCrossLayout ?? false)
        XCTAssertEqual(candidate?.targetLayoutID, "com.apple.keylayout.Russian")
    }
    
    func testSuggestCrossLayoutRussianToEnglish() {
        let results = engine.suggest(
            for: "рудд",
            activeLayoutID: "com.apple.keylayout.Russian",
            enabledLayouts: enabledLayouts,
            maxSuggestions: 4,
            includeCrossLayout: true
        )
        
        XCTAssertFalse(results.isEmpty)
        let candidate = results.first { $0.word.lowercased().hasPrefix("hell") }
        XCTAssertNotNil(candidate)
        XCTAssertTrue(candidate?.isCrossLayout ?? false)
        XCTAssertEqual(candidate?.targetLayoutID, "com.apple.keylayout.US")
    }
    
    func testSuggestRespectsCapitalization() {
        let results = engine.suggest(
            for: "Ghbd",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: enabledLayouts,
            maxSuggestions: 4,
            includeCrossLayout: true
        )
        
        XCTAssertFalse(results.isEmpty)
        let candidate = results.first { $0.word.lowercased().hasPrefix("прив") }
        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.word.first?.isUppercase, true)
    }
    
    func testSuggestMaxSuggestionsLimit() {
        let results = engine.suggest(
            for: "th",
            activeLayoutID: "com.apple.keylayout.US",
            enabledLayouts: enabledLayouts,
            maxSuggestions: 2,
            includeCrossLayout: false
        )
        
        XCTAssertLessThanOrEqual(results.count, 2)
    }
    
    func testAutocompletionAcceptKeyDefaultCodes() {
        XCTAssertEqual(AutocompletionAcceptKey.tab.defaultKeyCode, 0x30)
        XCTAssertEqual(AutocompletionAcceptKey.space.defaultKeyCode, 0x31)
        XCTAssertEqual(AutocompletionAcceptKey.enter.defaultKeyCode, 0x24)
        XCTAssertEqual(AutocompletionAcceptKey.rightArrow.defaultKeyCode, 0x7C)
    }
    
    func testSettingsManagerIsAcceptKey() {
        let settings = SettingsManager.shared
        
        // Tab
        settings.autoCompletionAcceptKey = .tab
        XCTAssertTrue(settings.isAutocompletionAcceptKey(keyCode: 0x30, flags: []))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x31, flags: []))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x30, flags: [.maskCommand]))
        
        // Space
        settings.autoCompletionAcceptKey = .space
        XCTAssertTrue(settings.isAutocompletionAcceptKey(keyCode: 0x31, flags: []))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x30, flags: []))
        
        // Enter
        settings.autoCompletionAcceptKey = .enter
        XCTAssertTrue(settings.isAutocompletionAcceptKey(keyCode: 0x24, flags: []))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x31, flags: []))
        
        // Right Arrow
        settings.autoCompletionAcceptKey = .rightArrow
        XCTAssertTrue(settings.isAutocompletionAcceptKey(keyCode: 0x7C, flags: []))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x7B, flags: []))
        
        // Custom Key (e.g. Option+Space)
        settings.autoCompletionAcceptKey = .custom
        settings.autoCompletionCustomKeyCode = 0x31 // Space
        settings.autoCompletionCustomModifiers = NSEvent.ModifierFlags.option.rawValue
        
        let optFlags: CGEventFlags = [.maskAlternate]
        XCTAssertTrue(settings.isAutocompletionAcceptKey(keyCode: 0x31, flags: optFlags))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x31, flags: []))
        XCTAssertFalse(settings.isAutocompletionAcceptKey(keyCode: 0x30, flags: optFlags))
    }
}
