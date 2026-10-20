import XCTest
@testable import LangSwitcher

final class SpellCheckServiceTests: XCTestCase {
    
    var spellChecker: SpellCheckService!
    
    override func setUp() {
        super.setUp()
        spellChecker = SpellCheckService.shared
    }
    
    func testValidEnglishWords() {
        XCTAssertTrue(spellChecker.isValidWord("hello", language: "en"))
        XCTAssertTrue(spellChecker.isValidWord("keyboard", language: "en"))
        XCTAssertTrue(spellChecker.isValidWord("apple", language: "en"))
    }
    
    func testInvalidEnglishWords() {
        // "ghbdtn" is "привет" typed on US layout - not a valid English word
        XCTAssertFalse(spellChecker.isValidWord("ghbdtn", language: "en"))
        XCTAssertFalse(spellChecker.isValidWord("qwertyasdf", language: "en"))
    }
    
    func testValidRussianWords() {
        XCTAssertTrue(spellChecker.isValidWord("привет", language: "ru"))
        XCTAssertTrue(spellChecker.isValidWord("клавиатура", language: "ru"))
        XCTAssertTrue(spellChecker.isValidWord("яблоко", language: "ru"))
    }
    
    func testInvalidRussianWords() {
        // "руддщ" is "hello" typed on Russian layout - not a valid Russian word
        XCTAssertFalse(spellChecker.isValidWord("руддщ", language: "ru"))
        XCTAssertFalse(spellChecker.isValidWord("абвгдейканесуществующее", language: "ru"))
    }
    
    func testEmptyAndWhitespace() {
        XCTAssertFalse(spellChecker.isValidWord("", language: "en"))
        XCTAssertFalse(spellChecker.isValidWord("   ", language: "en"))
    }
    
    func testIsValidWordInAnyLanguage() {
        XCTAssertTrue(spellChecker.isValidWordInAnyLanguage("hello", languages: ["en", "ru"]))
        XCTAssertTrue(spellChecker.isValidWordInAnyLanguage("привет", languages: ["en", "ru"]))
        XCTAssertFalse(spellChecker.isValidWordInAnyLanguage("ghbdtn123xyz", languages: ["en", "ru"]))
    }
    
    func testCompletionsForPartialWord() {
        let completions = spellChecker.completions(forPartialWord: "hell", language: "en")
        XCTAssertFalse(completions.isEmpty, "Should find completions for 'hell' in English")
        XCTAssertTrue(completions.contains { $0.lowercased().hasPrefix("hell") })
    }
    
    func testLanguageNormalization() {
        XCTAssertEqual(spellChecker.normalizeLanguage("en-US"), "en")
        XCTAssertEqual(spellChecker.normalizeLanguage("en_GB"), "en")
        XCTAssertEqual(spellChecker.normalizeLanguage("ru-RU"), "ru")
        XCTAssertEqual(spellChecker.normalizeLanguage("uk_UA"), "uk")
        XCTAssertTrue(spellChecker.isValidWord("hello", language: "en-US"))
        XCTAssertTrue(spellChecker.isValidWord("привет", language: "ru-RU"))
    }
}
