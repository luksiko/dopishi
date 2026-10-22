import XCTest
@testable import LangSwitcher

final class WordAlternativesEngineTests: XCTestCase {

    func testDerivesAlternativesExcludingCurrent() {
        let current = "привет"
        let allCandidates = ["привет", "приветствую", "приветствие", "приветик", "привет"]

        let alts = WordAlternativesEngine.alternatives(currentSuggestion: current, candidates: allCandidates, limit: 3)

        XCTAssertEqual(alts.count, 3)
        XCTAssertEqual(alts[0].text, "приветствую")
        XCTAssertEqual(alts[0].shortcut, "1")
        XCTAssertEqual(alts[1].text, "приветствие")
        XCTAssertEqual(alts[1].shortcut, "2")
        XCTAssertEqual(alts[2].text, "приветик")
        XCTAssertEqual(alts[2].shortcut, "3")
        XCTAssertFalse(alts.contains(where: { $0.text == current }))
    }

    func testCaseInsensitiveFilter() {
        let current = "Hello"
        let allCandidates = ["hello", "help", "helicopter"]

        let alts = WordAlternativesEngine.alternatives(currentSuggestion: current, candidates: allCandidates, limit: 2)

        XCTAssertEqual(alts.count, 2)
        XCTAssertEqual(alts[0].text, "help")
        XCTAssertEqual(alts[1].text, "helicopter")
    }

    func testEmptyWhenNoOtherCandidates() {
        let current = "привет"
        let allCandidates = ["привет", "Привет", " "]

        let alts = WordAlternativesEngine.alternatives(currentSuggestion: current, candidates: allCandidates)
        XCTAssertTrue(alts.isEmpty)
    }
}
