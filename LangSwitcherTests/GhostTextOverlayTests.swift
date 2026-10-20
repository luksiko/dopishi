import XCTest
@testable import LangSwitcher

@MainActor
final class GhostTextOverlayTests: XCTestCase {
    
    func testDisplayModeValues() {
        XCTAssertEqual(AutocompletionDisplayMode.popup.rawValue, 0)
        XCTAssertEqual(AutocompletionDisplayMode.ghostText.rawValue, 1)
        XCTAssertEqual(AutocompletionDisplayMode.both.rawValue, 2)
        
        XCTAssertFalse(AutocompletionDisplayMode.popup.displayName.isEmpty)
        XCTAssertFalse(AutocompletionDisplayMode.ghostText.displayName.isEmpty)
        XCTAssertFalse(AutocompletionDisplayMode.both.displayName.isEmpty)
    }
    
    func testGhostTextOverlayControllerState() {
        let controller = GhostTextOverlayController()
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(controller.currentSuffix, "")
        XCTAssertNil(controller.currentCandidate)
        
        let candidate = AutocompletionCandidate(
            word: "привет",
            targetLayoutID: "com.apple.keylayout.Russian",
            isCrossLayout: false,
            score: 100
        )
        
        let dummyRect = CGRect(x: 100, y: 100, width: 2, height: 16)
        controller.show(candidate: candidate, suffix: "ивет", caretRect: dummyRect)
        
        XCTAssertEqual(controller.currentSuffix, "ивет")
        XCTAssertEqual(controller.currentCandidate?.word, "привет")
        
        controller.hide()
        XCTAssertEqual(controller.currentSuffix, "")
        XCTAssertNil(controller.currentCandidate)
    }
    
    func testExcludedAppsSettings() {
        let settings = SettingsManager.shared
        let testID = "com.example.TestExcludedApp"
        
        settings.removeExcludedApp(bundleID: testID)
        XCTAssertFalse(settings.isAppExcluded(bundleID: testID))
        
        settings.addExcludedApp(bundleID: testID)
        XCTAssertTrue(settings.isAppExcluded(bundleID: testID))
        
        settings.removeExcludedApp(bundleID: testID)
        XCTAssertFalse(settings.isAppExcluded(bundleID: testID))
    }
}
