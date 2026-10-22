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
    
    func testSearchFieldAllowed() {
        XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXSearchField", subrole: nil, bundleID: textEdit))
    }

    func testComboBoxAllowed() {
        XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXComboBox", subrole: nil, bundleID: textEdit))
    }

    func testWebAreaAllowed() {
        XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXWebArea", subrole: nil, bundleID: textEdit))
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

    func testFoundEditorPreservedEvenIfPendingHasUnvisitedChildren() {
        // Node 0 has child 1 (focused text area) and 50 other unvisited sibling nodes
        XCTAssertEqual(AccessibilityService.resolveFocusedTextNode(root: 0, attributes: { node in
            (node == 1 ? "AXTextArea" : "AXGroup", nil, node == 1)
        }, focusedChild: { _ in nil }, children: { $0 == 0 ? [1] + Array(2..<50) : [] }, limit: 5), 1)
    }

    // MARK: - Secret Sanitizer Tests (Cotypist-grade Privacy Protection)

    func testDetectsPrivateKeys() {
        let rsaKey = "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA0...\n-----END RSA PRIVATE KEY-----"
        XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation(rsaKey))
        XCTAssertTrue(AutoCorrectionGate.isPotentialSecret(rsaKey))
        XCTAssertNil(AutoCorrectionGate.sanitize(text: rsaKey))
        XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
            role: "AXTextField", subrole: nil, bundleID: textEdit, text: rsaKey))
    }

    func testDetectsPasswordAssignments() {
        let cases = [
            "password: mysecretpassword123",
            "passwd = Admin2026!",
            "пароль: qwerty12345",
            "secret=s3cr3t",
            "kennwort: geheim123"
        ]
        for c in cases {
            XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation(c), "Failed to detect password in: \(c)")
            XCTAssertNil(AutoCorrectionGate.sanitize(text: c))
            XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
                role: "AXTextField", subrole: nil, bundleID: textEdit, text: c))
        }
    }

    func testDetectsShellExportSecrets() {
        let cases = [
            "export API_KEY=sk-proj-1234567890abcdef1234",
            "DB_PASSWORD=secret",
            "export GITHUB_TOKEN=ghp_12345678901234567890"
        ]
        for c in cases {
            XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation(c), "Failed to detect shell secret in: \(c)")
            XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
                role: "AXTextField", subrole: nil, bundleID: textEdit, text: c))
        }
    }

    func testDetectsApiTokensAndKeys() {
        let tokens = [
            "sk-proj-abcdefghijklmnopqrstuvwxyz1234",
            "sk_live_1234567890abcdef12",
            "AKIAIOSFODNN7EXAMPLE",
            "ghp_123456789012345678901234",
            "AIzaSyD-1234567890abcdefghijklmnopqrstu",
            "xoxb-1234567890-1234567890-abcdef",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozGz_abcdef"
        ]
        for t in tokens {
            XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation(t), "Failed on token: \(t)")
            XCTAssertTrue(AutoCorrectionGate.isPotentialSecret(t), "Failed potential secret on: \(t)")
            XCTAssertFalse(AutoCorrectionGate.allowsAutoCorrection(
                role: "AXTextField", subrole: nil, bundleID: textEdit, text: t))
        }
    }

    func testDetectsFinancialAndAuthData() {
        XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation("DE89 3704 0044 0532 0130 00"))
        XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation("https://admin:p@ssword@example.com/api"))
        XCTAssertTrue(AutoCorrectionGate.containsSensitiveInformation("4532 1234 5678 9012"))
    }

    func testNormalTextAllowed() {
        let normalTexts = [
            "Hello world, how are you today?",
            "Привет как твои дела?",
            "ghbdtn rfr ltkf",
            "let x = 42 + y",
            "function calculateTotal(items: [Item]) -> Double"
        ]
        for txt in normalTexts {
            XCTAssertFalse(AutoCorrectionGate.containsSensitiveInformation(txt), "False positive on: \(txt)")
            XCTAssertFalse(AutoCorrectionGate.isPotentialSecret(txt), "False positive on: \(txt)")
            XCTAssertTrue(AutoCorrectionGate.allowsAutoCorrection(
                role: "AXTextField", subrole: nil, bundleID: textEdit, text: txt))
        }
    }

    func testHighEntropyPasswordHeuristic() {
        let password = "P@ssw0rd2026!#"
        XCTAssertTrue(AutoCorrectionGate.isPotentialSecret(password))

        let normalWord = "Supercalifragilistic"
        XCTAssertFalse(AutoCorrectionGate.isPotentialSecret(normalWord))
    }

    func testSanitizesEmails() {
        let input = "Please contact support@example.com for help."
        let sanitized = AutoCorrectionGate.sanitize(text: input)
        XCTAssertEqual(sanitized, "Please contact [email] for help.")
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
