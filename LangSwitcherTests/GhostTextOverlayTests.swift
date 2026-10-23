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


extension GhostTextOverlayTests {
    func testLineWrapKeepsValidInsertionBoundsOnTheNewLine() {
        let rect = AccessibilityService.resolveCaretBounds(selectedRange: CFRange(location: 10, length: 0),
            primaryScreenMaxY: 200, rangeBounds: { range in
                range.length == 0 ? CGRect(x: 10, y: 80, width: 1, height: 15)
                    : CGRect(x: 50, y: 100, width: 8, height: 15)
            }, markerBounds: { nil })
        XCTAssertEqual(rect, CGRect(x: 10, y: 105, width: 1, height: 15))
    }

    func testFieldAnchorRemainsOnLeftMonitor() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let frame = FieldAnchorOverlayController.badgeFrame(
            fieldRect: CGRect(x: -1800, y: 200, width: 500, height: 100), visibleFrame: screen)
        XCTAssertEqual(frame.minX, -1828)
        XCTAssertEqual(frame.maxX, -1806)
        XCTAssertTrue(screen.contains(frame))
    }

    func testFieldAnchorPositionedOutsideFieldToAvoidCoveringText() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let field = CGRect(x: 100, y: 500, width: 400, height: 40)
        let frame = FieldAnchorOverlayController.badgeFrame(fieldRect: field, visibleFrame: screen)
        // Badge must be strictly to the left of the field to avoid overlapping text
        XCTAssertLessThanOrEqual(frame.maxX, field.minX)
        XCTAssertEqual(frame.maxX, field.minX - 6)
    }

    func testFieldAnchorHideCannotUndoImmediateReshow() async throws {
        let anchor = FieldAnchorOverlayController()
        defer { anchor.hide() }
        anchor.show(fieldRect: CGRect(x: 100, y: 200, width: 500, height: 100))
        anchor.hide()
        XCTAssertFalse(anchor.isVisible)
        anchor.show(fieldRect: CGRect(x: 150, y: 220, width: 500, height: 100))
        try await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertTrue(anchor.isVisible)
    }

    func testTelegramCaretAdjustedDownwardsForContainerPadding() {
        let rawCaret = CGRect(x: 500, y: 400, width: 1, height: 16)
        let adjusted = AccessibilityService.adjustCaretForApp(caret: rawCaret, bundleID: "ru.keepcoder.Telegram")
        // In Telegram, input container padding and baseline offset is 18 points downwards (smaller Y in Cocoa)
        XCTAssertEqual(adjusted.origin.x, 500)
        XCTAssertEqual(adjusted.origin.y, 400 - 18)
        XCTAssertEqual(adjusted.width, 1)
        XCTAssertEqual(adjusted.height, 16)
    }

    func testNonTelegramCaretRemainsUnchanged() {
        let rawCaret = CGRect(x: 500, y: 400, width: 1, height: 16)
        let chrome = AccessibilityService.adjustCaretForApp(caret: rawCaret, bundleID: "com.google.Chrome")
        XCTAssertEqual(chrome, rawCaret)
        let vscode = AccessibilityService.adjustCaretForApp(caret: rawCaret, bundleID: "com.microsoft.VSCode")
        XCTAssertEqual(vscode, rawCaret)
        let none = AccessibilityService.adjustCaretForApp(caret: rawCaret, bundleID: nil)
        XCTAssertEqual(none, rawCaret)
    }

    func testSmartPasteAppDetection() {
        XCTAssertTrue(AccessibilityService.isSmartPasteApp(bundleID: "com.microsoft.Word"))
        XCTAssertTrue(AccessibilityService.isSmartPasteApp(bundleID: "com.microsoft.Powerpoint"))
        XCTAssertTrue(AccessibilityService.isSmartPasteApp(bundleID: "com.microsoft.Outlook"))
        XCTAssertTrue(AccessibilityService.isSmartPasteApp(bundleID: "com.microsoft.Excel"))
        XCTAssertTrue(AccessibilityService.isSmartPasteApp(bundleID: "com.microsoft.onenote.mac"))

        XCTAssertFalse(AccessibilityService.isSmartPasteApp(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(AccessibilityService.isSmartPasteApp(bundleID: "com.google.Chrome"))
        XCTAssertFalse(AccessibilityService.isSmartPasteApp(bundleID: "com.apple.dt.Xcode"))
        XCTAssertFalse(AccessibilityService.isSmartPasteApp(bundleID: "com.apple.TextEdit"))
        XCTAssertFalse(AccessibilityService.isSmartPasteApp(bundleID: nil))
    }

    func testFieldAnchorContextStateUpdates() {
        let anchor = FieldAnchorOverlayController()
        defer { anchor.hide() }
        
        anchor.show(fieldRect: CGRect(x: 100, y: 200, width: 500, height: 100))
        XCTAssertFalse(anchor.hasScreenContext)
        XCTAssertFalse(anchor.hasPendingQuestion)
        
        anchor.updateContextState(hasScreenContext: true, hasPendingQuestion: false)
        XCTAssertTrue(anchor.hasScreenContext)
        XCTAssertFalse(anchor.hasPendingQuestion)
        
        anchor.updateContextState(hasScreenContext: true, hasPendingQuestion: true)
        XCTAssertTrue(anchor.hasScreenContext)
        XCTAssertTrue(anchor.hasPendingQuestion)
        
        anchor.hide()
        XCTAssertFalse(anchor.hasScreenContext)
        XCTAssertFalse(anchor.hasPendingQuestion)
    }

    func testAutocompletionCandidateHasScreenContext() {
        let regular = AutocompletionCandidate(
            word: "привет",
            targetLayoutID: "com.apple.keylayout.Russian"
        )
        XCTAssertFalse(regular.hasScreenContext)
        
        let contextual = AutocompletionCandidate(
            word: "да, конечно",
            targetLayoutID: "com.apple.keylayout.Russian",
            hasScreenContext: true
        )
        XCTAssertTrue(contextual.hasScreenContext)
    }
}

// MARK: - Ghost Text Stability Tests
extension GhostTextOverlayTests {
    private func makeService(
        popup: AutocompletionOverlayController? = nil,
        ghost: GhostTextOverlayController? = nil
    ) -> (service: AutoCorrectionService, ghost: GhostTextOverlayController, popup: AutocompletionOverlayController) {
        let settings = SettingsManager.shared
        let p = popup ?? AutocompletionOverlayController()
        let g = ghost ?? GhostTextOverlayController()
        let service = AutoCorrectionService(
            settingsManager: settings,
            textConverter: TextConverter(settingsManager: settings),
            overlayController: p,
            ghostTextController: g,
            completionRefresh: AutocompletionRefresh()
        )
        return (service, g, p)
    }

    func testGeometryAnchoredAtCaret() {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let caret = CGRect(x: screen.maxX - 60, y: screen.midY, width: 2, height: 16)
        let candidate = AutocompletionCandidate(word: "very long candidate phrase that exceeds the visible screen bounds", targetLayoutID: "com.apple.keylayout.US")
        
        ghost.show(candidate: candidate, suffix: "very long candidate phrase that exceeds the visible screen bounds", caretRect: caret)
        
        XCTAssertTrue(ghost.isVisible)
        guard let frame = ghost.panelFrame else {
            XCTFail("panelFrame should exist")
            return
        }
        
        // Origin.x must be anchored strictly to caret.maxX, never shifted leftwards
        XCTAssertEqual(frame.origin.x, caret.maxX)
        // Panel width must be clamped so frame does not overflow visible screen
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX)
        // Full unclipped suffix is preserved in controller state
        XCTAssertEqual(ghost.currentSuffix, "very long candidate phrase that exceeds the visible screen bounds")
    }

    func testStaleRequestDoesNotDismissNewSuggestion() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req1 = UUID()
        let req2 = UUID()
        
        // Present suggestion for req2 (the newer request)
        service.presentAIPrediction(
            suffix: "newer completion",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req2,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertEqual(service.activeGhostState?.requestId, req2)
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "newer completion")
        XCTAssertEqual(ghost.currentSuffix, "newer completion")
        
        // Stale late response from req1 arrives
        service.presentAIPrediction(
            suffix: "stale completion",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req1,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        // Must NOT overwrite req2
        XCTAssertEqual(service.activeGhostState?.requestId, req2)
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "newer completion")
        XCTAssertEqual(ghost.currentSuffix, "newer completion")
    }

    func testFieldSwitchInvalidatesGhost() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req = UUID()
        service.presentAIPrediction(
            suffix: "test phrase",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertNotNil(service.activeGhostState)
        XCTAssertTrue(ghost.isVisible)
        
        // Mouse click outside popup immediately invalidates ghost text
        service.handleMouseDown()
        
        XCTAssertNil(service.activeGhostState)
        XCTAssertFalse(ghost.isVisible)
        XCTAssertEqual(ghost.currentSuffix, "")
    }

    func testTypeAheadLettersSpacesPunctuation() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req = UUID()
        service.presentAIPrediction(
            suffix: "hello world, 123",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "hello world, 123")
        
        // 1. Letters: 'h'
        let matchedH = service.handleTypeAhead(char: "h")
        XCTAssertTrue(matchedH)
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "ello world, 123")
        XCTAssertEqual(ghost.currentSuffix, "ello world, 123")
        
        for c in "ello" {
            XCTAssertTrue(service.handleTypeAhead(char: c))
        }
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, " world, 123")
        
        // 2. Space
        XCTAssertTrue(service.handleTypeAhead(char: " "))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "world, 123")
        
        for c in "world" {
            XCTAssertTrue(service.handleTypeAhead(char: c))
        }
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, ", 123")
        
        // 3. Punctuation: ','
        XCTAssertTrue(service.handleTypeAhead(char: ","))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, " 123")
        
        // 4. Space
        XCTAssertTrue(service.handleTypeAhead(char: " "))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "123")
        
        // 5. Digits: '1'
        XCTAssertTrue(service.handleTypeAhead(char: "1"))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "23")
        
        // 6. Mismatch: 'z'
        let mismatch = service.handleTypeAhead(char: "z")
        XCTAssertFalse(mismatch)
        XCTAssertNil(service.activeGhostState)
        XCTAssertFalse(ghost.isVisible)
    }

    func testTypeAheadCaseInsensitive() {
        let (service, _, _) = makeService()
        defer { service.stop() }

        let req = UUID()
        service.presentAIPrediction(
            suffix: "Hello World",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )

        // Lowercase 'h' matching capital 'H'
        XCTAssertTrue(service.handleTypeAhead(char: "h"))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "ello World")

        // Capital 'E' matching lowercase 'e'
        XCTAssertTrue(service.handleTypeAhead(char: "E"))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "llo World")
    }

    func testEscapeDuringStreamCancelsPermanently() throws {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req = UUID()
        service.presentAIPrediction(
            suffix: "initial token",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertNotNil(service.activeGhostState)
        XCTAssertTrue(ghost.isVisible)
        
        // Simulate Escape key press (virtualKey 0x35)
        let escEvent = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true))
        escEvent.flags = []
        let intercepted = service.interceptKeyIfOverlayVisible(event: escEvent)
        XCTAssertTrue(intercepted, "Escape must be intercepted and consumed")
        
        XCTAssertNil(service.activeGhostState)
        XCTAssertFalse(ghost.isVisible)
        
        // Subsequent token arrives from the cancelled stream
        service.presentAIPrediction(
            suffix: "initial token and more words",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        // Must remain cancelled and suppressed
        XCTAssertNil(service.activeGhostState)
        XCTAssertFalse(ghost.isVisible)
    }

    func testPrefixInvarianceEnforced() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req = UUID()
        // 1. Initial prediction
        service.presentAIPrediction(
            suffix: "приложение для macOS",
            activeLayoutID: "com.apple.keylayout.Russian",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "приложение для macOS")
        XCTAssertEqual(ghost.currentSuffix, "приложение для macOS")
        
        // 2. Valid continuation extending the prefix
        service.presentAIPrediction(
            suffix: "приложение для macOS и iOS",
            activeLayoutID: "com.apple.keylayout.Russian",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "приложение для macOS и iOS")
        XCTAssertEqual(ghost.currentSuffix, "приложение для macOS и iOS")
        
        // 3. Divergent continuation (does not start with already shown prefix)
        service.presentAIPrediction(
            suffix: "программа для Windows",
            activeLayoutID: "com.apple.keylayout.Russian",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        // Divergence discarded: original prefix preserved!
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "приложение для macOS и iOS")
        XCTAssertEqual(ghost.currentSuffix, "приложение для macOS и iOS")
    }

    func testBackgroundExtensionPrefixInvariance() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req1 = UUID()
        service.presentAIPrediction(
            suffix: "world is great",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req1,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "world is great")
        
        // Background extension arrives under a NEW requestId (req2)
        let req2 = UUID()
        service.currentAIRequestId = req2
        
        // 1. Extension that diverges from visible text -> MUST BE DISCARDED
        service.presentAIPrediction(
            suffix: "completely different sentence",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req2,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "world is great")
        XCTAssertEqual(ghost.currentSuffix, "world is great")
        
        // 2. Extension that starts with visible text -> ACCEPTED
        service.presentAIPrediction(
            suffix: "world is great and beautiful",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req2,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "world is great and beautiful")
        XCTAssertEqual(ghost.currentSuffix, "world is great and beautiful")
    }

    func testTypeAheadWithLeadingWhitespaceNormalization() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }
        
        let req = UUID()
        // Stream chunk 1 arrives without leading space (trimmed because buffer was empty)
        service.presentAIPrediction(
            suffix: "world",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            initialBuffer: "",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "world")
        
        // User types 'w'
        XCTAssertTrue(service.handleTypeAhead(char: "w"))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "orld")
        
        // Stream chunk 2 arrives with leading space from the model: " world and more"
        service.presentAIPrediction(
            suffix: " world and more",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )
        
        // Must NOT be discarded as divergence! Should drop typed 'w' and extend to "orld and more"
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "orld and more")
        XCTAssertEqual(ghost.currentSuffix, "orld and more")
    }

    func testTypeAheadTabAcceptanceTextIntegrity() {
        // Test that PhraseAcceptancePlan correctly produces remaining suffix after typing
        // Scenario 1: User typed 'h' from "hello world"
        let plan1 = PhraseAcceptancePlan(buffer: "h", continuationAnchor: nil, insertion: "hello world")
        XCTAssertEqual(plan1.expected, "h")
        XCTAssertEqual(plan1.replacement, "hello world")
        XCTAssertEqual(plan1.appendingSuffix, "ello world")
        
        // Scenario 2: User typed through a space: "hello " -> wordBuffer is "", remainingSuffix is "world"
        let plan2 = PhraseAcceptancePlan(buffer: "", continuationAnchor: nil, insertion: "world")
        XCTAssertEqual(plan2.expected, "")
        XCTAssertEqual(plan2.replacement, "world")
        XCTAssertEqual(plan2.appendingSuffix, "world")
        
        // Scenario 3: Continuation anchor with subsequent word
        let plan3 = PhraseAcceptancePlan(buffer: "", continuationAnchor: "hello", insertion: "world")
        XCTAssertEqual(plan3.expected, "hello")
        XCTAssertEqual(plan3.replacement, "hello world")
        XCTAssertEqual(plan3.appendingSuffix, " world")
    }

    func testStaleFailedRequestDoesNotDismissNewSuggestion() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }

        let req1 = UUID()
        let req2 = UUID()

        // req2 is the current active request and displays a suggestion
        service.currentAIRequestId = req2
        service.presentAIPrediction(
            suffix: "active suggestion",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req2,
            fieldIdentifier: "field:2",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )

        XCTAssertEqual(service.activeGhostState?.requestId, req2)
        XCTAssertEqual(ghost.currentSuffix, "active suggestion")

        // Now an older request (req1 from field:1) fails or returns nil.
        // It must NOT dismiss req2's suggestion.
        // Simulate what happens in scheduleAIDebounce:
        if service.currentAIRequestId == req1 {
            service.dismissSuggestionsOnly()
        }

        XCTAssertEqual(service.activeGhostState?.requestId, req2)
        XCTAssertEqual(ghost.currentSuffix, "active suggestion")
    }

    func testTypeAheadPreservedAfterPartialPhraseAcceptance() {
        let (service, ghost, _) = makeService()
        defer { service.stop() }

        let req = UUID()
        service.currentAIRequestId = req
        service.presentAIPrediction(
            suffix: "hello beautiful world",
            activeLayoutID: "com.apple.keylayout.US",
            requestId: req,
            fieldIdentifier: "field:1",
            caretRect: CGRect(x: 100, y: 200, width: 2, height: 16)
        )

        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "hello beautiful world")

        // Simulate acceptCandidate word-by-word (first word "hello" accepted, remainder " beautiful world")
        let continuationRequestId = UUID()
        service.currentAIRequestId = continuationRequestId
        service.activeGhostState = ActiveGhostState(
            requestId: continuationRequestId,
            initialBuffer: "",
            remainingSuffix: " beautiful world",
            fullCompletionText: " beautiful world",
            fieldIdentifier: "field:1",
            suggestionTarget: nil,
            caretRect: CGRect(x: 150, y: 200, width: 2, height: 16),
            creationDate: Date()
        )
        ghost.show(candidate: AutocompletionCandidate(word: " beautiful world", targetLayoutID: "com.apple.keylayout.US"),
                   suffix: " beautiful world", caretRect: CGRect(x: 150, y: 200, width: 2, height: 16))

        // User now presses Space
        XCTAssertTrue(service.handleTypeAhead(char: " "))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "beautiful world")
        XCTAssertEqual(ghost.currentSuffix, "beautiful world")

        // User now presses 'b'
        XCTAssertTrue(service.handleTypeAhead(char: "b"))
        XCTAssertEqual(service.activeGhostState?.remainingSuffix, "eautiful world")
        XCTAssertEqual(ghost.currentSuffix, "eautiful world")
    }

    func testCaretStabilizationDoesNotJumpBackwardsOnStaleAnchor() async throws {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }

        let candidate = AutocompletionCandidate(word: "world", targetLayoutID: "com.apple.keylayout.US")
        let initialAnchor = CGRect(x: 100, y: 200, width: 2, height: 16)
        ghost.show(candidate: candidate, suffix: "orld", caretRect: initialAnchor)

        XCTAssertTrue(ghost.isVisible)
        XCTAssertEqual(ghost.lastCaretRect, initialAnchor)
        let initialX = ghost.panelFrame?.origin.x ?? 0
        XCTAssertEqual(initialX, 102, accuracy: 0.5)

        // Simulate keystroke: AX still reports initialAnchor (stale) for 1 call, then advances to x: 108
        var pollCalls = 0
        let freshAnchor = CGRect(x: 108, y: 200, width: 2, height: 16)
        ghost.show(candidate: candidate, suffix: "rld", caretRect: initialAnchor, caretProvider: {
            pollCalls += 1
            return pollCalls == 1 ? initialAnchor : freshAnchor
        })

        // Suffix updated immediately in text view without moving panel backwards
        XCTAssertEqual(ghost.currentSuffix, "rld")

        // Wait for poll task to resolve fresh anchor
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(ghost.lastCaretRect, freshAnchor)
        let resolvedX = ghost.panelFrame?.origin.x ?? 0
        XCTAssertEqual(resolvedX, 110, accuracy: 0.5)
    }

    func testCaretStabilizationResolvesWhenInitialCaretIsNil() async throws {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }

        let candidate = AutocompletionCandidate(word: "smooth", targetLayoutID: "com.apple.keylayout.US")
        let targetAnchor = CGRect(x: 150, y: 300, width: 2, height: 16)
        var pollCalls = 0

        ghost.show(candidate: candidate, suffix: "mooth", caretRect: nil, caretProvider: {
            pollCalls += 1
            return pollCalls > 1 ? targetAnchor : nil
        })

        XCTAssertFalse(ghost.isVisible)

        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(ghost.isVisible)
        XCTAssertEqual(ghost.lastCaretRect, targetAnchor)
        XCTAssertEqual(ghost.panelFrame?.origin.x ?? 0, 152, accuracy: 0.5)
    }

    func testHideCancelsActiveCaretStabilizationPoll() async throws {
        let ghost = GhostTextOverlayController()
        let candidate = AutocompletionCandidate(word: "cancel", targetLayoutID: "com.apple.keylayout.US")

        var pollCalls = 0
        ghost.show(candidate: candidate, suffix: "ancel", caretRect: nil, caretProvider: {
            pollCalls += 1
            return nil
        })

        ghost.hide()
        XCTAssertNil(ghost.pendingCaretAnchor)
        XCTAssertFalse(ghost.isVisible)

        try await Task.sleep(nanoseconds: 50_000_000)
        let finalCalls = pollCalls
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(pollCalls, finalCalls, "Poll task should have ceased execution after hide()")
    }

    // MARK: - Interactive Sandbox CustomDemoNSTextView Tests

    func testCustomDemoNSTextViewAttributesAndFocus() {
        let textView = CustomDemoNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        XCTAssertTrue(textView.isEditable, "Demo sandbox text view must be editable")
        XCTAssertTrue(textView.isSelectable, "Demo sandbox text view must be selectable")
        XCTAssertTrue(textView.acceptsFirstResponder, "Demo sandbox text view must accept first responder")
        XCTAssertFalse(textView.drawsBackground, "Background drawing should be disabled for SwiftUI container styling")
        XCTAssertEqual(textView.textContainer?.maximumNumberOfLines, 1, "Must be single line")
    }

    func testCustomDemoNSTextViewTabInterception() {
        let textView = CustomDemoNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        var tabCount = 0
        textView.onTab = {
            tabCount += 1
        }

        // When ghostText is empty, insertTab should not trigger onTab
        textView.ghostText = ""
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(tabCount, 0, "Tab should not trigger completion when ghost text is empty")

        // When ghostText is present, insertTab must trigger onTab
        textView.ghostText = "ет! Как дела?"
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(tabCount, 1, "Tab must trigger onTab when ghost text is active")
    }

    func testCustomDemoNSTextViewEscapeAndNewlineInterception() {
        let textView = CustomDemoNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        var tabCount = 0
        var escapeCount = 0
        textView.onTab = { tabCount += 1 }
        textView.onEscape = { escapeCount += 1 }

        // Test Escape
        textView.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(escapeCount, 1, "Escape must call onEscape")

        // Test Newline / Return with ghost text
        textView.ghostText = " world"
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(tabCount, 1, "Return/Newline should accept active ghost text")
    }

    func testCustomDemoNSTextViewDrawingDoesNotCrash() {
        let textView = CustomDemoNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 36))
        textView.placeholderText = "Placeholder test"
        textView.display() // Draw empty state with placeholder

        textView.string = "прив"
        textView.ghostText = "ет, мир! 🚀"
        textView.display() // Draw with Cyrillic text and emoji ghost text
        XCTAssertEqual(textView.string, "прив")
        XCTAssertEqual(textView.ghostText, "ет, мир! 🚀")
    }

    func testHasCaretAdvancedRejectsStaleAndBackwardPositions() {
        let stale = CGRect(x: 100, y: 200, width: 2, height: 16)

        // Same position -> false
        XCTAssertFalse(GhostTextOverlayController.hasCaretAdvanced(from: stale, to: stale))
        XCTAssertFalse(AutocompletionOverlayController.hasCaretAdvanced(from: stale, to: stale))

        // Moved backwards (to the left) -> false
        let backward = CGRect(x: 90, y: 200, width: 2, height: 16)
        XCTAssertFalse(GhostTextOverlayController.hasCaretAdvanced(from: stale, to: backward))
        XCTAssertFalse(AutocompletionOverlayController.hasCaretAdvanced(from: stale, to: backward))

        // Advanced to the right -> true
        let advanced = CGRect(x: 160, y: 200, width: 2, height: 16)
        XCTAssertTrue(GhostTextOverlayController.hasCaretAdvanced(from: stale, to: advanced))
        XCTAssertTrue(AutocompletionOverlayController.hasCaretAdvanced(from: stale, to: advanced))

        // Line wrap (vertical change >= 4) -> true
        let nextLine = CGRect(x: 20, y: 220, width: 2, height: 16)
        XCTAssertTrue(GhostTextOverlayController.hasCaretAdvanced(from: stale, to: nextLine))
        XCTAssertTrue(AutocompletionOverlayController.hasCaretAdvanced(from: stale, to: nextLine))

        // Stale anchor nil -> true if valid
        XCTAssertTrue(GhostTextOverlayController.hasCaretAdvanced(from: nil, to: advanced))
        XCTAssertTrue(AutocompletionOverlayController.hasCaretAdvanced(from: nil, to: advanced))

        // Coarse field rect -> rejected by AutocompletionOverlayController
        let fieldRect = CGRect(x: 100, y: 200, width: 300, height: 100)
        XCTAssertFalse(AutocompletionOverlayController.hasCaretAdvanced(from: stale, to: fieldRect))
    }

    func testContinuationWaitsForCaretAdvanceBeforeDisplaying() async throws {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }

        let stale = CGRect(x: 100, y: 200, width: 2, height: 16)
        let advanced = CGRect(x: 160, y: 200, width: 2, height: 16)
        var currentReported = stale

        let cand = AutocompletionCandidate(word: "мир", targetLayoutID: "com.apple.keylayout.Russian")
        ghost.showContinuation(
            candidate: cand,
            suffix: "мир",
            staleAnchor: stale,
            caretProvider: { currentReported },
            isCurrent: { true }
        )

        // While caret is still reported at stale anchor, ghost must NOT be visible
        XCTAssertFalse(ghost.isVisible)

        // Caret now advances after paste
        currentReported = advanced

        // Wait for polling task to detect advance
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(ghost.isVisible)
        XCTAssertEqual(ghost.lastCaretRect, advanced)
    }

    func testOverlayControllerContinuationWaitsForCaretAdvance() async throws {
        let popup = AutocompletionOverlayController()
        defer { popup.hide() }

        let stale = CGRect(x: 100, y: 200, width: 2, height: 16)
        let advanced = CGRect(x: 160, y: 200, width: 2, height: 16)
        var currentReported = stale

        let cand = AutocompletionCandidate(word: "мир", targetLayoutID: "com.apple.keylayout.Russian")
        popup.showContinuation(
            candidates: [cand],
            staleAnchor: stale,
            acceptKeyHint: "Tab",
            caretProvider: { currentReported },
            isCurrent: { true },
            onSelect: { _ in }
        )

        // Popup must NOT be visible while caret is stale
        XCTAssertFalse(popup.isVisible)

        // Caret now advances
        currentReported = advanced

        // Wait for polling task
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(popup.isVisible)
        XCTAssertEqual(popup.pendingCaretAnchor, advanced)
    }

    func testGhostTextDisplayOnLightAndDarkBackground() {
        let ghost = GhostTextOverlayController()
        defer { ghost.hide() }

        let cand = AutocompletionCandidate(word: "testing", targetLayoutID: "com.apple.keylayout.US")
        let caret = CGRect(x: 150, y: 250, width: 2, height: 20)

        ghost.show(candidate: cand, suffix: "sting", caretRect: caret)
        XCTAssertTrue(ghost.isVisible)
        XCTAssertEqual(ghost.currentSuffix, "sting")

        if let panel = ghost.panelFrame {
            XCTAssertGreaterThan(panel.width, 0)
            XCTAssertGreaterThan(panel.height, 0)
        }
    }
}
