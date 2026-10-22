import Foundation
import AppKit

// MARK: - Editor Font Customizer
// Discovers, parses, and provides the exact font family and size used in code editors
// (VS Code, Cursor, Windsurf, Ghostty, iTerm2, Terminal) to ensure 1:1 pixel alignment
// of ghost-text completion overlays.

@MainActor
final class EditorFontCustomizer {
    
    static let shared = EditorFontCustomizer()
    
    // MARK: - Known Bundle Identifiers
    
    static let ghosttyBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.mitchellh.ghostty.debug"
    ]
    
    static let vscodeForkBundleIDs: [String: String] = [
        "com.microsoft.VSCode": "Code",
        "com.microsoft.VSCodeInsiders": "Code - Insiders",
        "com.visualstudio.code.oss": "Code - OSS",
        "com.vscodium": "VSCodium",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf"
    ]
    
    static let itermBundleIDs: Set<String> = [
        "com.googlecode.iterm2"
    ]
    
    static let appleTerminalBundleIDs: Set<String> = [
        "com.apple.Terminal"
    ]
    
    static let otherCodingAppBundleIDs: Set<String> = [
        "com.apple.dt.Xcode",
        "com.sublimetext.3",
        "com.sublimetext.4",
        "com.barebones.bbedit",
        "com.panic.Nova",
        "com.jetbrains.intellij",
        "com.jetbrains.pycharm",
        "com.jetbrains.webstorm",
        "com.jetbrains.goland",
        "com.jetbrains.CLion",
        "com.jetbrains.AppCode",
        "com.jetbrains.rider"
    ]
    
    // MARK: - Cache Structure
    
    struct CachedFontConfig {
        let font: NSFont
        let timestamp: Date
        let family: String?
        let size: CGFloat
    }
    
    private var cache: [String: CachedFontConfig] = [:]
    private let cacheTTL: TimeInterval = 4.0 // 4 seconds TTL
    
    // Test overrides
    var ghosttyConfigOverride: String?
    var vscodeSettingsOverride: String?
    
    // MARK: - Public Font Resolution
    
    /// Resolves the optimal NSFont for the target application and caret bounds.
    func font(for bundleID: String?, caretHeight: CGFloat? = nil) -> NSFont? {
        guard let bundleID = bundleID else { return nil }
        
        let now = Date()
        if let cached = cache[bundleID], now.timeIntervalSince(cached.timestamp) < cacheTTL {
            // If caret height is passed and differs substantially, scale font size
            if let caretHeight = caretHeight, caretHeight > 10, caretHeight < 40 {
                let expectedSize = max(11.0, min(24.0, caretHeight - 3.0))
                if abs(cached.size - expectedSize) > 3.0 {
                    let scaled = NSFont(name: cached.font.fontName, size: expectedSize) ?? cached.font
                    return scaled
                }
            }
            return cached.font
        }
        
        let config = resolveFontConfig(for: bundleID, caretHeight: caretHeight)
        guard let resolved = config else { return nil }
        
        cache[bundleID] = CachedFontConfig(
            font: resolved.font,
            timestamp: now,
            family: resolved.family,
            size: resolved.size
        )
        return resolved.font
    }
    
    /// Returns the detected font family and size for inspection or testing.
    func detectedFontConfig(for bundleID: String) -> (family: String?, size: CGFloat)? {
        guard let resolved = resolveFontConfig(for: bundleID, caretHeight: nil) else { return nil }
        return (resolved.family, resolved.size)
    }
    
    // MARK: - Internal Resolution
    
    private func resolveFontConfig(for bundleID: String, caretHeight: CGFloat?) -> (font: NSFont, family: String?, size: CGFloat)? {
        let fallbackSize: CGFloat
        if let ch = caretHeight, ch > 10, ch < 40 {
            fallbackSize = max(11.0, min(24.0, ch - 3.0))
        } else {
            fallbackSize = 13.5
        }
        
        // 1. Ghostty
        if Self.ghosttyBundleIDs.contains(bundleID) {
            let parsed = loadGhosttyConfig()
            let size = parsed.size ?? fallbackSize
            if let family = parsed.family, let font = instantiateFont(name: family, size: size) {
                return (font, family, size)
            }
            return (NSFont.monospacedSystemFont(ofSize: size, weight: .regular), parsed.family, size)
        }
        
        // 2. VS Code and forks (Cursor, Windsurf, VSCodium)
        if let appFolder = Self.vscodeForkBundleIDs[bundleID] {
            let parsed = loadVSCodeConfig(appName: appFolder)
            let size = parsed.size ?? fallbackSize
            if let family = parsed.family, let font = instantiateFont(name: family, size: size) {
                return (font, family, size)
            }
            return (NSFont.monospacedSystemFont(ofSize: size, weight: .regular), parsed.family, size)
        }
        
        // 3. iTerm2
        if Self.itermBundleIDs.contains(bundleID) {
            let parsed = loadITerm2Config()
            let size = parsed.size ?? fallbackSize
            if let family = parsed.family, let font = instantiateFont(name: family, size: size) {
                return (font, family, size)
            }
            return (NSFont.monospacedSystemFont(ofSize: size, weight: .regular), parsed.family, size)
        }
        
        // 4. Apple Terminal
        if Self.appleTerminalBundleIDs.contains(bundleID) {
            let size = fallbackSize
            if let font = instantiateFont(name: "SF Mono", size: size) ?? instantiateFont(name: "Menlo", size: size) {
                return (font, font.familyName, size)
            }
            return (NSFont.monospacedSystemFont(ofSize: size, weight: .regular), "SF Mono", size)
        }
        
        // 5. Other IDEs / Editors
        if Self.otherCodingAppBundleIDs.contains(bundleID) || bundleID.contains("jetbrains") || bundleID.contains("Xcode") {
            let size = fallbackSize
            return (NSFont.monospacedSystemFont(ofSize: size, weight: .regular), nil, size)
        }
        
        return nil
    }
    
    // MARK: - App Config Parsers
    
    private func loadGhosttyConfig() -> (family: String?, size: CGFloat?) {
        if let override = ghosttyConfigOverride {
            return Self.parseGhosttyConfig(content: override)
        }
        
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let candidateURLs = [
            home.appendingPathComponent(".config/ghostty/config"),
            home.appendingPathComponent(".config/ghostty/config.ghostty"),
            home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config"),
            home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config.ghostty")
        ]
        
        for url in candidateURLs {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let parsed = Self.parseGhosttyConfig(content: content)
                if parsed.family != nil || parsed.size != nil {
                    return parsed
                }
            }
        }
        return (nil, nil)
    }
    
    static func parseGhosttyConfig(content: String) -> (family: String?, size: CGFloat?) {
        var family: String?
        var size: CGFloat?
        
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            
            if line.hasPrefix("font-family") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    var val = parts[1]
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    if !val.isEmpty {
                        family = val
                    }
                }
            } else if line.hasPrefix("font-size") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let parsedSize = Double(parts[1]), parsedSize > 4 && parsedSize < 100 {
                    size = CGFloat(parsedSize)
                }
            }
        }
        return (family, size)
    }
    
    private func loadVSCodeConfig(appName: String) -> (family: String?, size: CGFloat?) {
        if let override = vscodeSettingsOverride {
            return Self.parseVSCodeSettings(jsonString: override)
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Library/Application Support/\(appName)/User/settings.json")
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (nil, nil)
        }
        return Self.parseVSCodeSettings(jsonString: content)
    }
    
    static func parseVSCodeSettings(jsonString: String) -> (family: String?, size: CGFloat?) {
        // Strip trailing commas or comments if user has JSON with comments
        let cleaned = jsonString
            .replacingOccurrences(of: "//.*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
        
        guard let data = cleaned.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (nil, nil)
        }
        
        var family: String?
        var size: CGFloat?
        
        if let rawFamily = dict["editor.fontFamily"] as? String {
            // First item before comma: e.g. "'JetBrains Mono', Menlo, Monaco, monospace" -> "JetBrains Mono"
            let first = rawFamily.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
            var clean = first
            if (clean.hasPrefix("'") && clean.hasSuffix("'")) || (clean.hasPrefix("\"") && clean.hasSuffix("\"")) {
                clean = String(clean.dropFirst().dropLast())
            }
            if !clean.isEmpty && clean.lowercased() != "monospace" {
                family = clean
            }
        }
        
        if let rawSize = dict["editor.fontSize"] as? Double, rawSize > 4 && rawSize < 100 {
            size = CGFloat(rawSize)
        } else if let intSize = dict["editor.fontSize"] as? Int, intSize > 4 && intSize < 100 {
            size = CGFloat(intSize)
        }
        
        return (family, size)
    }
    
    private func loadITerm2Config() -> (family: String?, size: CGFloat?) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plistURL = home.appendingPathComponent("Library/Preferences/com.googlecode.iterm2.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            return (nil, nil)
        }
        
        if let bookmarks = dict["New Bookmarks"] as? [[String: Any]], let defaultProfile = bookmarks.first {
            if let fontStr = defaultProfile["Normal Font"] as? String {
                return Self.parseITermFontString(fontStr)
            }
        }
        return (nil, nil)
    }
    
    static func parseITermFontString(_ fontString: String) -> (family: String?, size: CGFloat?) {
        // e.g. "JetBrainsMono-Regular 14" or "Monaco 12" or "Menlo-Regular 13"
        let trimmed = fontString.trimmingCharacters(in: .whitespaces)
        guard let lastSpace = trimmed.lastIndex(of: " ") else {
            return (trimmed, nil)
        }
        let familyPart = String(trimmed[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        let sizePart = String(trimmed[lastSpace...]).trimmingCharacters(in: .whitespaces)
        let size = Double(sizePart).flatMap { CGFloat($0) }
        
        // Clean up common PostScript styles (e.g. JetBrainsMono-Regular -> JetBrains Mono)
        let cleanedFamily = familyPart
            .replacingOccurrences(of: "-Regular", with: "")
            .replacingOccurrences(of: "-Medium", with: "")
            .replacingOccurrences(of: "-Light", with: "")
            .replacingOccurrences(of: "-Bold", with: "")
        
        return (cleanedFamily.isEmpty ? familyPart : cleanedFamily, size)
    }
    
    // MARK: - Font Factory
    
    private func instantiateFont(name: String, size: CGFloat) -> NSFont? {
        if let font = NSFont(name: name, size: size) {
            return font
        }
        // Try searching family name in NSFontManager
        let manager = NSFontManager.shared
        if manager.availableFontFamilies.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return manager.font(withFamily: name, traits: [], weight: 5, size: size)
        }
        return nil
    }
}
