import XCTest
@testable import LangSwitcher

@MainActor
final class TypoCorrectionEngineTests: XCTestCase {

    func testExtraLetterTyposFromUserPrompt() {
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("большоей", languages: ["ru", "en"]), "большой")
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("поставитьл", languages: ["ru", "en"]), "поставить")
    }

    func testMissingLetterTyposFromUserPrompt() {
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("больой", languages: ["ru", "en"]), "большой")
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("исправлось", languages: ["ru", "en"]), "исправилось")
    }

    func testTransposedLetters() {
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("привте", languages: ["ru", "en"]), "привет")
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("Привте", languages: ["ru", "en"]), "Привет")
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("тчо", languages: ["ru", "en"]), "что")
    }

    func testDuplicateAndAdjacentKeyTypos() {
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("привеет", languages: ["ru", "en"]), "привет")
        XCTAssertEqual(TypoCorrectionEngine.correctTypo("привкт", languages: ["ru", "en"]), "привет")
    }

    func testValidWordsAreNeverModified() {
        XCTAssertNil(TypoCorrectionEngine.correctTypo("большой", languages: ["ru", "en"]))
        XCTAssertNil(TypoCorrectionEngine.correctTypo("поставить", languages: ["ru", "en"]))
        XCTAssertNil(TypoCorrectionEngine.correctTypo("привет", languages: ["ru", "en"]))
        XCTAssertNil(TypoCorrectionEngine.correctTypo("hello", languages: ["ru", "en"]))
    }

    func testAcronymsAndMixedCaseAreIgnored() {
        XCTAssertNil(TypoCorrectionEngine.correctTypo("СССР", languages: ["ru", "en"]))
        XCTAssertNil(TypoCorrectionEngine.correctTypo("API", languages: ["ru", "en"]))
        XCTAssertNil(TypoCorrectionEngine.correctTypo("macOS", languages: ["ru", "en"]))
    }

    func testKeyboardAdjacency() {
        XCTAssertTrue(TypoCorrectionEngine.areKeysAdjacent("ь", "л"))
        XCTAssertTrue(TypoCorrectionEngine.areKeysAdjacent("к", "е"))
        XCTAssertFalse(TypoCorrectionEngine.areKeysAdjacent("й", "ю"))
    }
}
