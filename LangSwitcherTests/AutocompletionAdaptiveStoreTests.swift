import XCTest
@testable import LangSwitcher

@MainActor
final class AutocompletionAdaptiveStoreTests: XCTestCase {
    
    private var store: AutocompletionAdaptiveStore!
    
    override func setUp() async throws {
        try await super.setUp()
        store = AutocompletionAdaptiveStore.shared
        store.clearAll()
    }
    
    override func tearDown() async throws {
        store.clearAll()
        try await super.tearDown()
    }
    
    func testWordFrequencyTracking() {
        XCTAssertEqual(store.frequencyScore(for: "apple"), 0)
        
        store.recordWordUsage(word: "apple")
        XCTAssertEqual(store.frequencyScore(for: "apple"), 200)
        
        store.recordWordUsage(word: "apple")
        XCTAssertEqual(store.frequencyScore(for: "apple"), 400)
    }
    
    func testBigramBonusFromBuiltIn() {
        let bonus = store.bigramBonus(for: "день", after: "добрый")
        XCTAssertEqual(bonus, 800)
        
        let noBonus = store.bigramBonus(for: "слон", after: "добрый")
        XCTAssertEqual(noBonus, 0)
    }
    
    func testLearnedBigramBonus() {
        store.recordWordUsage(word: "swift", after: "hello")
        let bonus = store.bigramBonus(for: "swift", after: "hello")
        XCTAssertGreaterThanOrEqual(bonus, 600)
    }
    
    func testTopContinuations() {
        let ruContinuations = store.topContinuations(after: "добрый", limit: 3)
        XCTAssertTrue(ruContinuations.contains("день"))
        
        let enContinuations = store.topContinuations(after: "pull", limit: 2)
        XCTAssertTrue(enContinuations.contains("request"))
    }
    
    func testClearAll() {
        store.recordWordUsage(word: "test", after: "unit")
        XCTAssertGreaterThan(store.frequencyScore(for: "test"), 0)
        
        store.clearAll()
        XCTAssertEqual(store.frequencyScore(for: "test"), 0)
        XCTAssertEqual(store.bigramBonus(for: "test", after: "unit"), 0)
    }
}
