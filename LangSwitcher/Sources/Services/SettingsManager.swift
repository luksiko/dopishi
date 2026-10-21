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
    case never = 3            // Never switch layout after conversion
    
    @MainActor var displayName: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .always: return l10n.t("layoutSwitchMode.always.name")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.name")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.name")
        case .never: return l10n.t("layoutSwitchMode.never.name")
        }
    }
    
    @MainActor var description: String {
        let l10n = LocalizationManager.shared
        switch self {
        case .always: return l10n.t("layoutSwitchMode.always.desc")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.desc")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.desc")
        case .never: return l10n.t("layoutSwitchMode.never.desc")
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

    /// Whether to fix two initial capitals in words (e.g. "ПРобую" -> "Пробую", "THis" -> "This"). Default: true.
    @Published var autoCorrectionFixTwoInitialCapitals: Bool {
        didSet { defaults.set(autoCorrectionFixTwoInitialCapitals, forKey: Keys.autoCorrectionFixTwoInitialCapitals) }
    }

    /// Whether real-time word autocompletion HUD is enabled. Default: true.
    @Published var autoCompletionEnabled: Bool {
        didSet {
            defaults.set(autoCompletionEnabled, forKey: Keys.autoCompletionEnabled)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Key used to accept autocompletion suggestion. Default: .tab.
    @Published var autoCompletionAcceptKey: AutocompletionAcceptKey {
        didSet {
            defaults.set(autoCompletionAcceptKey.rawValue, forKey: Keys.autoCompletionAcceptKey)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Custom key code when acceptKey is .custom. Default: 0x30 (Tab).
    @Published var autoCompletionCustomKeyCode: UInt16 {
        didSet {
            defaults.set(Int(autoCompletionCustomKeyCode), forKey: Keys.autoCompletionCustomKeyCode)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Custom modifiers when acceptKey is .custom. Default: 0.
    @Published var autoCompletionCustomModifiers: UInt {
        didSet {
            defaults.set(autoCompletionCustomModifiers, forKey: Keys.autoCompletionCustomModifiers)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Key for accepting the entire completion phrase. Default: .shiftTab.
    @Published var autoCompletionAcceptAllKey: AutocompletionAcceptAllKey {
        didSet {
            defaults.set(autoCompletionAcceptAllKey.rawValue, forKey: Keys.autoCompletionAcceptAllKey)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Custom key code when acceptAllKey is .custom. Default: 0x30 (Tab).
    @Published var autoCompletionCustomAcceptAllKeyCode: UInt16 {
        didSet {
            defaults.set(Int(autoCompletionCustomAcceptAllKeyCode), forKey: Keys.autoCompletionCustomAcceptAllKeyCode)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Custom modifiers when acceptAllKey is .custom. Default: Shift.
    @Published var autoCompletionCustomAcceptAllModifiers: UInt {
        didSet {
            defaults.set(autoCompletionCustomAcceptAllModifiers, forKey: Keys.autoCompletionCustomAcceptAllModifiers)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Max autocompletion suggestions to show (1...6). Default: 4.
    @Published var autoCompletionMaxSuggestions: Int {
        didSet { defaults.set(autoCompletionMaxSuggestions, forKey: Keys.autoCompletionMaxSuggestions) }
    }

    /// Minimum prefix length before showing completions (2...5). Default: 2.
    @Published var autoCompletionMinPrefixLength: Int {
        didSet { defaults.set(autoCompletionMinPrefixLength, forKey: Keys.autoCompletionMinPrefixLength) }
    }

    /// Whether number keys (1...5) select completions directly. Default: true.
    @Published var autoCompletionUseNumberShortcuts: Bool {
        didSet { defaults.set(autoCompletionUseNumberShortcuts, forKey: Keys.autoCompletionUseNumberShortcuts) }
    }

    /// Whether to include trailing space when accepting a single word. Default: true.
    @Published var autoCompletionIncludeTrailingSpace: Bool {
        didSet { defaults.set(autoCompletionIncludeTrailingSpace, forKey: Keys.autoCompletionIncludeTrailingSpace) }
    }

    /// Whether the primary accept key accepts the entire phrase. Default: false (next word).
    @Published var autoCompletionAcceptEntirePhrase: Bool {
        didSet { defaults.set(autoCompletionAcceptEntirePhrase, forKey: Keys.autoCompletionAcceptEntirePhrase) }
    }

    /// Whether to include trailing punctuation when accepting a single word. Default: true.
    @Published var autoCompletionIncludeTrailingPunctuation: Bool {
        didSet { defaults.set(autoCompletionIncludeTrailingPunctuation, forKey: Keys.autoCompletionIncludeTrailingPunctuation) }
    }

    /// Action when Escape is pressed while a suggestion is showing. Default: .pauseFewSeconds.
    @Published var autoCompletionEscapeAction: AutocompletionEscapeAction {
        didSet {
            defaults.set(autoCompletionEscapeAction.rawValue, forKey: Keys.autoCompletionEscapeAction)
        }
    }

    /// Shortcut to force-activate completions at cursor. Default: Control + Section/Grave.
    @Published var autoCompletionForceActivateKeyCode: UInt16 {
        didSet { defaults.set(Int(autoCompletionForceActivateKeyCode), forKey: Keys.autoCompletionForceActivateKeyCode) }
    }
    @Published var autoCompletionForceActivateModifiers: UInt {
        didSet { defaults.set(autoCompletionForceActivateModifiers, forKey: Keys.autoCompletionForceActivateModifiers) }
    }
    @Published var autoCompletionForceActivateEnabled: Bool {
        didSet { defaults.set(autoCompletionForceActivateEnabled, forKey: Keys.autoCompletionForceActivateEnabled) }
    }

    /// Shortcut to temporarily toggle completions in the current app. Default: Control + Option + Command + Section.
    @Published var autoCompletionToggleCurrentAppKeyCode: UInt16 {
        didSet { defaults.set(Int(autoCompletionToggleCurrentAppKeyCode), forKey: Keys.autoCompletionToggleCurrentAppKeyCode) }
    }
    @Published var autoCompletionToggleCurrentAppModifiers: UInt {
        didSet { defaults.set(autoCompletionToggleCurrentAppModifiers, forKey: Keys.autoCompletionToggleCurrentAppModifiers) }
    }
    @Published var autoCompletionToggleCurrentAppEnabled: Bool {
        didSet { defaults.set(autoCompletionToggleCurrentAppEnabled, forKey: Keys.autoCompletionToggleCurrentAppEnabled) }
    }

    /// Shortcut to toggle completions globally.
    @Published var autoCompletionToggleGlobalKeyCode: UInt16 {
        didSet { defaults.set(Int(autoCompletionToggleGlobalKeyCode), forKey: Keys.autoCompletionToggleGlobalKeyCode) }
    }
    @Published var autoCompletionToggleGlobalModifiers: UInt {
        didSet { defaults.set(autoCompletionToggleGlobalModifiers, forKey: Keys.autoCompletionToggleGlobalModifiers) }
    }
    @Published var autoCompletionToggleGlobalEnabled: Bool {
        didSet {
            defaults.set(autoCompletionToggleGlobalEnabled, forKey: Keys.autoCompletionToggleGlobalEnabled)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Whether cross-layout suggestions (e.g. ghbd -> привет) are included. Default: true.
    @Published var autoCompletionIncludeCrossLayout: Bool {
        didSet { defaults.set(autoCompletionIncludeCrossLayout, forKey: Keys.autoCompletionIncludeCrossLayout) }
    }

    /// Whether to suggest profanity and curse words in autocompletion. Default: false (OFF).
    @Published var autoCompletionSuggestProfanity: Bool {
        didSet { defaults.set(autoCompletionSuggestProfanity, forKey: Keys.autoCompletionSuggestProfanity) }
    }

    /// Delay before showing autocompletion popup (in seconds). Default: 0.035 (35 ms).
    @Published var autoCompletionDelay: Double {
        didSet { defaults.set(autoCompletionDelay, forKey: Keys.autoCompletionDelay) }
    }

    // MARK: - AI Assistant Settings

    /// Whether predictive AI continuation (2-4 words) is enabled. Default: true.
    @Published var aiPredictiveEnabled: Bool {
        didSet {
            defaults.set(aiPredictiveEnabled, forKey: Keys.aiPredictiveEnabled)
            NotificationCenter.default.post(name: .aiSettingsChanged, object: nil)
        }
    }

    /// Whether a subtle floating indicator badge is shown in the top-left of the active text field. Default: true.
    @Published var showFieldAnchorBadge: Bool {
        didSet { defaults.set(showFieldAnchorBadge, forKey: Keys.showFieldAnchorBadge) }
    }

    /// Whether AI is automatically disabled when running on battery power. Default: true.
    @Published var aiBatteryModeEnabled: Bool {
        didSet {
            defaults.set(aiBatteryModeEnabled, forKey: Keys.aiBatteryModeEnabled)
            NotificationCenter.default.post(name: .aiSettingsChanged, object: nil)
        }
    }

    /// Maximum number of words in an AI prediction (2...4). Default: 3.
    @Published var aiMaxContinuationWords: Int {
        didSet { defaults.set(aiMaxContinuationWords, forKey: Keys.aiMaxContinuationWords) }
    }

    /// Typing debounce delay for AI continuation (in seconds). Default: 0.350 (350 ms).
    @Published var aiDebounceDelay: Double {
        didSet { defaults.set(aiDebounceDelay, forKey: Keys.aiDebounceDelay) }
    }

    /// Whether to stream token generation progressively for lower Time-to-First-Token. Default: true.
    @Published var aiStreamingEnabled: Bool {
        didSet { defaults.set(aiStreamingEnabled, forKey: Keys.aiStreamingEnabled) }
    }

    /// Whether to extract screen context (recent chat messages / window text) for AI predictions. Default: true.
    @Published var aiScreenContextEnabled: Bool {
        didSet {
            defaults.set(aiScreenContextEnabled, forKey: Keys.aiScreenContextEnabled)
            NotificationCenter.default.post(name: .aiSettingsChanged, object: nil)
        }
    }

    /// User-defined system instructions for the AI assistant.
    @Published var aiCustomInstructions: String {
        didSet { defaults.set(aiCustomInstructions, forKey: Keys.aiCustomInstructions) }
    }

    /// Whether writing history and style personalization is enabled. Default: true.
    @Published var aiPersonalizationEnabled: Bool {
        didSet { defaults.set(aiPersonalizationEnabled, forKey: Keys.aiPersonalizationEnabled) }
    }

    /// Per-application custom instructions, vocabulary, and toggles.
    @Published var perAppAISettings: [String: AppAISettings] {
        didSet { savePerAppAISettings() }
    }

    /// Currently active/selected model identifier. Default: "qwen2.5-0.5b".
    @Published var selectedModelId: String {
        didSet {
            defaults.set(selectedModelId, forKey: Keys.selectedModelId)
            NotificationCenter.default.post(name: .aiSettingsChanged, object: nil)
        }
    }

    /// Path to user-specified local GGUF model file.
    @Published var customModelPath: String {
        didSet {
            defaults.set(customModelPath, forKey: Keys.customModelPath)
            NotificationCenter.default.post(name: .aiSettingsChanged, object: nil)
        }
    }

    /// Total characters saved via autocompletion and autocorrection.
    @Published var savedCharactersCount: Int {
        didSet { defaults.set(savedCharactersCount, forKey: Keys.savedCharactersCount) }
    }

    /// Total keystrokes/clicks saved via autocompletion.
    @Published var savedClicksCount: Int {
        didSet { defaults.set(savedClicksCount, forKey: Keys.savedClicksCount) }
    }

    /// Computed check: whether AI inference is allowed based on preferences and battery state.
    var isAIAllowed: Bool {
        guard aiPredictiveEnabled else { return false }
        if aiBatteryModeEnabled && PowerService.shared.isOnBattery {
            return false
        }
        return true
    }

    /// Autocompletion display presentation style (popup HUD, inline ghost text, or both). Default: .both.
    @Published var autoCompletionDisplayMode: AutocompletionDisplayMode {
        didSet {
            defaults.set(autoCompletionDisplayMode.rawValue, forKey: Keys.autoCompletionDisplayMode)
            NotificationCenter.default.post(name: .autoCompletionSettingsChanged, object: nil)
        }
    }

    /// Applications where autocompletion and auto-correction are disabled.
    @Published var excludedAppBundleIDs: [String] {
        didSet {
            defaults.set(excludedAppBundleIDs, forKey: Keys.excludedAppBundleIDs)
            NotificationCenter.default.post(name: .autoCorrectionSettingsChanged, object: nil)
        }
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
    
    /// Determines whether the given event matches the configured autocompletion accept key (next word)
    func isAutocompletionAcceptKey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let nonModFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
        switch autoCompletionAcceptKey {
        case .tab:
            let hasShift = flags.contains(.maskShift)
            return keyCode == 0x30 && nonModFlags.isEmpty && !hasShift
        case .space:
            return keyCode == 0x31 && nonModFlags.isEmpty
        case .enter:
            return keyCode == 0x24 && nonModFlags.isEmpty
        case .rightArrow:
            return keyCode == 0x7C && nonModFlags.isEmpty
        case .custom:
            return matchKeyAndModifiers(keyCode: keyCode, flags: flags, targetKeyCode: autoCompletionCustomKeyCode, targetModifiers: autoCompletionCustomModifiers)
        }
    }

    /// Determines whether the given event matches the configured accept all key (entire phrase)
    func isAutocompletionAcceptAllKey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        let nonModFlags = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
        switch autoCompletionAcceptAllKey {
        case .cmdSection:
            let hasCmd = flags.contains(.maskCommand)
            let otherMods = flags.intersection([.maskAlternate, .maskControl, .maskShift])
            // 0x0A is § on ISO keyboards, 0x32 is ` / ~ on ANSI
            let isSectionOrGrave = (keyCode == 0x0A || keyCode == 0x32)
            return isSectionOrGrave && hasCmd && otherMods.isEmpty
        case .shiftTab:
            let hasShift = flags.contains(.maskShift)
            return keyCode == 0x30 && hasShift && nonModFlags.isEmpty
        case .cmdReturn:
            let hasCmd = flags.contains(.maskCommand)
            let otherMods = flags.intersection([.maskAlternate, .maskControl, .maskShift])
            return keyCode == 0x24 && hasCmd && otherMods.isEmpty
        case .optionTab:
            let hasOpt = flags.contains(.maskAlternate)
            let otherMods = flags.intersection([.maskCommand, .maskControl, .maskShift])
            return keyCode == 0x30 && hasOpt && otherMods.isEmpty
        case .custom:
            return matchKeyAndModifiers(keyCode: keyCode, flags: flags, targetKeyCode: autoCompletionCustomAcceptAllKeyCode, targetModifiers: autoCompletionCustomAcceptAllModifiers)
        }
    }

    /// Helper to match keyCode and modifier flags against recorded target shortcut
    func matchKeyAndModifiers(keyCode: UInt16, flags: CGEventFlags, targetKeyCode: UInt16, targetModifiers: UInt) -> Bool {
        guard keyCode == targetKeyCode else { return false }
        let relevantMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
        let actualMods = UInt(flags.rawValue & relevantMask)
        let expectedNSEventMods = NSEvent.ModifierFlags(rawValue: targetModifiers).intersection(.deviceIndependentFlagsMask)
        let actualNSEventMods = NSEvent.ModifierFlags(rawValue: actualMods).intersection(.deviceIndependentFlagsMask)
        return actualNSEventMods == expectedNSEventMods
    }

    /// Determines whether the given event matches the force-activate completions shortcut
    func isAutocompletionForceActivateKey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard autoCompletionForceActivateEnabled else { return false }
        return matchKeyAndModifiers(keyCode: keyCode, flags: flags, targetKeyCode: autoCompletionForceActivateKeyCode, targetModifiers: autoCompletionForceActivateModifiers)
    }

    /// Determines whether the given event matches the shortcut to toggle completions for current app
    func isAutocompletionToggleCurrentAppKey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard autoCompletionToggleCurrentAppEnabled else { return false }
        return matchKeyAndModifiers(keyCode: keyCode, flags: flags, targetKeyCode: autoCompletionToggleCurrentAppKeyCode, targetModifiers: autoCompletionToggleCurrentAppModifiers)
    }

    /// Determines whether the given event matches the shortcut to toggle completions globally
    func isAutocompletionToggleGlobalKey(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard autoCompletionToggleGlobalEnabled else { return false }
        return matchKeyAndModifiers(keyCode: keyCode, flags: flags, targetKeyCode: autoCompletionToggleGlobalKeyCode, targetModifiers: autoCompletionToggleGlobalModifiers)
    }
    
    /// Keep the global toggle reachable even when both typing features are off.
    var needsKeyboardMonitoring: Bool {
        autoCorrectionEnabled || autoCompletionEnabled || autoCompletionToggleGlobalEnabled
    }

    // MARK: - Excluded Apps Management
    
    func addExcludedApp(bundleID: String) {
        guard !bundleID.isEmpty, !excludedAppBundleIDs.contains(bundleID) else { return }
        excludedAppBundleIDs.append(bundleID)
    }
    
    func removeExcludedApp(bundleID: String) {
        excludedAppBundleIDs.removeAll { $0 == bundleID }
    }
    
    func isAppExcluded(bundleID: String?) -> Bool {
        guard let bid = bundleID else { return false }
        return excludedAppBundleIDs.contains(bid)
    }
    
    // MARK: - Per-App AI Settings Management
    
    func aiInstructions(for bundleID: String?, language: String? = nil) -> String {
        var parts: [String] = []
        let global = aiCustomInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !global.isEmpty {
            parts.append(global)
        }
        if let bid = bundleID, let appSetting = perAppAISettings[bid] {
            let appInst = appSetting.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !appInst.isEmpty {
                parts.append(appInst)
            }
            if !appSetting.customVocabulary.isEmpty {
                let vocabList = appSetting.customVocabulary.joined(separator: ", ")
                parts.append("Preferred terminology: \(vocabList)")
            }
        }
        if aiPersonalizationEnabled, let bid = bundleID {
            if let stylePrompt = UserTextHistoryStore.shared.stylePrompt(for: bid, language: language) {
                parts.append(stylePrompt)
            }
        }
        return parts.joined(separator: "\n")
    }
    
    func isAIEnabled(for bundleID: String?) -> Bool {
        guard isAIAllowed else { return false }
        if let bid = bundleID, let appSetting = perAppAISettings[bid], !appSetting.isAIEnabled {
            return false
        }
        return true
    }
    
    func setAppAISettings(_ settings: AppAISettings) {
        perAppAISettings[settings.bundleID] = settings
    }
    
    func removeAppAISettings(bundleID: String) {
        perAppAISettings.removeValue(forKey: bundleID)
    }
    
    private func savePerAppAISettings() {
        if let data = try? JSONEncoder().encode(perAppAISettings) {
            defaults.set(data, forKey: Keys.perAppAISettings)
        }
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
        static let autoCorrectionFixTwoInitialCapitals = "autoCorrectionFixTwoInitialCapitals"
        static let autoCompletionEnabled = "autoCompletionEnabled"
        static let autoCompletionAcceptKey = "autoCompletionAcceptKey"
        static let autoCompletionCustomKeyCode = "autoCompletionCustomKeyCode"
        static let autoCompletionCustomModifiers = "autoCompletionCustomModifiers"
        static let autoCompletionAcceptAllKey = "autoCompletionAcceptAllKey"
        static let autoCompletionCustomAcceptAllKeyCode = "autoCompletionCustomAcceptAllKeyCode"
        static let autoCompletionCustomAcceptAllModifiers = "autoCompletionCustomAcceptAllModifiers"
        static let autoCompletionIncludeTrailingSpace = "autoCompletionIncludeTrailingSpace"
        static let autoCompletionAcceptEntirePhrase = "autoCompletionAcceptEntirePhrase"
        static let autoCompletionIncludeTrailingPunctuation = "autoCompletionIncludeTrailingPunctuation"
        static let autoCompletionEscapeAction = "autoCompletionEscapeAction"
        static let autoCompletionForceActivateKeyCode = "autoCompletionForceActivateKeyCode"
        static let autoCompletionForceActivateModifiers = "autoCompletionForceActivateModifiers"
        static let autoCompletionForceActivateEnabled = "autoCompletionForceActivateEnabled"
        static let autoCompletionToggleCurrentAppKeyCode = "autoCompletionToggleCurrentAppKeyCode"
        static let autoCompletionToggleCurrentAppModifiers = "autoCompletionToggleCurrentAppModifiers"
        static let autoCompletionToggleCurrentAppEnabled = "autoCompletionToggleCurrentAppEnabled"
        static let autoCompletionToggleGlobalKeyCode = "autoCompletionToggleGlobalKeyCode"
        static let autoCompletionToggleGlobalModifiers = "autoCompletionToggleGlobalModifiers"
        static let autoCompletionToggleGlobalEnabled = "autoCompletionToggleGlobalEnabled"
        static let autoCompletionMaxSuggestions = "autoCompletionMaxSuggestions"
        static let autoCompletionMinPrefixLength = "autoCompletionMinPrefixLength"
        static let autoCompletionUseNumberShortcuts = "autoCompletionUseNumberShortcuts"
        static let autoCompletionIncludeCrossLayout = "autoCompletionIncludeCrossLayout"
        static let autoCompletionSuggestProfanity = "autoCompletionSuggestProfanity"
        static let autoCompletionDisplayMode = "autoCompletionDisplayMode"
        static let autoCompletionDelay = "autoCompletionDelay"
        static let excludedAppBundleIDs = "excludedAppBundleIDs"
        static let statusBarIconStyle = "statusBarIconStyle"
        static let thoughtRecoveryEnabled = "thoughtRecoveryEnabled"
        static let thoughtRecoveryPreview = "thoughtRecoveryPreview"
        static let recoveryCount = "recoveryCount"
        static let recoveryRevertCount = "recoveryRevertCount"
        static let aiPredictiveEnabled = "aiPredictiveEnabled"
        static let showFieldAnchorBadge = "showFieldAnchorBadge"
        static let aiBatteryModeEnabled = "aiBatteryModeEnabled"
        static let aiMaxContinuationWords = "aiMaxContinuationWords"
        static let aiDebounceDelay = "aiDebounceDelay"
        static let aiStreamingEnabled = "aiStreamingEnabled"
        static let aiScreenContextEnabled = "aiScreenContextEnabled"
        static let aiCustomInstructions = "aiCustomInstructions"
        static let aiPersonalizationEnabled = "aiPersonalizationEnabled"
        static let perAppAISettings = "perAppAISettings"
        static let selectedModelId = "selectedModelId"
        static let customModelPath = "customModelPath"
        static let savedCharactersCount = "savedCharactersCount"
        static let savedClicksCount = "savedClicksCount"
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
        self.autoCorrectionFixTwoInitialCapitals = defaults.object(forKey: Keys.autoCorrectionFixTwoInitialCapitals) as? Bool ?? true // Default: ON
        
        self.autoCompletionEnabled = defaults.object(forKey: Keys.autoCompletionEnabled) as? Bool ?? true      // Default: ON
        let savedAcceptKey = defaults.string(forKey: Keys.autoCompletionAcceptKey)
        self.autoCompletionAcceptKey = savedAcceptKey.flatMap { AutocompletionAcceptKey(rawValue: $0) } ?? .tab
        let savedCustomCode = defaults.object(forKey: Keys.autoCompletionCustomKeyCode) as? Int
        self.autoCompletionCustomKeyCode = UInt16(savedCustomCode ?? 0x30)
        self.autoCompletionCustomModifiers = defaults.object(forKey: Keys.autoCompletionCustomModifiers) as? UInt ?? 0
        let savedAcceptAllKey = defaults.string(forKey: Keys.autoCompletionAcceptAllKey)
        self.autoCompletionAcceptAllKey = savedAcceptAllKey.flatMap { AutocompletionAcceptAllKey(rawValue: $0) } ?? .shiftTab
        let savedCustomAllCode = defaults.object(forKey: Keys.autoCompletionCustomAcceptAllKeyCode) as? Int
        self.autoCompletionCustomAcceptAllKeyCode = UInt16(savedCustomAllCode ?? 0x30)
        self.autoCompletionCustomAcceptAllModifiers = defaults.object(forKey: Keys.autoCompletionCustomAcceptAllModifiers) as? UInt ?? NSEvent.ModifierFlags.shift.rawValue
        self.autoCompletionMaxSuggestions = defaults.object(forKey: Keys.autoCompletionMaxSuggestions) as? Int ?? 4
        self.autoCompletionMinPrefixLength = defaults.object(forKey: Keys.autoCompletionMinPrefixLength) as? Int ?? 2
        self.autoCompletionUseNumberShortcuts = defaults.object(forKey: Keys.autoCompletionUseNumberShortcuts) as? Bool ?? true
        self.autoCompletionIncludeTrailingSpace = defaults.object(forKey: Keys.autoCompletionIncludeTrailingSpace) as? Bool ?? true
        self.autoCompletionAcceptEntirePhrase = defaults.object(forKey: Keys.autoCompletionAcceptEntirePhrase) as? Bool ?? false
        self.autoCompletionIncludeTrailingPunctuation = defaults.object(forKey: Keys.autoCompletionIncludeTrailingPunctuation) as? Bool ?? true
        let savedEscapeAction = defaults.string(forKey: Keys.autoCompletionEscapeAction)
        self.autoCompletionEscapeAction = savedEscapeAction.flatMap { AutocompletionEscapeAction(rawValue: $0) } ?? .pauseFewSeconds
        
        let savedForceCode = defaults.object(forKey: Keys.autoCompletionForceActivateKeyCode) as? Int
        self.autoCompletionForceActivateKeyCode = UInt16(savedForceCode ?? 0x0A) // 0x0A = § or 0x32 = `
        self.autoCompletionForceActivateModifiers = defaults.object(forKey: Keys.autoCompletionForceActivateModifiers) as? UInt ?? NSEvent.ModifierFlags.control.rawValue
        self.autoCompletionForceActivateEnabled = defaults.object(forKey: Keys.autoCompletionForceActivateEnabled) as? Bool ?? true
        
        let savedAppCode = defaults.object(forKey: Keys.autoCompletionToggleCurrentAppKeyCode) as? Int
        self.autoCompletionToggleCurrentAppKeyCode = UInt16(savedAppCode ?? 0x0A)
        self.autoCompletionToggleCurrentAppModifiers = defaults.object(forKey: Keys.autoCompletionToggleCurrentAppModifiers) as? UInt ?? (NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue | NSEvent.ModifierFlags.command.rawValue)
        self.autoCompletionToggleCurrentAppEnabled = defaults.object(forKey: Keys.autoCompletionToggleCurrentAppEnabled) as? Bool ?? true
        
        let savedGlobalCode = defaults.object(forKey: Keys.autoCompletionToggleGlobalKeyCode) as? Int
        self.autoCompletionToggleGlobalKeyCode = UInt16(savedGlobalCode ?? 0x00)
        self.autoCompletionToggleGlobalModifiers = defaults.object(forKey: Keys.autoCompletionToggleGlobalModifiers) as? UInt ?? 0
        self.autoCompletionToggleGlobalEnabled = defaults.object(forKey: Keys.autoCompletionToggleGlobalEnabled) as? Bool ?? false
        self.autoCompletionIncludeCrossLayout = defaults.object(forKey: Keys.autoCompletionIncludeCrossLayout) as? Bool ?? true
        self.autoCompletionSuggestProfanity = defaults.object(forKey: Keys.autoCompletionSuggestProfanity) as? Bool ?? false // Default: OFF
        let savedDisplayMode = defaults.object(forKey: Keys.autoCompletionDisplayMode) as? Int
        self.autoCompletionDisplayMode = AutocompletionDisplayMode(rawValue: savedDisplayMode ?? 2) ?? .both
        self.autoCompletionDelay = defaults.object(forKey: Keys.autoCompletionDelay) as? Double ?? 0.035
        
        let savedExcluded = defaults.stringArray(forKey: Keys.excludedAppBundleIDs)
        self.excludedAppBundleIDs = savedExcluded ?? Array(AutoCorrectionGate.defaultExcludedBundleIDs).sorted()
        
        self.thoughtRecoveryEnabled = defaults.object(forKey: Keys.thoughtRecoveryEnabled) as? Bool ?? true  // Default: ON
        self.thoughtRecoveryPreview = defaults.object(forKey: Keys.thoughtRecoveryPreview) as? Bool ?? false // Default: OFF
        self.recoveryCount = defaults.integer(forKey: Keys.recoveryCount)
        self.recoveryRevertCount = defaults.integer(forKey: Keys.recoveryRevertCount)
        
        self.aiPredictiveEnabled = defaults.object(forKey: Keys.aiPredictiveEnabled) as? Bool ?? true   // Default: ON
        self.showFieldAnchorBadge = defaults.object(forKey: Keys.showFieldAnchorBadge) as? Bool ?? true // Default: ON
        self.aiBatteryModeEnabled = defaults.object(forKey: Keys.aiBatteryModeEnabled) as? Bool ?? true // Default: ON
        self.aiMaxContinuationWords = defaults.object(forKey: Keys.aiMaxContinuationWords) as? Int ?? 3  // Default: 3 words
        self.aiDebounceDelay = defaults.object(forKey: Keys.aiDebounceDelay) as? Double ?? 0.350        // Default: 350 ms
        self.aiStreamingEnabled = defaults.object(forKey: Keys.aiStreamingEnabled) as? Bool ?? true     // Default: ON
        self.aiScreenContextEnabled = defaults.object(forKey: Keys.aiScreenContextEnabled) as? Bool ?? true // Default: ON
        self.aiCustomInstructions = defaults.string(forKey: Keys.aiCustomInstructions) ?? ""
        self.aiPersonalizationEnabled = defaults.object(forKey: Keys.aiPersonalizationEnabled) as? Bool ?? true // Default: ON
        if let data = defaults.data(forKey: Keys.perAppAISettings),
           let savedPerApp = try? JSONDecoder().decode([String: AppAISettings].self, from: data) {
            self.perAppAISettings = savedPerApp
        } else {
            self.perAppAISettings = [:]
        }
        self.selectedModelId = defaults.string(forKey: Keys.selectedModelId) ?? RecommendedAIModel.defaultModelID
        self.customModelPath = defaults.string(forKey: Keys.customModelPath) ?? ""
        self.savedCharactersCount = defaults.integer(forKey: Keys.savedCharactersCount)
        self.savedClicksCount = defaults.integer(forKey: Keys.savedClicksCount)
        
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
    
    func recordSavedText(inserted: Int, typed: Int) {
        let saved = max(0, inserted - typed)
        savedCharactersCount += saved
        savedClicksCount += saved
        defaults.set(savedCharactersCount, forKey: Keys.savedCharactersCount)
        defaults.set(savedClicksCount, forKey: Keys.savedClicksCount)
    }

    func recordAutoCorrection(charCount: Int) {
        savedCharactersCount += charCount
        savedClicksCount += charCount * 2
        defaults.set(savedCharactersCount, forKey: Keys.savedCharactersCount)
        defaults.set(savedClicksCount, forKey: Keys.savedClicksCount)
    }

    func resetStatistics() {
        conversionCount = 0
        recoveryCount = 0
        recoveryRevertCount = 0
        savedCharactersCount = 0
        savedClicksCount = 0
        defaults.set(0, forKey: Keys.conversionCount)
        defaults.set(0, forKey: Keys.recoveryCount)
        defaults.set(0, forKey: Keys.recoveryRevertCount)
        defaults.set(0, forKey: Keys.savedCharactersCount)
        defaults.set(0, forKey: Keys.savedClicksCount)
    }
    
    private func saveLayouts() {
        if let data = try? JSONEncoder().encode(enabledLayouts) {
            defaults.set(data, forKey: Keys.enabledLayouts)
        }
    }
}
