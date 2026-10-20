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
}
