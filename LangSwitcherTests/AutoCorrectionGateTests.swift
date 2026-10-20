import XCTest
@testable import LangSwitcher

final class AutoCorrectionGateTests: XCTestCase {
    
    // MARK: - allowsAutoCorrection
    //
    // The silent auto-correction runs only in plain text fields of non-excluded
    // apps. Secure fields and unknown focus fail closed (deny).
    
    private let textEdit = "com.apple.TextEdit"
    
    func testPlainTextFieldAllowed() {
        XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextField", subrole: nil, bundleID: textEdit))
    }
    
    func testTextAreaAllowed() {
        XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextArea", subrole: "AXContentList", bundleID: textEdit))
    }
    
    func testSecureRoleDenied() {
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXSecureTextField", subrole: nil, bundleID: textEdit))
    }
    
    func testSecureSubroleDenied() {
        // Safari-style: role stays AXTextField, subrole marks it secure
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextField", subrole: "AXSecureTextField", bundleID: textEdit))
    }
    
    func testNonTextRoleDenied() {
        // Focused button or other controls must never be hijacked
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXButton", subrole: nil, bundleID: textEdit))
    }
    
    func testUnknownFocusDenied() {
        // Fail closed: no AX permission or unreadable UI means no auto-correct
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: nil, subrole: nil, bundleID: textEdit))
    }
    
    func testTerminalExcluded() {
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextArea", subrole: nil, bundleID: "com.apple.Terminal"))
    }
    
    func testITermExcluded() {
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextArea", subrole: nil, bundleID: "com.googlecode.iterm2"))
    }
    
    func testCustomExclusionRespected() {
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextField", subrole: nil, bundleID: "com.example.game",
            excludedBundleIDs: ["com.example.game"]))
    }
    
    func testUnknownAppWithTextFieldAllowed() {
        // NSWorkspace hiccup must not block a verified text field
        XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextField", subrole: nil, bundleID: nil))
    }
    
    // MARK: - isSecureField
    
    func testIsSecureField() {
        XCTAssertTrue(AutoCorrectionGate.isSecureField(role: "AXSecureTextField", subrole: nil))
        XCTAssertTrue(AutoCorrectionGate.isSecureField(role: "AXTextField", subrole: "AXSecureTextField"))
        XCTAssertFalse(AutoCorrectionGate.isSecureField(role: "AXTextField", subrole: nil))
        XCTAssertFalse(AutoCorrectionGate.isSecureField(role: nil, subrole: nil))
    }
    func testNestedEditorRequiresExplicitFocus() {
        let result = AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 0 ? "AXGroup" : "AXTextArea", nil, node == 2)
        }, focusedChild: { _ in nil }, children: { $0 == 0 ? [1, 2] : [] })
        XCTAssertEqual(result, 2)
        XCTAssertNil(AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 0 ? "AXGroup" : "AXTextArea", nil, false)
        }, focusedChild: { _ in nil }, children: { $0 == 0 ? [1] : [] }))
    }

    func testNestedSecureOrAmbiguousEditorIsRejected() {
        XCTAssertNil(AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 0 ? "AXGroup" : "AXTextArea", node == 2 ? "AXSecureTextField" : nil, node != 0)
        }, focusedChild: { _ in nil }, children: { $0 == 0 ? [1, 2] : [] }))
        XCTAssertNil(AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 0 ? "AXGroup" : "AXTextArea", nil, node != 0)
        }, focusedChild: { _ in nil }, children: { $0 == 0 ? [1, 2] : [] }))
    }

    func testFocusLinkCyclesAndTraversalBudget() {
        XCTAssertEqual(AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 1 ? "AXTextArea" : "AXGroup", nil, false)
        }, focusedChild: { $0 == 0 ? 1 : 0 }, children: { _ in [] }), 1)
        XCTAssertNil(AccessibilityService.resolveFocusedTextNode(root: 0,
            attributes: { _ in ("AXGroup", nil, false) }, focusedChild: { _ in nil },
            children: { [$0 + 1] }, limit: 5))
    }

    func testExplicitFocusLinkAvoidsScanningPublicationContent() {
        XCTAssertEqual(AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 1 ? "AXTextArea" : "AXGroup", nil, false)
        }, focusedChild: { $0 == 0 ? 1 : nil }, children: { _ in Array(2..<1000) }, limit: 3), 1)
    }

}


extension AutoCorrectionGateTests {
    @MainActor
    func testRemovingDefaultExclusionsAllowsTerminalEditors() {
        let settings = SettingsManager.shared
        let saved = settings.excludedAppBundleIDs
        defer { settings.excludedAppBundleIDs = saved }
        for bundleID in AutoCorrectionGate.defaultExcludedBundleIDs {
            settings.addExcludedApp(bundleID: bundleID)
            XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(role: "AXTextArea", subrole: nil,
                bundleID: bundleID, excludedBundleIDs: Set(settings.excludedAppBundleIDs)))
            settings.removeExcludedApp(bundleID: bundleID)
            XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(role: "AXTextArea", subrole: nil,
                bundleID: bundleID, excludedBundleIDs: Set(settings.excludedAppBundleIDs)))
            XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(role: "AXTextField", subrole: "AXSecureTextField",
                bundleID: bundleID, excludedBundleIDs: Set(settings.excludedAppBundleIDs)))
        }
    }
}
