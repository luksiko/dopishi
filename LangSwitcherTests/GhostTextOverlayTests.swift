import XCTest
import AppKit
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
    func testRepeatedOverlayResizingDoesNotEnterWindowConstraintLoop() {
        let ghost = GhostTextOverlayController()
        let popup = AutocompletionOverlayController()
        defer { ghost.hide(); popup.hide() }
        let caret = CGRect(x: 200, y: 300, width: 2, height: 16)
        for index in 0..<40 {
            let suffix = index.isMultiple(of: 2) ? "llo" : "longer completion"
            let candidate = AutocompletionCandidate(
                word: "he" + suffix, targetLayoutID: "com.apple.keylayout.US",
                isCrossLayout: false, score: 100
            )
            ghost.show(candidate: candidate, suffix: suffix, caretRect: caret)
            let candidates = (0..<(index % 4 + 1)).map { offset in
                AutocompletionCandidate(word: "completion" + String(offset),
                                        targetLayoutID: "com.apple.keylayout.US",
                                        isCrossLayout: false, score: 100 - offset)
            }
            popup.show(candidates: candidates,
                       caretRect: caret, acceptKeyHint: "Tab", onSelect: { _ in })
            // Existing tests only inspected controller state. Flush real AppKit
            // layout so repeated constraint invalidation also runs in regression tests.
            for window in NSApp.windows where window is NSPanel && window.isVisible {
                window.contentView?.layoutSubtreeIfNeeded()
                window.update()
                XCTAssertTrue(window.frame.width.isFinite)
                XCTAssertTrue(window.frame.height.isFinite)
                XCTAssertGreaterThan(window.frame.width, 0)
                XCTAssertGreaterThan(window.frame.height, 0)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            XCTAssertEqual(ghost.currentSuffix, suffix)
            XCTAssertEqual(popup.candidates.count, index % 4 + 1)
            if index.isMultiple(of: 3) { ghost.hide(); popup.hide() }
        }
    }

    func testCaretUsesPrimaryScreenOriginAndLastCharacterRightEdge() {
        let bounds = CGRect(x: 2400, y: -200, width: 12, height: 20)
        let caret = AccessibilityService.normalizedCaretBounds(bounds, primaryScreenMaxY: 900,
                                                              precedingCharacter: true)
        XCTAssertEqual(caret, CGRect(x: 2412, y: 1080, width: 1, height: 20))
        XCTAssertEqual(AccessibilityService.normalizedCaretBounds(
            CGRect(x: -500, y: 100, width: 0, height: 18), primaryScreenMaxY: 900,
            precedingCharacter: false), CGRect(x: -500, y: 782, width: 1, height: 18))
    }

    func testCaretRejectsWholeFieldAndInvalidBounds() {
        for bounds in [CGRect(x: 0, y: 0, width: 500, height: 300),
                       CGRect(x: 0, y: 0, width: 0, height: 0),
                       CGRect(x: 0, y: 0, width: 10, height: 400)] {
            XCTAssertNil(AccessibilityService.normalizedCaretBounds(bounds, primaryScreenMaxY: 900,
                                                                   precedingCharacter: false))
        }
    }

    func testPopupHidesWhenCaretCannotBeMeasured() {
        let popup = AutocompletionOverlayController()
        let candidate = AutocompletionCandidate(word: "hello", targetLayoutID: "com.apple.keylayout.US")
        popup.show(candidates: [candidate], caretRect: CGRect(x: 100, y: 200, width: 1, height: 18),
                   acceptKeyHint: "Tab", onSelect: { _ in })
        XCTAssertTrue(popup.isVisible)
        popup.show(candidates: [candidate], caretRect: nil, acceptKeyHint: "Tab", onSelect: { _ in })
        XCTAssertFalse(popup.isVisible)
        XCTAssertNil(popup.selectedCandidate)
    }

    func testMarkerCaretFallbackWhenStandardRangesAreUnavailable() {
        var standardQueried = false
        let rect = AccessibilityService.resolveCaretBounds(selectedRange: nil, primaryScreenMaxY: 900,
            rangeBounds: { _ in standardQueried = true; return nil },
            markerBounds: { CGRect(x: 100, y: 200, width: 0, height: 20) })
        XCTAssertFalse(standardQueried)
        XCTAssertEqual(rect, CGRect(x: 100, y: 680, width: 1, height: 20))
    }

    func testSelectedTextDoesNotBecomeGhostCaret() {
        let rect = AccessibilityService.resolveCaretBounds(selectedRange: CFRange(location: 5, length: 3),
            primaryScreenMaxY: 900, rangeBounds: { _ in XCTFail("Selection must not be queried"); return nil },
            markerBounds: { XCTFail("Selection must not fall back to a marker"); return nil })
        XCTAssertNil(rect)
    }

    func testPreviousCharacterIsUsedWhenCollapsedRangeIsUnsupported() {
        var lengths: [Int] = []
        let rect = AccessibilityService.resolveCaretBounds(selectedRange: CFRange(location: 5, length: 0),
            primaryScreenMaxY: 900, rangeBounds: { range in
                lengths.append(range.length)
                return range.length == 0 ? nil : CGRect(x: 100, y: 200, width: 10, height: 20)
            }, markerBounds: { XCTFail("Standard bounds take priority"); return nil })
        XCTAssertEqual(lengths, [0, 1])
        XCTAssertEqual(rect?.minX, 110)
    }

    func testWideMarkerBoundsAreNotTreatedAsAnInsertionPoint() {
        XCTAssertNil(AccessibilityService.resolveCaretBounds(selectedRange: nil, primaryScreenMaxY: 900,
            rangeBounds: { _ in nil }, markerBounds: { CGRect(x: 100, y: 200, width: 60, height: 20) }))
    }

}


extension GhostTextOverlayTests {
    func testContinuationRecoversWhenCaretTemporarilyUnavailable() async throws {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }
        let candidate = AutocompletionCandidate(word: "are you", targetLayoutID: "com.apple.keylayout.US")
        var calls = 0
        ghost.showContinuation(candidate: candidate, suffix: "are you", caretProvider: {
            calls += 1
            return calls == 1 ? nil : CGRect(x: 100, y: 200, width: 1, height: 18)
        }, isCurrent: { true })
        XCTAssertFalse(ghost.isVisible)
        XCTAssertEqual(ghost.currentCandidate, candidate)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(ghost.isVisible)
        XCTAssertEqual(ghost.currentSuffix, "are you")
    }

    func testDismissalCancelsPendingContinuationPresentation() async throws {
        let ghost = GhostTextOverlayController()
        var calls = 0
        ghost.showContinuation(candidate: AutocompletionCandidate(word: "next", targetLayoutID: "com.apple.keylayout.US"),
            suffix: "next", caretProvider: { calls += 1; return nil }, isCurrent: { true })
        ghost.hide()
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(ghost.currentCandidate)
        XCTAssertFalse(ghost.isVisible)
    }

    func testFieldChangeDiscardsPendingContinuation() async throws {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }
        var current = true
        ghost.showContinuation(candidate: AutocompletionCandidate(word: "next", targetLayoutID: "com.apple.keylayout.US"),
            suffix: "next", caretProvider: { nil }, isCurrent: { current })
        current = false
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(ghost.currentCandidate)
        XCTAssertFalse(ghost.isVisible)
    }
}
