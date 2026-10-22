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
}
