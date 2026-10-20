import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    @State private var selectedTab = 0
    
    private var tabItems: [(String, String)] {
        [
            (l10n.t("settings.tab.general"), "gear"),
            (l10n.t("settings.tab.layouts"), "keyboard"),
            (l10n.t("settings.tab.hotkey"), "command"),
            (l10n.t("settings.tab.permissions"), "lock.shield"),
            (l10n.t("settings.tab.log"), "list.bullet.rectangle"),
        ]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Classic segmented tab bar
            HStack(spacing: 0) {
                ForEach(Array(tabItems.enumerated()), id: \.offset) { index, item in
                    Button {
                        selectedTab = index
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.1)
                                .font(.system(size: 16))
                            Text(item.0)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == index ? Color.accentColor.opacity(0.15) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == index ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            Divider()
                .padding(.top, 4)
            
            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsTab()
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                case 1:
                    LayoutsSettingsTab()
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                case 2:
                    HotkeySettingsTab()
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                case 3:
                    PermissionsView()
                        .environmentObject(l10n)
                case 4:
                    ConversionLogView(logStore: ConversionLogStore.shared)
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 520)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    
    var body: some View {
        Form {
            Section {
                Picker(l10n.t("general.language"), selection: $l10n.currentLanguage) {
                    ForEach(LocalizationManager.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                
                Picker(l10n.t("general.statusBarIcon"), selection: $settingsManager.statusBarIconStyle) {
                    ForEach(StatusBarIconStyle.allCases, id: \.self) { style in
                        Text(iconStyleDisplayName(style)).tag(style)
                    }
                }
                
                Toggle(l10n.t("general.launchAtLogin"), isOn: $settingsManager.launchAtLogin)
                Toggle(l10n.t("general.playSound"), isOn: $settingsManager.playSounds)
                Toggle(l10n.t("general.showNotifications"), isOn: $settingsManager.showNotifications)
            }
            
            Section(l10n.t("general.smartConversion")) {
                Picker(l10n.t("general.mode"), selection: $settingsManager.smartConversionMode) {
                    ForEach(SmartConversionMode.allCases, id: \.self) { mode in
                        Text(smartModeDisplayName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(smartModeDescription(settingsManager.smartConversionMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            
            Section(l10n.t("general.thoughtRecovery")) {
                Toggle(l10n.t("general.thoughtRecoveryEnabled"), isOn: $settingsManager.thoughtRecoveryEnabled)
                Toggle(l10n.t("general.thoughtRecoveryPreview"), isOn: $settingsManager.thoughtRecoveryPreview)
                    .disabled(!settingsManager.thoughtRecoveryEnabled)

                Text(l10n.t("general.thoughtRecoveryHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settingsManager.recoveryCount > 0 {
                    HStack {
                        Text(l10n.t("general.recoveryStats"))
                            .font(.caption)
                        Spacer()
                        Text("\(settingsManager.recoveryCount) · \(l10n.t("general.recoveryRevertRate")) \(Int(settingsManager.recoveryRevertRate * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(l10n.t("general.layoutSwitch")) {
                Picker(l10n.t("general.mode"), selection: $settingsManager.layoutSwitchMode) {
                    ForEach(LayoutSwitchMode.allCases, id: \.self) { mode in
                        Text(layoutSwitchModeDisplayName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                
                Text(layoutSwitchModeDescription(settingsManager.layoutSwitchMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            
            Section(l10n.t("general.autoCorrection")) {
                Toggle(l10n.t("general.autoCorrectionEnabled"), isOn: $settingsManager.autoCorrectionEnabled)
                
                Text(l10n.t("general.autoCorrectionDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                
                if settingsManager.autoCorrectionEnabled {
                    Toggle(l10n.t("general.autoCorrectionSpellCheck"), isOn: $settingsManager.autoCorrectionUseSpellCheck)
                    
                    Text(l10n.t("general.autoCorrectionSpellCheckDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    
                    Toggle(l10n.t("general.autoCorrectionSwitchLayout"), isOn: $settingsManager.autoCorrectionSwitchLayout)
                }
            }
            
            Section(l10n.t("general.autocompletion")) {
                Toggle(l10n.t("autocompletion.enabled"), isOn: $settingsManager.autoCompletionEnabled)
                
                Text(l10n.t("autocompletion.desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                
                if settingsManager.autoCompletionEnabled {
                    Picker(l10n.t("autocompletion.acceptKey"), selection: $settingsManager.autoCompletionAcceptKey) {
                        ForEach(AutocompletionAcceptKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    
                    if settingsManager.autoCompletionAcceptKey == .custom {
                        AutocompletionKeyRecorderView(
                            keyCode: $settingsManager.autoCompletionCustomKeyCode,
                            modifiers: $settingsManager.autoCompletionCustomModifiers
                        )
                    }
                    
                    Toggle(l10n.t("autocompletion.useNumberShortcuts"), isOn: $settingsManager.autoCompletionUseNumberShortcuts)
                    
                    Toggle(l10n.t("autocompletion.includeCrossLayout"), isOn: $settingsManager.autoCompletionIncludeCrossLayout)
                    
                    Text(l10n.t("autocompletion.crossLayoutDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    
                    Stepper("\(l10n.t("autocompletion.minPrefixLength")) \(settingsManager.autoCompletionMinPrefixLength)", value: $settingsManager.autoCompletionMinPrefixLength, in: 2...5)
                    
                    Stepper("\(l10n.t("autocompletion.maxSuggestions")) \(settingsManager.autoCompletionMaxSuggestions)", value: $settingsManager.autoCompletionMaxSuggestions, in: 1...6)
                }
            }
            
            Section(l10n.t("general.howItWorks")) {
                Text(l10n.t("general.howItWorksText"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section(l10n.t("general.statistics")) {
                HStack {
                    Text(l10n.t("general.totalConversions"))
                    Spacer()
                    Text("\(settingsManager.conversionCount)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Mode Display Helpers
    // Use l10n from @EnvironmentObject so SwiftUI re-renders on language change
    
    private func iconStyleDisplayName(_ style: StatusBarIconStyle) -> String {
        switch style {
        case .languageBadge: return l10n.t("settings.iconStyle.languageBadge")
        case .keyboardIcon: return l10n.t("settings.iconStyle.keyboardIcon")
        }
    }
    
    private func smartModeDisplayName(_ mode: SmartConversionMode) -> String {
        switch mode {
        case .lastWord: return l10n.t("smartMode.lastWord.name")
        case .greedyLine: return l10n.t("smartMode.greedyLine.name")
        case .disabled: return l10n.t("smartMode.disabled.name")
        }
    }
    
    private func smartModeDescription(_ mode: SmartConversionMode) -> String {
        switch mode {
        case .lastWord: return l10n.t("smartMode.lastWord.desc")
        case .greedyLine: return l10n.t("smartMode.greedyLine.desc")
        case .disabled: return l10n.t("smartMode.disabled.desc")
        }
    }
    
    private func layoutSwitchModeDisplayName(_ mode: LayoutSwitchMode) -> String {
        switch mode {
        case .always: return l10n.t("layoutSwitchMode.always.name")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.name")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.name")
        }
    }
    
    private func layoutSwitchModeDescription(_ mode: LayoutSwitchMode) -> String {
        switch mode {
        case .always: return l10n.t("layoutSwitchMode.always.desc")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.desc")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.desc")
        }
    }
}

// MARK: - Layouts Settings

struct LayoutsSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("layouts.title"))
                .font(.headline)
            
            Text(l10n.t("layouts.description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            List {
                ForEach(settingsManager.enabledLayouts) { layout in
                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(layout.localizedName)
                                .font(.body)
                            Text(layout.id)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(layout.languageCode.uppercased())
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            HStack {
                Button(l10n.t("layouts.refresh")) {
                    settingsManager.refreshSystemLayouts()
                }
                
                Spacer()
                
                Text(l10n.t("layouts.count").replacingOccurrences(of: "%d", with: "\(settingsManager.enabledLayouts.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Single Key Layout Switch
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.t("layoutSwitchKey.title"))
                        .font(.headline)
                    
                    Text(l10n.t("layoutSwitchKey.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(l10n.t("layoutSwitchKey.current"))
                        Spacer()
                        Picker("", selection: $settingsManager.layoutSwitchKey) {
                            ForEach(LayoutSwitchKey.allCases) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    Text(l10n.t("layoutSwitchKey.hint"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Divider()
                
                // Section 2: Text Conversion Shortcut
                VStack(alignment: .leading, spacing: 12) {
                    Text(l10n.t("hotkey.title"))
                        .font(.headline)
                    
                    Text(l10n.t("hotkey.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Current shortcut display
                    HStack {
                        Text(l10n.t("hotkey.current"))
                        Spacer()
                        Text(settingsManager.hotkeyDescription)
                            .font(.system(.title3, design: .rounded))
                            .bold()
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Double Shift toggle
                    Toggle(l10n.t("hotkey.useDoubleShift"), isOn: $settingsManager.useDoubleShift)
                        .toggleStyle(.switch)
                    
                    Text(l10n.t("hotkey.doubleShiftHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !settingsManager.useDoubleShift {
                        Divider()
                        
                        Text(l10n.t("hotkey.customTitle"))
                            .font(.subheadline)
                            .bold()
                        
                        HotkeyRecorderView(
                            keyCode: $settingsManager.hotkeyKeyCode,
                            modifiers: Binding(
                                get: { settingsManager.hotkeyModifierFlags },
                                set: { settingsManager.hotkeyModifierFlags = $0 }
                            )
                        )
                        .environmentObject(l10n)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Launch at Login Helper

enum LaunchAtLoginHelper {
    static func setLaunchAtLogin(_ enabled: Bool) {
        // In production, use SMAppService (macOS 13+) or ServiceManagement
        // For now this is a placeholder
    }
}
