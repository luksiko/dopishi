import Foundation

// MARK: - Layout Switch Key
/// Dedicated single key for toggling/cycling system keyboard layout
enum LayoutSwitchKey: String, CaseIterable, Identifiable, Codable {
    case disabled = "disabled"
    case rightOption = "rightOption"
    case rightCommand = "rightCommand"
    case rightShift = "rightShift"
    case rightControl = "rightControl"
    case capsLock = "capsLock"
    case leftOption = "leftOption"
    case leftControl = "leftControl"
    case leftCommand = "leftCommand"
    case leftShift = "leftShift"
    case fn = "fn"
    
    var id: String { rawValue }
    
    var keyCode: UInt16? {
        switch self {
        case .disabled: return nil
        case .rightOption: return 61    // 0x3D
        case .rightCommand: return 54   // 0x36
        case .rightShift: return 60     // 0x3C
        case .rightControl: return 62   // 0x3E
        case .capsLock: return 57       // 0x39
        case .leftOption: return 58     // 0x3A
        case .leftControl: return 59    // 0x3B
        case .leftCommand: return 55    // 0x37
        case .leftShift: return 56      // 0x38
        case .fn: return 63             // 0x3F
        }
    }
    
    /// Device-dependent mask for modifier keys in Carbon/IOKit
    var deviceMask: UInt32? {
        switch self {
        case .rightOption: return 0x0040  // NX_DEVICERALTKEYMASK
        case .rightCommand: return 0x0010 // NX_DEVICERCMDKEYMASK
        case .rightShift: return 0x0004   // NX_DEVICERSHIFTKEYMASK
        case .rightControl: return 0x2000 // NX_DEVICERCTLKEYMASK
        case .leftOption: return 0x0020   // NX_DEVICELALTKEYMASK
        case .leftCommand: return 0x0008  // NX_DEVICELCMDKEYMASK
        case .leftShift: return 0x0002    // NX_DEVICELSHIFTKEYMASK
        case .leftControl: return 0x0001  // NX_DEVICELCTLKEYMASK
        default: return nil
        }
    }
    
    @MainActor var displayName: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .disabled: return l10n.t("layoutSwitchKey.disabled")
        case .rightOption: return l10n.t("layoutSwitchKey.rightOption")
        case .rightCommand: return l10n.t("layoutSwitchKey.rightCommand")
        case .rightShift: return l10n.t("layoutSwitchKey.rightShift")
        case .rightControl: return l10n.t("layoutSwitchKey.rightControl")
        case .capsLock: return l10n.t("layoutSwitchKey.capsLock")
        case .leftOption: return l10n.t("layoutSwitchKey.leftOption")
        case .leftControl: return l10n.t("layoutSwitchKey.leftControl")
        case .leftCommand: return l10n.t("layoutSwitchKey.leftCommand")
        case .leftShift: return l10n.t("layoutSwitchKey.leftShift")
        case .fn: return l10n.t("layoutSwitchKey.fn")
        }
    }
}
