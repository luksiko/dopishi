import Foundation
import Carbon
import Cocoa

// MARK: - Keyboard Layout Detector
// Detects installed keyboard layouts from the system

final class KeyboardLayoutDetector {
    
    /// Get all keyboard layouts currently enabled in System Preferences
    static func getInstalledLayouts() -> [KeyboardLayout] {
        var layouts: [KeyboardLayout] = []
        
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return layouts
        }
        
        for source in inputSources {
            guard let categoryPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else { continue }
            let category = Unmanaged<CFString>.fromOpaque(categoryPtr).takeUnretainedValue() as String
            guard category == kTISPropertyInputSourceCategory as String ||
                  category == (kTISCategoryKeyboardInputSource as String) else { continue }
            
            guard let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr).takeUnretainedValue()) else { continue }
            
            guard let typePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { continue }
            let type = Unmanaged<CFString>.fromOpaque(typePtr).takeUnretainedValue() as String
            guard type == (kTISTypeKeyboardLayout as String) else { continue }
            
            guard let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
            
            guard !layouts.contains(where: { $0.id.caseInsensitiveCompare(sourceID) == .orderedSame }) else { continue }
            
            guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { continue }
            let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
            
            var langCode = "unknown"
            if let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
                let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String]
                langCode = langs?.first ?? "unknown"
            }
            if langCode == "unknown" || langCode.isEmpty {
                langCode = StatusBarBadgeRenderer.languageCode(layoutId: sourceID, languageCode: "", localizedName: name).lowercased()
            }
            
            // Pre-warm character map (extracts dynamic map if not static)
            _ = LayoutCharacterMap.characterMap(for: sourceID)
            
            layouts.append(KeyboardLayout(
                id: sourceID,
                localizedName: name,
                languageCode: langCode
            ))
        }
        
        // If no supported layouts found, provide defaults
        if layouts.isEmpty {
            layouts = defaultLayouts()
        }
        
        return layouts
    }
    
    /// Get the currently active keyboard layout
    static func getCurrentLayout() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
        
        guard let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return nil }
        let name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        
        var langCode = "unknown"
        if let langsPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) {
            let langs = Unmanaged<CFArray>.fromOpaque(langsPtr).takeUnretainedValue() as? [String]
            langCode = langs?.first ?? "unknown"
        }
        
        return KeyboardLayout(id: sourceID, localizedName: name, languageCode: langCode)
    }
    
    /// Switch the active keyboard layout to the one matching the given source ID.
    /// Uses TISSelectInputSource from the Carbon Input Source API.
    static func switchToLayout(_ targetID: String) {
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            NSLog("[LangSwitcher] switchToLayout: failed to get input source list")
            return
        }
        
        // Pass 1: exact match
        for source in inputSources {
            guard let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr).takeUnretainedValue()) else { continue }
            guard let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
            
            if sourceID.caseInsensitiveCompare(targetID) == .orderedSame {
                let status = TISSelectInputSource(source)
                if status == noErr {
                    NSLog("[LangSwitcher] switchToLayout: switched to exact '\(targetID)'")
                    NotificationCenter.default.post(name: .keyboardLayoutSelectionChanged, object: nil)
                    return
                } else {
                    NSLog("[LangSwitcher] switchToLayout: TISSelectInputSource failed with status \(status)")
                }
            }
        }
        
        // Pass 2: family fallback match (e.g. RussianWin <-> Russian, ABC <-> US)
        let targetLower = targetID.lowercased()
        for source in inputSources {
            guard let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr).takeUnretainedValue()) else { continue }
            guard let sourceIDPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { continue }
            let sourceID = Unmanaged<CFString>.fromOpaque(sourceIDPtr).takeUnretainedValue() as String
            let sourceLower = sourceID.lowercased()
            
            var matched = false
            if targetLower.contains("russian") && sourceLower.contains("russian") {
                matched = true
            } else if !targetLower.contains("russian") && !sourceLower.contains("russian") &&
                      (targetLower.contains("us") || targetLower.contains("abc")) &&
                      (sourceLower.contains("us") || sourceLower.contains("abc")) {
                matched = true
            } else if targetLower.contains("ukrainian") && sourceLower.contains("ukrainian") {
                matched = true
            } else if targetLower.contains("polish") && sourceLower.contains("polish") {
                matched = true
            } else if targetLower.contains("german") && sourceLower.contains("german") {
                matched = true
            } else if targetLower.contains("french") && sourceLower.contains("french") {
                matched = true
            } else if targetLower.contains("spanish") && sourceLower.contains("spanish") {
                matched = true
            } else if targetLower.contains("tajik") && sourceLower.contains("tajik") {
                matched = true
            } else if targetLower.contains(sourceLower) || sourceLower.contains(targetLower) {
                if !(targetLower.contains("russian") && (sourceLower.contains("us") || sourceLower.contains("abc"))) &&
                   !(sourceLower.contains("russian") && (targetLower.contains("us") || targetLower.contains("abc"))) {
                    matched = true
                }
            }
            
            if matched {
                let status = TISSelectInputSource(source)
                if status == noErr {
                    NSLog("[LangSwitcher] switchToLayout: switched to family match '\(sourceID)' for '\(targetID)'")
                    NotificationCenter.default.post(name: .keyboardLayoutSelectionChanged, object: nil)
                } else {
                    NSLog("[LangSwitcher] switchToLayout: TISSelectInputSource failed with status \(status)")
                }
                return
            }
        }
        
        NSLog("[LangSwitcher] switchToLayout: layout '\(targetID)' not found in system sources")
    }
    
    /// Calculate the next keyboard layout in the sequence.
    /// Pure function for testability.
    static func nextLayout(
        currentID: String?,
        currentLanguageCode: String? = nil,
        among layouts: [KeyboardLayout]
    ) -> KeyboardLayout? {
        guard layouts.count > 1 else { return nil }
        
        var currentIndex: Int? = nil
        if let currentID = currentID {
            currentIndex = layouts.firstIndex(where: {
                $0.id.caseInsensitiveCompare(currentID) == .orderedSame
            })
        }
        if currentIndex == nil, let lang = currentLanguageCode {
            currentIndex = layouts.firstIndex(where: {
                $0.languageCode.lowercased() == lang.lowercased()
            })
        }
        
        let index = currentIndex ?? -1
        let nextIndex = (index + 1) % layouts.count
        return layouts[nextIndex]
    }
    
    /// Switch to the next enabled layout in a cyclic sequence.
    /// If there are 2 layouts (e.g. EN, RU), toggles between them.
    /// If there are 3+, cycles through them in order.
    @discardableResult
    static func switchToNextLayout(among layouts: [KeyboardLayout]? = nil) -> KeyboardLayout? {
        let candidateLayouts: [KeyboardLayout]
        if let layouts = layouts, !layouts.isEmpty {
            candidateLayouts = layouts
        } else {
            candidateLayouts = getInstalledLayouts()
        }
        
        let current = getCurrentLayout()
        guard let target = nextLayout(
            currentID: current?.id,
            currentLanguageCode: current?.languageCode,
            among: candidateLayouts
        ) else {
            return nil
        }
        
        switchToLayout(target.id)
        return target
    }
    
    /// Default fallback layouts
    private static func defaultLayouts() -> [KeyboardLayout] {
        [
            KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en"),
            KeyboardLayout(id: "com.apple.keylayout.Russian", localizedName: "Russian", languageCode: "ru"),
        ]
    }
}
