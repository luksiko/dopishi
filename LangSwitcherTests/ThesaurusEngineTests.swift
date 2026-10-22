import XCTest
@testable import LangSwitcher

final class ThesaurusEngineTests: XCTestCase {

    func testRussianSynonymsLower() {
        let results = ThesaurusEngine.suggest(word: "быстрый")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains("скорый"))
        XCTAssertTrue(results.contains("оперативный"))
    }

    func testRussianSynonymsCapitalized() {
        let results = ThesaurusEngine.suggest(word: "Быстрый")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains("Скорый"))
        XCTAssertTrue(results.contains("Оперативный"))
    }

    func testRussianSynonymsAllUpper() {
        let results = ThesaurusEngine.suggest(word: "БЫСТРЫЙ")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains("СКОРЫЙ"))
        XCTAssertTrue(results.contains("ОПЕРАТИВНЫЙ"))
    }

    func testEnglishSynonyms() {
        let results = ThesaurusEngine.suggest(word: "fast")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains("quick"))

        let capitalized = ThesaurusEngine.suggest(word: "Important")
        XCTAssertTrue(capitalized.contains("Crucial"))
    }

    func testNumberedCandidates() {
        let candidates = ThesaurusEngine.candidates(for: "важный", limit: 3)
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates[0].shortcut, "1")
        XCTAssertEqual(candidates[1].shortcut, "2")
        XCTAssertEqual(candidates[2].shortcut, "3")
        XCTAssertEqual(candidates[0].synonym, "значимый")
    }

    func testUnknownWord() {
        let results = ThesaurusEngine.suggest(word: "qwerty_unknown_word_xyz")
        XCTAssertTrue(results.isEmpty)
    }
}
