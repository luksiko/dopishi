import SwiftUI

// MARK: - Pro Badge Component

struct ProBadge: View {
    var text: String = "PRO"

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                LinearGradient(
                    colors: [Color.purple, Color.blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    @State private var selectedTab = 0

    private var tabItems: [(String, String)] {
        [
            (l10n.t("settings.tab.general"), "gear"),
            (l10n.t("settings.tab.layout"), "keyboard"),
            (l10n.t("settings.tab.ai"), "sparkles"),
            (l10n.t("settings.tab.apps"), "square.grid.2x2"),
            (l10n.t("settings.tab.history"), "chart.bar"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Modern native-styled segmented tab bar
            HStack(spacing: 6) {
                ForEach(Array(tabItems.enumerated()), id: \.offset) { index, item in
                    Button {
                        selectedTab = index
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.1)
                                .font(.system(size: 16, weight: selectedTab == index ? .semibold : .regular))
                            Text(item.0)
                                .font(.caption)
                                .fontWeight(selectedTab == index ? .semibold : .regular)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == index ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedTab == index ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsTab(selectedTab: $selectedTab)
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                case 1:
                    LayoutSettingsTab()
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                case 2:
                    AIAssistantSettingsTab()
                        .environmentObject(settingsManager)
                        .environmentObject(l10n)
                case 3:
                    AppsSettingsTab()
                        .environmentObject(settingsManager)
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
        .frame(width: 620, height: 600)
        .onAppear {
            selectedTab = settingsManager.selectedSettingsTab
        }
        .onChange(of: settingsManager.selectedSettingsTab) { newTab in
            selectedTab = newTab
        }
        .onChange(of: selectedTab) { newTab in
            settingsManager.selectedSettingsTab = newTab
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    @State private var hasAccessibility = AccessibilityService.hasAccessibilityPermission
    @State private var showPermissionsGuide = false

    var body: some View {
        Form {
            // ── Appearance & Language ───────────────────────────────
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
            }

            // ── System Integration ──────────────────────────────────
            Section {
                Toggle(l10n.t("general.launchAtLogin"), isOn: $settingsManager.launchAtLogin)
                Toggle(l10n.t("general.playSound"), isOn: $settingsManager.playSounds)
                Toggle(l10n.t("general.showNotifications"), isOn: $settingsManager.showNotifications)

                HStack {
                    Toggle(l10n.t("general.iCloudSync"), isOn: $settingsManager.iCloudSyncEnabled)
                    Spacer()
                    ProBadge()
                }
                Text(l10n.t("general.iCloudSyncDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Accessibility Permissions Status ────────────────────
            Section {
                if hasAccessibility {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.t("permissions.active"))
                                .font(.body)
                                .fontWeight(.medium)
                            Text(l10n.t("permissions.activeDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(l10n.t("permissions.openSystemSettings")) {
                            AccessibilityService.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(l10n.t("permissions.accessibilityTitle"))
                                    .font(.body)
                                    .fontWeight(.semibold)
                                Text(l10n.t("permissions.notGranted"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(l10n.t("permissions.grantAccess")) {
                                AccessibilityService.requestAccessibilityPermission()
                                hasAccessibility = AccessibilityService.hasAccessibilityPermission
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        DisclosureGroup(l10n.t("permissions.guide"), isExpanded: $showPermissionsGuide) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.t("permissions.step1"))
                                Text(l10n.t("permissions.step2"))
                                Text(l10n.t("permissions.step3"))
                                Text(l10n.t("permissions.step4"))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasAccessibility = AccessibilityService.hasAccessibilityPermission
        }
    }

    private func iconStyleDisplayName(_ style: StatusBarIconStyle) -> String {
        switch style {
        case .languageBadge: return l10n.t("settings.iconStyle.languageBadge")
        case .keyboardIcon: return l10n.t("settings.iconStyle.keyboardIcon")
        }
    }
}

// MARK: - Layout & Conversion Settings Tab

struct LayoutSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    @State private var isLayoutsExpanded = false

    var body: some View {
        Form {
            // ── 1. Single Key Layout Switch ─────────────────────────
            Section(l10n.t("layoutSwitchKey.title")) {
                Picker(l10n.t("layoutSwitchKey.current"), selection: $settingsManager.layoutSwitchKey) {
                    ForEach(LayoutSwitchKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }

                Text(l10n.t("layoutSwitchKey.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Toggle(l10n.t("layout.multiLanguageAutoDetect"), isOn: $settingsManager.proMultiLanguageAutoDetect)
                    Spacer()
                    ProBadge()
                }
                .padding(.top, 4)

                Text(l10n.t("layout.multiLanguageAutoDetectDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── 2. Text Conversion Shortcut ─────────────────────────
            Section(l10n.t("hotkey.title")) {
                Toggle(l10n.t("hotkey.useDoubleShift"), isOn: $settingsManager.useDoubleShift)

                Text(l10n.t("hotkey.doubleShiftHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !settingsManager.useDoubleShift {
                    HStack {
                        Text(l10n.t("hotkey.customTitle"))
                        Spacer()
                        HotkeyRecorderView(
                            keyCode: $settingsManager.hotkeyKeyCode,
                            modifiers: Binding(
                                get: { settingsManager.hotkeyModifierFlags },
                                set: { settingsManager.hotkeyModifierFlags = $0 }
                            )
                        )
                        .environmentObject(l10n)
                    }
                    .padding(.top, 2)
                }
            }

            // ── 3. Smart Conversion Mode ────────────────────────────
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

                Divider()
                    .padding(.vertical, 2)

                Picker(l10n.t("general.layoutSwitch"), selection: $settingsManager.layoutSwitchMode) {
                    ForEach(LayoutSwitchMode.allCases, id: \.self) { mode in
                        Text(layoutSwitchModeDisplayName(mode)).tag(mode)
                    }
                }

                Text(layoutSwitchModeDescription(settingsManager.layoutSwitchMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── 4. Automatic Typo Correction ────────────────────────
            Section(l10n.t("general.autoCorrection")) {
                Toggle(l10n.t("general.autoCorrectionEnabled"), isOn: $settingsManager.autoCorrectionEnabled)

                Text(l10n.t("general.autoCorrectionDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settingsManager.autoCorrectionEnabled {
                    // Layout & Dictionary
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.t("general.autoCorrectionGroup.layout"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Toggle(l10n.t("general.autoCorrectionSpellCheck"), isOn: $settingsManager.autoCorrectionUseSpellCheck)
                        Text(l10n.t("general.autoCorrectionSpellCheckDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(l10n.t("general.autoCorrectionSwitchLayout"), isOn: $settingsManager.autoCorrectionSwitchLayout)
                        Text(l10n.t("general.autoCorrectionSwitchLayoutDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)

                    Divider().padding(.vertical, 4)

                    // Capitalization & Letter Case
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.t("general.autoCorrectionGroup.casing"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Toggle(l10n.t("general.autoCorrectionCapitalizeSentences"), isOn: $settingsManager.autoCorrectionCapitalizeSentences)
                        Text(l10n.t("general.autoCorrectionCapitalizeSentencesDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(l10n.t("general.autoCorrectionFixTwoCapitals"), isOn: $settingsManager.autoCorrectionFixTwoInitialCapitals)
                        Text(l10n.t("general.autoCorrectionFixTwoCapitalsDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(l10n.t("general.autoCorrectionFixCapsLock"), isOn: $settingsManager.autoCorrectionFixCapsLockErrors)
                        Text(l10n.t("general.autoCorrectionFixCapsLockDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.vertical, 4)

                    // Smart Punctuation & Typography
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.t("general.autoCorrectionGroup.punctuation"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        Toggle(l10n.t("general.autoCorrectionCommaBeforeConjunctions"), isOn: $settingsManager.autoCorrectionCommaBeforeConjunctions)
                        Text(l10n.t("general.autoCorrectionCommaBeforeConjunctionsDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(l10n.t("general.autoCorrectionRemoveSpaceBeforePunctuation"), isOn: $settingsManager.autoCorrectionRemoveSpaceBeforePunctuation)
                        Text(l10n.t("general.autoCorrectionRemoveSpaceBeforePunctuationDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle(l10n.t("general.autoCorrectionSmartDashesAndEllipsis"), isOn: $settingsManager.autoCorrectionSmartDashesAndEllipsis)
                        Text(l10n.t("general.autoCorrectionSmartDashesAndEllipsisDesc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // ── 5. Thought Recovery Buffer ──────────────────────────
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

            // ── 6. Installed System Layouts ─────────────────────────
            Section {
                DisclosureGroup(isExpanded: $isLayoutsExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(settingsManager.enabledLayouts) { layout in
                            HStack {
                                Image(systemName: "keyboard")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(layout.localizedName)
                                        .font(.body)
                                    Text(layout.id)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(layout.languageCode.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 2)
                        }

                        HStack {
                            Spacer()
                            Button(l10n.t("layouts.refresh")) {
                                settingsManager.refreshSystemLayouts()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text(l10n.t("layouts.title"))
                        Spacer()
                        Text(l10n.t("layouts.count").replacingOccurrences(of: "%d", with: "\(settingsManager.enabledLayouts.count)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Mode Display Helpers

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
        case .never: return l10n.t("layoutSwitchMode.never.name")
        }
    }

    private func layoutSwitchModeDescription(_ mode: LayoutSwitchMode) -> String {
        switch mode {
        case .always: return l10n.t("layoutSwitchMode.always.desc")
        case .ifLastWordConverted: return l10n.t("layoutSwitchMode.ifLastWord.desc")
        case .ifAnyWordConverted: return l10n.t("layoutSwitchMode.ifAnyWord.desc")
        case .never: return l10n.t("layoutSwitchMode.never.desc")
        }
    }
}

// MARK: - Compatibility Aliases for Previous Views

typealias LayoutsSettingsTab = LayoutSettingsTab
typealias HotkeySettingsTab = LayoutSettingsTab

// MARK: - Launch at Login Helper

enum LaunchAtLoginHelper {
    static func setLaunchAtLogin(_ enabled: Bool) {
        // SMAppService (macOS 13+) is managed by system or bundle helper
    }
}
