import Foundation

// MARK: - Auto-Correction Gate
// Pure policy: where the silent auto-correction may run.
// Secure fields, sensitive data, and unknown focus fail closed (deny).

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
    
    // MARK: - Secret Sanitizer Patterns (Cotypist-grade Privacy Protection)
    
    private static let privateKeyRegex = try? NSRegularExpression(
        pattern: #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#,
        options: []
    )
    
    private static let passwordAssignmentRegex = try? NSRegularExpression(
        pattern: #"(?i)(\b(?:pass(?:word|wort|wd|phrase)?|kennwort|secret|пароль)[ \t]*[:=][ \t]*)(\S+)"#,
        options: []
    )
    
    private static let shellExportSecretRegex = try? NSRegularExpression(
        pattern: #"(?i)^[ \t]*(?:export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*(?:TOKEN|KEY|SECRET|PASSWORD|PASSWD|AUTH)[ \t]*=[ \t]*(\S+)"#,
        options: [.anchorsMatchLines]
    )
    
    private static let apiTokensRegex = try? NSRegularExpression(
        pattern: #"\b(?:sk-(?:proj-)?[0-9A-Za-z_-]{20,}|(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{16,}|(?:AKIA|ASIA)[0-9A-Z]{16}|gh[pousr]_[0-9A-Za-z]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[0-9A-Za-z-]{10,}|eyJ[0-9A-Za-z_-]{8,}\.[0-9A-Za-z_-]{8,}(?:\.[0-9A-Za-z_-]{5,})?)\b"#,
        options: []
    )
    
    private static let ibanRegex = try? NSRegularExpression(
        pattern: #"\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){2,7}(?:[ ]?[A-Z0-9]{1,3})?\b"#,
        options: []
    )
    
    private static let basicAuthUrlRegex = try? NSRegularExpression(
        pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s/:@]+:[^\s/@]+@"#,
        options: []
    )
    
    private static let creditCardRegex = try? NSRegularExpression(
        pattern: #"\b(?:\d[ -]*?){13,16}\b"#,
        options: []
    )

    private static let emailRegex = try? NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,
        options: []
    )
    
    /// True for password fields, via role or subrole.
    static func isSecureField(role: String?, subrole: String?) -> Bool {
        role == secureIdentifier || subrole == secureIdentifier
    }
    
    /// Checks whether the text contains sensitive information like API keys,
    /// private keys, passwords, bearer tokens, or financial identifiers.
    static func containsSensitiveInformation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let privateKeyRegex, privateKeyRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let passwordAssignmentRegex, passwordAssignmentRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let shellExportSecretRegex, shellExportSecretRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let apiTokensRegex, apiTokensRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let ibanRegex, ibanRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let basicAuthUrlRegex, basicAuthUrlRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let creditCardRegex, creditCardRegex.firstMatch(in: text, range: range) != nil {
            return true
        }
        return false
    }
    
    /// Checks if a single word or buffer matches high-risk secret patterns (API keys, JWT, passwords).
    static func isPotentialSecret(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if containsSensitiveInformation(word) { return true }
        
        // High-entropy password heuristic: length >= 10 with digits + punctuation + mixed case
        if word.count >= 10 {
            let hasLower = word.contains(where: \.isLowercase)
            let hasUpper = word.contains(where: \.isUppercase)
            let hasDigit = word.contains(where: \.isNumber)
            let hasPunct = word.contains(where: \.isPunctuation) || word.contains(where: \.isSymbol)
            if hasLower && hasUpper && hasDigit && hasPunct {
                return true
            }
        }
        return false
    }
    
    /// Redacts sensitive patterns in a string (e.g. replacing tokens or emails with placeholders).
    static func sanitize(text: String) -> String? {
        guard !text.isEmpty else { return nil }
        if containsSensitiveInformation(text) { return nil }
        
        var clean = text
        let range = NSRange(location: 0, length: clean.utf16.count)
        if let emailRegex {
            clean = emailRegex.stringByReplacingMatches(in: clean, range: range, withTemplate: "[email]")
        }
        return clean
    }
    
    /// Combined rule for the automatic flow. Manual hotkey conversion
    /// (explicit user intent) bypasses this gate entirely.
    static func allowsAutoCorrection(
        role: String?,
        subrole: String?,
        bundleID: String?,
        text: String? = nil,
        excludedBundleIDs: Set<String> = defaultExcludedBundleIDs
    ) -> Bool {
        // Unknown focus (no AX permission, unreadable UI) fails closed
        guard let role, textInputRoles.contains(role) else { return false }
        guard !isSecureField(role: role, subrole: subrole) else { return false }
        // Unknown app is transient (AX already proved readable) — allow
        if let bundleID, excludedBundleIDs.contains(bundleID) { return false }
        // Sensitive text contents (passwords, tokens, API keys) fail closed
        if let text, containsSensitiveInformation(text) { return false }
        return true
    }
}
