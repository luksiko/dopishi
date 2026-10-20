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
    
    func testRussianLayoutIsNotTreatedAsUSInFamilyMatching() {
        // "russian" contains "us" as a substring.
        // Verify that Russian is NOT matched as US.
        let targetLower = "com.apple.keylayout.russianwin"
        let sourceLower = "com.apple.keylayout.us"
        
        let isTargetUS = !targetLower.contains("russian") && (targetLower.contains("us") || targetLower.contains("abc"))
        let isSourceUS = !sourceLower.contains("russian") && (sourceLower.contains("us") || sourceLower.contains("abc"))
        
        XCTAssertFalse(isTargetUS, "Russian layout must never match as US family")
        XCTAssertTrue(isSourceUS, "US layout must match as US family")
    }
    
    // MARK: - Status Bar Badge Renderer Tests
    
    func testStatusBarBadgeRendererLanguageCodeMapping() {
        // Supported layouts
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutRU), "RU")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutUS), "EN")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutUK), "UK")
        
        let layoutDE = KeyboardLayout(id: "com.apple.keylayout.German", localizedName: "German", languageCode: "de")
        let layoutFR = KeyboardLayout(id: "com.apple.keylayout.French", localizedName: "French", languageCode: "fr")
        let layoutES = KeyboardLayout(id: "com.apple.keylayout.Spanish", localizedName: "Spanish", languageCode: "es")
        let layoutABC = KeyboardLayout(id: "com.apple.keylayout.ABC", localizedName: "ABC", languageCode: "en")
        let layoutRussianWin = KeyboardLayout(id: "com.apple.keylayout.RussianWin", localizedName: "Russian - PC", languageCode: "ru")
        
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutDE), "DE")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutFR), "FR")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutES), "ES")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutABC), "EN")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: layoutRussianWin), "RU")
        
        // Critical: Russian contains "us" as substring, must resolve to RU and not EN
        let ruCode = StatusBarBadgeRenderer.languageCode(layoutId: "com.apple.keylayout.russian", languageCode: "unknown", localizedName: "Russian")
        XCTAssertEqual(ruCode, "RU")
        
        // Fallbacks
        let customWithLang = KeyboardLayout(id: "custom.italian", localizedName: "Italian", languageCode: "it-IT")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: customWithLang), "IT")
        
        let customWithName = KeyboardLayout(id: "custom.pl", localizedName: "Polski", languageCode: "unknown")
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: customWithName), "PO")
        
        // Nil layout fallback
        XCTAssertEqual(StatusBarBadgeRenderer.languageCode(for: nil), "EN")
    }
    
    func testStatusBarBadgeRendererRenderBadge() {
        let image = StatusBarBadgeRenderer.renderBadge(text: "RU")
        XCTAssertTrue(image.isTemplate, "Status bar badge image must be template for dark/light adaptation")
        XCTAssertEqual(image.size.height, 16.0)
        XCTAssertGreaterThanOrEqual(image.size.width, 24.0)
    }
    
    @MainActor
    func testStatusBarIconStyleSettings() {
        let badgeStyle = StatusBarIconStyle.languageBadge
        let keyboardStyle = StatusBarIconStyle.keyboardIcon
        
        XCTAssertFalse(badgeStyle.displayName.isEmpty)
        XCTAssertFalse(keyboardStyle.displayName.isEmpty)
        XCTAssertNotEqual(badgeStyle.displayName, keyboardStyle.displayName)
    }

    @MainActor
    func testLayoutSwitchModes() {
        XCTAssertEqual(LayoutSwitchMode.allCases.count, 4)
        XCTAssertEqual(LayoutSwitchMode.always.rawValue, 0)
        XCTAssertEqual(LayoutSwitchMode.ifLastWordConverted.rawValue, 1)
        XCTAssertEqual(LayoutSwitchMode.ifAnyWordConverted.rawValue, 2)
        XCTAssertEqual(LayoutSwitchMode.never.rawValue, 3)
        
        for mode in LayoutSwitchMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty)
            XCTAssertFalse(mode.description.isEmpty)
        }
    }
}
