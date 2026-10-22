import Foundation

// MARK: - Auto-Correction Gate
// Pure policy: where the silent auto-correction may run.
// Secure fields and unknown focus fail closed (deny).

enum AutoCorrectionGate {
    
    /// Roles the auto-correction may touch. Deliberately narrow:
    /// any other focused control (a button, a menu) must never hijack
    /// the selection.
    static let textInputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXComboBox",
        "AXWebArea",
        "AXGenericElement",
        "AXParagraph"
    ]
    
    /// Accessibility identifier marking a password field — appears either
    /// as the role itself or, Safari-style, as the subrole of an AXTextField.
    static let secureIdentifier = "AXSecureTextField"
    
    /// Apps where silent rewriting is dangerous even in plain fields
    /// (shell commands must never be reinterpreted as prose, password managers must never be inspected).
    static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Main",
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess"
    ]
    
    /// True for password fields, via role or subrole.
    static func isSecureField(role: String?, subrole: String?) -> Bool {
        role == secureIdentifier || subrole == secureIdentifier
    }
    
    /// Combined rule for the automatic flow. Manual hotkey conversion
    /// (explicit user intent) bypasses this gate entirely.
    static func allowsAutoCorrection(
        role: String?,
        subrole: String?,
        bundleID: String?,
        excludedBundleIDs: Set<String> = defaultExcludedBundleIDs
    ) -> Bool {
        // Unknown focus (no AX permission, unreadable UI) fails closed
        guard let role, textInputRoles.contains(role) else { return false }
        guard !isSecureField(role: role, subrole: subrole) else { return false }
        // Unknown app is transient (AX already proved readable) — allow
        if let bundleID, excludedBundleIDs.contains(bundleID) { return false }
        return true
    }
}
