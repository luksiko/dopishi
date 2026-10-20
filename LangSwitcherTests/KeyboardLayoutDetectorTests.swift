import XCTest
@testable import LangSwitcher

final class KeyboardLayoutDetectorTests: XCTestCase {
    
    let layoutUS = KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en")
    let layoutRU = KeyboardLayout(id: "com.apple.keylayout.Russian", localizedName: "Russian", languageCode: "ru")
    let layoutUK = KeyboardLayout(id: "com.apple.keylayout.Ukrainian", localizedName: "Ukrainian", languageCode: "uk")
    
    func testNextLayoutTwoLayoutsToggle() {
        let layouts = [layoutUS, layoutRU]
        
        // From US -> RU
        let nextFromUS = KeyboardLayoutDetector.nextLayout(
            currentID: layoutUS.id,
            among: layouts
        )
        XCTAssertEqual(nextFromUS?.id, layoutRU.id)
        
        // From RU -> US
        let nextFromRU = KeyboardLayoutDetector.nextLayout(
            currentID: layoutRU.id,
            among: layouts
        )
        XCTAssertEqual(nextFromRU?.id, layoutUS.id)
    }
    
    func testNextLayoutThreeLayoutsCycle() {
        let layouts = [layoutUS, layoutRU, layoutUK]
        
        let afterUS = KeyboardLayoutDetector.nextLayout(currentID: layoutUS.id, among: layouts)
        XCTAssertEqual(afterUS?.id, layoutRU.id)
        
        let afterRU = KeyboardLayoutDetector.nextLayout(currentID: layoutRU.id, among: layouts)
        XCTAssertEqual(afterRU?.id, layoutUK.id)
        
        let afterUK = KeyboardLayoutDetector.nextLayout(currentID: layoutUK.id, among: layouts)
        XCTAssertEqual(afterUK?.id, layoutUS.id)
    }
    
    func testNextLayoutCurrentUnknownDefaultsToFirst() {
        let layouts = [layoutUS, layoutRU]
        
        let next = KeyboardLayoutDetector.nextLayout(
            currentID: "com.apple.keylayout.Unknown",
            among: layouts
        )
        XCTAssertEqual(next?.id, layoutUS.id, "When current layout is unknown, cycle should start at first layout")
    }
    
    func testNextLayoutLanguageCodeFallback() {
        let layouts = [layoutUS, layoutRU]
        
        // Current has a slightly different ID but matching language code "ru"
        let next = KeyboardLayoutDetector.nextLayout(
            currentID: "com.apple.keylayout.Russian-PC",
            currentLanguageCode: "ru",
            among: layouts
        )
        XCTAssertEqual(next?.id, layoutUS.id)
    }
    
    func testNextLayoutSingleLayoutReturnsNil() {
        let layouts = [layoutUS]
        let next = KeyboardLayoutDetector.nextLayout(currentID: layoutUS.id, among: layouts)
        XCTAssertNil(next, "Single layout cannot be switched")
    }
    
    func testNextLayoutEmptyListReturnsNil() {
        let next = KeyboardLayoutDetector.nextLayout(currentID: layoutUS.id, among: [])
        XCTAssertNil(next)
    }
}
