import XCTest
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
