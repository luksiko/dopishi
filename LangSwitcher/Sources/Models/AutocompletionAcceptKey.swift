import Foundation
import Carbon
import Cocoa

// MARK: - Autocompletion Candidate

struct AutocompletionCandidate: Identifiable, Equatable, Hashable {
    let id: String
    let word: String
    let targetLayoutID: String
    let isCrossLayout: Bool
    let score: Int
    
    init(word: String, targetLayoutID: String, isCrossLayout: Bool = false, score: Int = 0) {
        self.id = "\(targetLayoutID):\(word)"
        self.word = word
        self.targetLayoutID = targetLayoutID
        self.isCrossLayout = isCrossLayout
        self.score = score
    }
}

// MARK: - Autocompletion Accept Key

enum AutocompletionAcceptKey: String, CaseIterable, Identifiable, Codable {
    case tab = "tab"
    case space = "space"
    case enter = "enter"
    case rightArrow = "rightArrow"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var defaultKeyCode: UInt16 {
        switch self {
        case .tab: return 0x30        // Tab
        case .space: return 0x31      // Space
        case .enter: return 0x24      // Return
        case .rightArrow: return 0x7C // Right Arrow
        case .custom: return 0x30     // Tab fallback
        }
    }
    
    @MainActor
    var displayName: String {
        LocalizationManager.shared.t("autocompletion.acceptKey.\(rawValue)")
    }
    
    @MainActor
    var shortcutHint: String {
        shortcutHint()
    }
    
    @MainActor
    func shortcutHint(customKeyCode: UInt16 = 0x30, customModifiers: UInt = 0) -> String {
        switch self {
        case .tab: return "⇥"
        case .space: return "␣"
        case .enter: return "↩"
        case .rightArrow: return "→"
        case .custom:
            let mods = HotkeyManager.modifierFlagsToString(NSEvent.ModifierFlags(rawValue: customModifiers).intersection(.deviceIndependentFlagsMask))
            let key = HotkeyManager.keyCodeToString(customKeyCode)
            return "\(mods)\(key)"
        }
    }
}
