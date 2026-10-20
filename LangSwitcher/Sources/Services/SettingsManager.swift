import Foundation
import SwiftUI

// MARK: - Smart Conversion Mode
/// Determines behavior when no text is selected and the hotkey is pressed

enum SmartConversionMode: Int, CaseIterable, Codable {
    case lastWord = 0      // Convert only last word (current behavior)
    case greedyLine = 1    // Select to line start, find boundary, convert wrong-layout tail
    case disabled = 2      // No smart conversion — only works with explicit selection
    
    @MainActor var displayName: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .lastWord: return l10n.t("smartMode.lastWord.name")
        case .greedyLine: return l10n.t("smartMode.greedyLine.name")
        case .disabled: return l10n.t("smartMode.disabled.name")
        }
    }
    
    @MainActor var description: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .lastWord: return l10n.t("smartMode.lastWord.desc")
        case .greedyLine: return l10n.t("smartMode.greedyLine.desc")
        case .disabled: return l10n.t("smartMode.disabled.desc")
        }
    }
}

// MARK: - Layout Switch Mode
/// Controls whether the keyboard layout is automatically switched after a hotkey-triggered conversion

enum LayoutSwitchMode: Int, CaseIterable, Codable {
    case always = 0           // Always switch layout when hotkey is pressed
    case ifLastWordConverted = 1  // Switch if the last word was in wrong layout and got reconverted
    case ifAnyWordConverted = 2   // Switch if any word in the converted text needed reconversion
    
    @MainActor var displayName: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .always: return l10n.t("layoutSwitchMode.always.name")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.name")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.name")
        }
    }
    
    @MainActor var description: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .always: return l10n.t("layoutSwitchMode.always.desc")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.desc")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.desc")
        }
    }
}

// MARK: - Status Bar Icon Style
/// Style of the icon displayed in the macOS status bar (menu bar)

enum StatusBarIconStyle: Int, CaseIterable, Codable {
    case languageBadge = 0 // Language code in a frame (e.g. RU, EN)
    case keyboardIcon = 1  // System keyboard icon
    
    @MainActor var displayName: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .languageBadge: return l10n.t("settings.iconStyle.languageBadge")
        case .keyboardIcon: return l10n.t("settings.iconStyle.keyboardIcon")
        }
    }
}

// MARK: - Settings Manager
// Persists user preferences via UserDefaults

@MainActor
final class SettingsManager: ObservableObject {
    
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Published Properties
    
    @Published var enabledLayouts: [KeyboardLayout] {
        didSet { saveLayouts() }
    }
    
    /// true = double-shift mode, false = regular modifier+key hotkey
    @Published var useDoubleShift: Bool {
        didSet {
            defaults.set(useDoubleShift, forKey: Keys.useDoubleShift)
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }
    
    @Published var hotkeyKeyCode: UInt16 {
        didSet {
            defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
            if !useDoubleShift {
                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
            }
        }
    }
    
    @Published var hotkeyModifiers: UInt {
        didSet {
            defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers)
            if !useDoubleShift {
                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
            }
        }
    }
    
    /// Dedicated single key for toggling/cycling keyboard layout directly
    @Published var layoutSwitchKey: LayoutSwitchKey {
        didSet {
            defaults.set(layoutSwitchKey.rawValue, forKey: Keys.layoutSwitchKey)
            NotificationCenter.default.post(name: .layoutSwitchKeyChanged, object: nil)
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }
    
    @Published var showNotifications: Bool {
        didSet { defaults.set(showNotifications, forKey: Keys.showNotifications) }
    }
    
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }
    
    @Published var smartConversionMode: SmartConversionMode {
        didSet { defaults.set(smartConversionMode.rawValue, forKey: Keys.smartConversionMode) }
    }
    
    @Published var layoutSwitchMode: LayoutSwitchMode {
        didSet { defaults.set(layoutSwitchMode.rawValue, forKey: Keys.layoutSwitchMode) }
    }
    
    @Published var conversionCount: Int {
        didSet { defaults.set(conversionCount, forKey: Keys.conversionCount) }
    }
    
    /// Whether conversion logging is enabled. Default: OFF (privacy first).
    @Published var loggingEnabled: Bool {
        didSet { defaults.set(loggingEnabled, forKey: Keys.loggingEnabled) }
    }
    
    /// Max number of log entries to keep. 0 = unlimited. Default: 100.
    @Published var logMaxEntries: Int {
        didSet { defaults.set(logMaxEntries, forKey: Keys.logMaxEntries) }
    }
    
    /// Whether auto-correction on word boundary (space/enter/punctuation) is enabled.
    @Published var autoCorrectionEnabled: Bool {
        didSet {
            defaults.set(autoCorrectionEnabled, forKey: Keys.autoCorrectionEnabled)
            NotificationCenter.default.post(name: .autoCorrectionSettingsChanged, object: nil)
        }
    }
    
    /// Whether to use NSSpellChecker to validate converted words (reduces false positives).
    @Published var autoCorrectionUseSpellCheck: Bool {
        didSet { defaults.set(autoCorrectionUseSpellCheck, forKey: Keys.autoCorrectionUseSpellCheck) }
    }
    
    /// Whether to switch the keyboard layout after auto-correction.
    @Published var autoCorrectionSwitchLayout: Bool {
        didSet { defaults.set(autoCorrectionSwitchLayout, forKey: Keys.autoCorrectionSwitchLayout) }
    }

    /// Style of icon in the macOS menu bar. Default: language badge in a frame (RU, EN).
    @Published var statusBarIconStyle: StatusBarIconStyle {
        didSet {
            defaults.set(statusBarIconStyle.rawValue, forKey: Keys.statusBarIconStyle)
            NotificationCenter.default.post(name: .statusBarIconStyleChanged, object: nil)
        }
    }

    /// Thought Recovery: reconstruct a whole line span by span instead of
    /// converting one wrong-layout tail. Default: ON.
    @Published var thoughtRecoveryEnabled: Bool {
        didSet { defaults.set(thoughtRecoveryEnabled, forKey: Keys.thoughtRecoveryEnabled) }
    }

    /// Show the reconstruction (with alternatives) before applying it, instead
    /// of pasting straight into the app. Default: OFF.
    @Published var thoughtRecoveryPreview: Bool {
        didSet { defaults.set(thoughtRecoveryPreview, forKey: Keys.thoughtRecoveryPreview) }
    }

    /// How many lines Thought Recovery rewrote.
    @Published var recoveryCount: Int {
        didSet { defaults.set(recoveryCount, forKey: Keys.recoveryCount) }
    }

    /// How many recoveries the user reverted.
    @Published var recoveryRevertCount: Int {
        didSet { defaults.set(recoveryRevertCount, forKey: Keys.recoveryRevertCount) }
    }

    // MARK: - Computed
    
    /// Share of recoveries the user reverted.
    var recoveryRevertRate: Double {
        guard recoveryCount > 0 else { return 0 }
        return Double(recoveryRevertCount) / Double(recoveryCount)
    }
    
    var hotkeyModifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: hotkeyModifiers) }
        set { hotkeyModifiers = newValue.rawValue }
    }
    
    var hotkeyDescription: String {
        if useDoubleShift {
            return "⇧⇧ (Double Shift)"
        }
        let mods = HotkeyManager.modifierFlagsToString(hotkeyModifierFlags)
        let key = HotkeyManager.keyCodeToString(hotkeyKeyCode)
        return "\(mods)\(key)"
    }
    
    // MARK: - Keys
    
    private enum Keys {
        static let enabledLayouts = "enabledLayouts"
        static let useDoubleShift = "useDoubleShift"
        static let layoutSwitchKey = "layoutSwitchKey"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
        static let showNotifications = "showNotifications"
        static let playSounds = "playSounds"
        static let smartConversionMode = "smartConversionMode"
        static let layoutSwitchMode = "layoutSwitchMode"
        static let conversionCount = "conversionCount"
        static let loggingEnabled = "loggingEnabled"
        static let logMaxEntries = "logMaxEntries"
        static let autoCorrectionEnabled = "autoCorrectionEnabled"
        static let autoCorrectionUseSpellCheck = "autoCorrectionUseSpellCheck"
        static let autoCorrectionSwitchLayout = "autoCorrectionSwitchLayout"
        static let statusBarIconStyle = "statusBarIconStyle"
        static let thoughtRecoveryEnabled = "thoughtRecoveryEnabled"
        static let thoughtRecoveryPreview = "thoughtRecoveryPreview"
        static let recoveryCount = "recoveryCount"
        static let recoveryRevertCount = "recoveryRevertCount"
    }
    
    // MARK: - Init
    
    private init() {
        // Default: double-shift mode
        let savedUseDoubleShift = defaults.object(forKey: Keys.useDoubleShift) as? Bool
        self.useDoubleShift = savedUseDoubleShift ?? true  // Default ON
        
        let savedLayoutSwitchKey = defaults.string(forKey: Keys.layoutSwitchKey)
        self.layoutSwitchKey = savedLayoutSwitchKey.flatMap { LayoutSwitchKey(rawValue: $0) } ?? .disabled
        
        // Fallback hotkey settings (Option+S) for regular mode
        let savedKeyCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
        self.hotkeyKeyCode = UInt16(savedKeyCode ?? 0x01) // 0x01 = S key
        
        let savedMods = defaults.object(forKey: Keys.hotkeyModifiers) as? UInt
        self.hotkeyModifiers = savedMods ?? NSEvent.ModifierFlags.option.rawValue
        
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.showNotifications = defaults.object(forKey: Keys.showNotifications) as? Bool ?? true
        self.playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        let savedSmartMode = defaults.object(forKey: Keys.smartConversionMode) as? Int
        self.smartConversionMode = SmartConversionMode(rawValue: savedSmartMode ?? 1) ?? .greedyLine // Default: greedy
        
        let savedLayoutSwitchMode = defaults.object(forKey: Keys.layoutSwitchMode) as? Int
        self.layoutSwitchMode = LayoutSwitchMode(rawValue: savedLayoutSwitchMode ?? 0) ?? .always // Default: always
        
        self.conversionCount = defaults.integer(forKey: Keys.conversionCount)
        self.loggingEnabled = defaults.object(forKey: Keys.loggingEnabled) as? Bool ?? false  // Default: OFF
        self.logMaxEntries = defaults.object(forKey: Keys.logMaxEntries) as? Int ?? 100       // Default: 100
        self.autoCorrectionEnabled = defaults.object(forKey: Keys.autoCorrectionEnabled) as? Bool ?? false     // Default: OFF
        self.autoCorrectionUseSpellCheck = defaults.object(forKey: Keys.autoCorrectionUseSpellCheck) as? Bool ?? true  // Default: ON
        self.autoCorrectionSwitchLayout = defaults.object(forKey: Keys.autoCorrectionSwitchLayout) as? Bool ?? true    // Default: ON
        
        self.thoughtRecoveryEnabled = defaults.object(forKey: Keys.thoughtRecoveryEnabled) as? Bool ?? true  // Default: ON
        self.thoughtRecoveryPreview = defaults.object(forKey: Keys.thoughtRecoveryPreview) as? Bool ?? false // Default: OFF
        self.recoveryCount = defaults.integer(forKey: Keys.recoveryCount)
        self.recoveryRevertCount = defaults.integer(forKey: Keys.recoveryRevertCount)
        
        let savedIconStyle = defaults.object(forKey: Keys.statusBarIconStyle) as? Int
        self.statusBarIconStyle = StatusBarIconStyle(rawValue: savedIconStyle ?? 0) ?? .languageBadge
        
        // Load layouts: validate against actual system installed layouts
        let systemLayouts = KeyboardLayoutDetector.getInstalledLayouts()
        let systemIDs = Set(systemLayouts.map { $0.id.lowercased() })
        
        if let data = defaults.data(forKey: Keys.enabledLayouts),
           let savedLayouts = try? JSONDecoder().decode([KeyboardLayout].self, from: data),
           !savedLayouts.isEmpty {
            let valid = savedLayouts.filter { systemIDs.contains($0.id.lowercased()) }
            if valid.count >= 2 {
                self.enabledLayouts = valid
            } else {
                self.enabledLayouts = systemLayouts
                if let encoded = try? JSONEncoder().encode(systemLayouts) {
                    defaults.set(encoded, forKey: Keys.enabledLayouts)
                }
            }
        } else {
            self.enabledLayouts = systemLayouts
        }
    }
    
    // MARK: - Methods
    
    func refreshSystemLayouts() {
        enabledLayouts = KeyboardLayoutDetector.getInstalledLayouts()
    }
    
    func incrementConversionCount() {
        conversionCount += 1
    }

    func incrementRecoveryCount() {
        recoveryCount += 1
    }

    func incrementRecoveryRevertCount() {
        recoveryRevertCount += 1
    }
    
    private func saveLayouts() {
        if let data = try? JSONEncoder().encode(enabledLayouts) {
            defaults.set(data, forKey: Keys.enabledLayouts)
        }
    }
}
