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

// MARK: - Sidebar Tab Enum

enum SettingsSidebarTab: Int, CaseIterable, Identifiable {
    case general = 0
    case shortcuts = 1
    case autoCorrection = 2
    case layouts = 3
    case ai = 4
    case apps = 5
    case history = 6
    case setup = 7
    case about = 8

    var id: Int { rawValue }
}

// MARK: - Sidebar Item Button

struct SidebarItemButton: View {
    let tab: SettingsSidebarTab
    let isSelected: Bool
    let title: String
    let iconName: String
    let iconColors: [Color]
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: iconColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)

                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    @State private var selectedTab: SettingsSidebarTab = .general

    private var mainTabs: [SettingsSidebarTab] {
        [.general, .shortcuts, .autoCorrection, .layouts, .ai, .apps, .history]
    }

    private var bottomTabs: [SettingsSidebarTab] {
        [.setup, .about]
    }

    var body: some View {
        HStack(spacing: 0) {
            // Modern macOS Sidebar
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(mainTabs) { tab in
                            SidebarItemButton(
                                tab: tab,
                                isSelected: selectedTab == tab,
                                title: tabTitle(tab),
                                iconName: tabIcon(tab),
                                iconColors: tabColors(tab)
                            ) {
                                selectedTab = tab
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)

                        ForEach(bottomTabs) { tab in
                            SidebarItemButton(
                                tab: tab,
                                isSelected: selectedTab == tab,
                                title: tabTitle(tab),
                                iconName: tabIcon(tab),
                                iconColors: tabColors(tab)
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }

                Spacer()
            }
            .frame(width: 215)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // Detail View
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()

                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab(selectedTab: $selectedTab)
                    case .shortcuts:
                        ShortcutsSettingsTab()
                    case .autoCorrection:
                        AutoCorrectionSettingsTab()
                    case .layouts:
                        LayoutsSettingsTab()
                    case .ai:
                        AIAssistantSettingsTab()
                    case .apps:
                        AppsSettingsTab()
                    case .history:
                        ConversionLogView(logStore: ConversionLogStore.shared)
                    case .setup:
                        SetupSettingsTab(selectedTab: $selectedTab)
                    case .about:
                        AboutSettingsTab()
                    }
                }
                .environmentObject(settingsManager)
                .environmentObject(l10n)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .frame(idealWidth: 780, idealHeight: 600)
        .onAppear {
            if let tab = SettingsSidebarTab(rawValue: settingsManager.selectedSettingsTab) {
                selectedTab = tab
            } else {
                selectedTab = .general
            }
            settingsManager.refreshSystemLayouts()
        }
        .onChange(of: settingsManager.selectedSettingsTab) { newTabRaw in
            if let tab = SettingsSidebarTab(rawValue: newTabRaw) {
                selectedTab = tab
            }
        }
        .onChange(of: selectedTab) { newTab in
            settingsManager.selectedSettingsTab = newTab.rawValue
        }
    }

    private func tabTitle(_ tab: SettingsSidebarTab) -> String {
        switch tab {
        case .setup: return l10n.t("settings.tab.setup")
        case .general: return l10n.t("settings.tab.general")
        case .shortcuts: return l10n.t("settings.tab.shortcuts")
        case .layouts: return l10n.t("settings.tab.layouts")
        case .autoCorrection: return l10n.t("settings.tab.autoCorrection")
        case .ai: return l10n.t("settings.tab.ai")
        case .apps: return l10n.t("settings.tab.apps")
        case .history: return l10n.t("settings.tab.history")
        case .about: return l10n.t("settings.tab.about")
        }
    }

    private func tabIcon(_ tab: SettingsSidebarTab) -> String {
        switch tab {
        case .setup: return "wand.and.stars"
        case .general: return "gearshape.fill"
        case .shortcuts: return "command"
        case .layouts: return "keyboard.fill"
        case .autoCorrection: return "text.badge.checkmark"
        case .ai: return "sparkles"
        case .apps: return "square.grid.2x2.fill"
        case .history: return "chart.bar.xaxis"
        case .about: return "info.circle.fill"
        }
    }

    private func tabColors(_ tab: SettingsSidebarTab) -> [Color] {
        switch tab {
        case .setup: return [Color.indigo, Color.purple]
        case .general: return [Color.gray, Color.secondary]
        case .shortcuts: return [Color.orange, Color.red]
        case .layouts: return [Color.teal, Color.cyan]
        case .autoCorrection: return [Color.blue, Color.indigo]
        case .ai: return [Color.purple, Color.pink]
        case .apps: return [Color.green, Color.mint]
        case .history: return [Color.orange, Color.yellow]
        case .about: return [Color.blue, Color.teal]
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @Binding var selectedTab: SettingsSidebarTab
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    @ObservedObject private var updateManager = UpdateManager.shared

    @State private var hasAccessibility = AccessibilityService.hasAccessibilityPermission
    @State private var showPermissionsGuide = false

    var body: some View {
        Form {
            // ── 1. Accessibility Permissions Status (Priority #1) ───
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

            // ── 2. Setup Wizard ─────────────────────────────────────
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("settings.setupWizard.title"))
                            .font(.body)
                            .fontWeight(.medium)
                        Text(l10n.t("settings.setupWizard.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(l10n.t("settings.setupWizard.button")) {
                        selectedTab = .setup
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }

            // ── 3. Appearance & Language ────────────────────────────
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

            // ── 4. System Integration ───────────────────────────────
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

            // ── 5. Updates ──────────────────────────────────────────
            Section(l10n.t("general.updates")) {
                Toggle(l10n.t("general.autoUpdateCheck"), isOn: $updateManager.automaticallyChecksForUpdates)
                Text(l10n.t("general.updatesDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(l10n.t("general.checkNow")) {
                    updateManager.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            settingsManager.refreshSystemLayouts()
            hasAccessibility = AccessibilityService.hasAccessibilityPermission
        }
    }

    private func iconStyleDisplayName(_ style: StatusBarIconStyle) -> String {
        switch style {
        case .languageBadge:
            let codes = settingsManager.enabledLayouts
                .map { $0.languageCode.uppercased() }
                .filter { !$0.isEmpty }
            var uniqueCodes: [String] = []
            for code in codes where !uniqueCodes.contains(code) {
                uniqueCodes.append(code)
            }
            let base = l10n.t("settings.iconStyle.languageBadge")
            if !uniqueCodes.isEmpty {
                let maxShown = 3
                let shown = uniqueCodes.prefix(maxShown).joined(separator: ", ")
                let suffix = uniqueCodes.count > maxShown ? "…" : ""
                return "\(base) (\(shown)\(suffix))"
            }
            return "\(base) (EN)"
        case .keyboardIcon:
            return l10n.t("settings.iconStyle.keyboardIcon")
        }
    }
}

// MARK: - Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        Form {
            // ── 1. Single Key Layout Switch ─────────────────────────
            Section(l10n.t("shortcuts.section.layoutSwitch")) {
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
            Section(l10n.t("shortcuts.section.conversion")) {
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

                Divider()
                    .padding(.vertical, 4)

                Picker(l10n.t("general.smartConversion"), selection: $settingsManager.smartConversionMode) {
                    ForEach(SmartConversionMode.allCases, id: \.self) { mode in
                        Text(smartModeDisplayName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(smartModeDescription(settingsManager.smartConversionMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                Picker(l10n.t("general.layoutSwitch"), selection: $settingsManager.layoutSwitchMode) {
                    ForEach(LayoutSwitchMode.allCases, id: \.self) { mode in
                        Text(layoutSwitchModeDisplayName(mode)).tag(mode)
                    }
                }

                Text(layoutSwitchModeDescription(settingsManager.layoutSwitchMode))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── 3. Autocompletion Shortcuts ─────────────────────────
            Section(l10n.t("shortcuts.section.completions")) {
                HStack {
                    Text(l10n.t("autocompletion.completeNextWord"))
                    Spacer()
                    Picker("", selection: $settingsManager.autoCompletionAcceptKey) {
                        ForEach(AutocompletionAcceptKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                if settingsManager.autoCompletionAcceptKey == .custom {
                    AutocompletionKeyRecorderView(
                        keyCode: $settingsManager.autoCompletionCustomKeyCode,
                        modifiers: $settingsManager.autoCompletionCustomModifiers
                    )
                }

                Toggle(l10n.t("autocompletion.includeTrailingSpace"), isOn: $settingsManager.autoCompletionIncludeTrailingSpace)
                Text(l10n.t("autocompletion.includeTrailingSpaceDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(l10n.t("autocompletion.acceptEntirePhrase"), isOn: $settingsManager.autoCompletionAcceptEntirePhrase)
                Text(l10n.t("autocompletion.acceptEntirePhraseDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(l10n.t("autocompletion.triggerFullCompletion"))
                    Spacer()
                    Picker("", selection: $settingsManager.autoCompletionAcceptAllKey) {
                        ForEach(AutocompletionAcceptAllKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }

                if settingsManager.autoCompletionAcceptAllKey == .custom {
                    AutocompletionKeyRecorderView(
                        keyCode: $settingsManager.autoCompletionCustomAcceptAllKeyCode,
                        modifiers: $settingsManager.autoCompletionCustomAcceptAllModifiers
                    )
                }

                HStack {
                    Text(l10n.t("autocompletion.whenEscapePressed"))
                    Spacer()
                    Picker("", selection: $settingsManager.autoCompletionEscapeAction) {
                        ForEach(AutocompletionEscapeAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
            }

            // ── 4. Undo & Quick Revert ──────────────────────────────
            Section(l10n.t("shortcuts.section.undo")) {
                Toggle(l10n.t("shortcuts.revertOnBackspace"), isOn: $settingsManager.autoCorrectionRevertOnBackspace)
                Text(l10n.t("shortcuts.revertOnBackspaceDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

// MARK: - Auto-Correction Settings Tab

struct AutoCorrectionSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        Form {
            // ── Master Toggle ───────────────────────────────────────
            Section {
                Toggle(l10n.t("general.autoCorrectionEnabled"), isOn: $settingsManager.autoCorrectionEnabled)
                    .font(.headline)

                Text(l10n.t("general.autoCorrectionDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settingsManager.autoCorrectionEnabled {
                // ── 1. Layout & Typos ───────────────────────────────
                Section(l10n.t("general.autoCorrectionGroup.layout")) {
                    Toggle(l10n.t("general.autoCorrectionSpellCheck"), isOn: $settingsManager.autoCorrectionUseSpellCheck)
                    Text(l10n.t("general.autoCorrectionSpellCheckDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.t("general.autoCorrectionSwitchLayout"), isOn: $settingsManager.autoCorrectionSwitchLayout)
                    Text(l10n.t("general.autoCorrectionSwitchLayoutDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.t("general.autoCorrectionFixTypos"), isOn: $settingsManager.autoCorrectionFixTypos)
                    Text(l10n.t("general.autoCorrectionFixTyposDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.t("general.autoCorrectionRevertOnBackspace"), isOn: $settingsManager.autoCorrectionRevertOnBackspace)
                    Text(l10n.t("general.autoCorrectionRevertOnBackspaceDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ── 2. Capitalization & Letter Case ─────────────────
                Section(l10n.t("general.autoCorrectionGroup.casing")) {
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

                // ── 3. Smart Punctuation & Typography ───────────────
                Section(l10n.t("general.autoCorrectionGroup.punctuation")) {
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

                    Toggle(l10n.t("general.autoCorrectionEmojiShortcodes"), isOn: $settingsManager.autoCorrectionEmojiShortcodes)
                    Text(l10n.t("general.autoCorrectionEmojiShortcodesDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ── 4. Thought Recovery Buffer ──────────────────────
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
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Layouts & Dictionaries Settings Tab

struct LayoutsSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    @ObservedObject private var dictionaryManager = DictionaryDownloadManager.shared

    var body: some View {
        Form {
            // ── 1. Installed System Layouts & Hunspell Dictionaries ──
            Section(l10n.t("layouts.title")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(settingsManager.enabledLayouts) { layout in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "keyboard")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(layout.localizedName)
                                        .font(.body)
                                        .fontWeight(.medium)
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

                            // Dictionary status & action row
                            let status = dictionaryManager.status(for: layout.languageCode)
                            let dlState = dictionaryManager.downloadStates[layout.languageCode.lowercased()] ?? .idle

                            HStack(spacing: 6) {
                                switch status {
                                case .systemProvided:
                                    Image(systemName: "checkmark.seal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(l10n.t("layouts.dict.system"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)

                                case .installed:
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    Text(l10n.t("layouts.dict.installed"))
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    Spacer()
                                    Button {
                                        dictionaryManager.openSpellingDirectory()
                                    } label: {
                                        Image(systemName: "folder")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(l10n.t("layouts.dict.openFolder"))

                                case .availableForDownload(let dict):
                                    switch dlState {
                                    case .downloading(let progress):
                                        ProgressView(value: progress)
                                            .frame(width: 50)
                                            .scaleEffect(0.7)
                                        Text(l10n.t("layouts.dict.downloading"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                    case .completed:
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                        Text(l10n.t("layouts.dict.installed"))
                                            .font(.caption2)
                                            .foregroundStyle(.green)

                                    case .failed(let err):
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                        Text(err)
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(l10n.t("layouts.dict.retry")) {
                                            Task { await dictionaryManager.downloadDictionary(for: dict) }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)

                                    case .idle:
                                        Image(systemName: "exclamationmark.circle")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text(l10n.t("layouts.dict.missing"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button {
                                            Task { await dictionaryManager.downloadDictionary(for: dict) }
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: "arrow.down.circle")
                                                Text("\(l10n.t("layouts.dict.download")) (~\(String(format: "%.1f", dict.approximateSizeMB)) MB)")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.mini)
                                    }

                                case .unsupported:
                                    Image(systemName: "questionmark.circle")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(l10n.t("layouts.dict.notAvailable"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.leading, 24)
                            .padding(.top, 1)
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Button(l10n.t("layouts.dict.openFolder")) {
                            dictionaryManager.openSpellingDirectory()
                        }
                        .buttonStyle(.link)
                        .font(.caption)

                        Spacer()

                        Button(l10n.t("layouts.refresh")) {
                            settingsManager.refreshSystemLayouts()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }

            // ── 2. User Dictionary & Learned Words ───────────────────
            Section {
                UserDictionarySettingsSection()
            }
        }
        .formStyle(.grouped)
        .onAppear {
            settingsManager.refreshSystemLayouts()
        }
    }
}

// MARK: - Setup Settings Tab

struct SetupSettingsTab: View {
    @Binding var selectedTab: SettingsSidebarTab
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    @State private var hasAccessibility = AccessibilityService.hasAccessibilityPermission
    @State private var testInput: String = "ghbdtn"
    @State private var convertedPreview: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.indigo, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)

                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(l10n.t("setup.tab.title"))
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(l10n.t("setup.tab.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)

                // 1. Accessibility Status Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: hasAccessibility ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(hasAccessibility ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.t("setup.tab.systemAccess"))
                                .font(.body)
                                .fontWeight(.semibold)
                            Text(hasAccessibility ? l10n.t("setup.tab.systemAccessOk") : l10n.t("setup.tab.systemAccessNeeded"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !hasAccessibility {
                            Button(l10n.t("permissions.grantAccess")) {
                                AccessibilityService.requestAccessibilityPermission()
                                hasAccessibility = AccessibilityService.hasAccessibilityPermission
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(l10n.t("permissions.openSystemSettings")) {
                                AccessibilityService.openAccessibilitySettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // 2. Interactive Typing Test Card
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.t("setup.tab.testConversion"))
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField(l10n.t("setup.tab.testConversionPlaceholder"), text: $testInput)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: testInput) { newValue in
                                updateConversion(for: newValue)
                            }

                        Button(l10n.t("onboarding.step3.convert")) {
                            updateConversion(for: testInput)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !convertedPreview.isEmpty {
                        HStack {
                            Text(l10n.t("setup.tab.testConversionResult"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(convertedPreview)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.top, 2)
                    }

                    Text(l10n.t("setup.tab.testConversionTip"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)

                // 3. Step-by-Step Wizard Launcher Button
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        NotificationCenter.default.post(name: NSNotification.Name("OpenOnboardingRequested"), object: nil)
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.headline)
                            Text(l10n.t("setup.tab.launchWizard"))
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Text(l10n.t("setup.tab.launchWizardDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 4. Privacy Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        Text(l10n.t("setup.tab.privacyTitle"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text(l10n.t("setup.tab.privacyDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(10)
            }
            .padding(20)
        }
        .onAppear {
            hasAccessibility = AccessibilityService.hasAccessibilityPermission
            updateConversion(for: testInput)
        }
    }

    private func updateConversion(for text: String) {
        let active = settingsManager.enabledLayouts
        let candidateIDs = active.map(\.id)
        let detected = LayoutMapper.detectSourceLayout(text: text, candidateLayouts: candidateIDs)
        let sourceID = detected ?? active.first?.id ?? "com.apple.keylayout.US"
        let targetID = active.first(where: { $0.id != sourceID })?.id ?? "com.apple.keylayout.Russian"
        convertedPreview = LayoutMapper.convert(text: text, from: sourceID, to: targetID) ?? text
    }
}

// MARK: - About Settings Tab

struct AboutSettingsTab: View {
    @EnvironmentObject var l10n: LocalizationManager
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .padding(.top, 10)

                VStack(spacing: 4) {
                    Text(l10n.t("about.appName"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(l10n.t("about.version"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(l10n.t("about.tab.description"))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)

                Divider()
                    .frame(maxWidth: 360)

                VStack(spacing: 8) {
                    Text(l10n.t("about.howToUse"))
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(l10n.t("about.step1"), systemImage: "1.circle")
                        Label(l10n.t("about.step2"), systemImage: "2.circle")
                        Label(l10n.t("about.step3"), systemImage: "3.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(maxWidth: 360)

                HStack(spacing: 16) {
                    Link(l10n.t("about.github"), destination: URL(string: "https://github.com/luksiko/dopishi")!)
                        .font(.caption)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(l10n.t("about.license"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(l10n.t("general.checkNow")) {
                    updateManager.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

// MARK: - Compatibility Aliases for Previous Views

typealias LayoutSettingsTab = LayoutsSettingsTab
typealias HotkeySettingsTab = ShortcutsSettingsTab

// MARK: - User Dictionary Settings Section

struct UserDictionarySettingsSection: View {
    @ObservedObject var userDictionary = UserDictionary.shared
    @EnvironmentObject var l10n: LocalizationManager
    @State private var newWord: String = ""
    @State private var searchText: String = ""
    @State private var isExpanded: Bool = false
    @State private var showClearAlert: Bool = false

    var filteredWords: [String] {
        let all = userDictionary.learnedWordsList
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.t("general.userDictionaryDesc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(l10n.t("general.userDictionaryAddPlaceholder"), text: $newWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addWord()
                        }

                    Button(l10n.t("general.userDictionaryAdd")) {
                        addWord()
                    }
                    .disabled(!userDictionary.canLearn(newWord))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if userDictionary.words.isEmpty {
                    Text(l10n.t("general.userDictionaryEmpty"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    if userDictionary.words.count > 6 {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            TextField(l10n.t("common.search"), text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.caption)
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(5)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredWords, id: \.self) { word in
                                HStack {
                                    Text(word)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                    Button {
                                        userDictionary.forget(word)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(l10n.t("common.delete"))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.06))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .frame(maxHeight: 180)

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Text(l10n.t("general.userDictionaryClearAll"))
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(l10n.t("general.userDictionary"))
                Spacer()
                Text(l10n.t("general.userDictionaryCount").replacingOccurrences(of: "%d", with: "\(userDictionary.words.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(l10n.t("general.userDictionaryClearConfirmTitle"), isPresented: $showClearAlert) {
            Button(l10n.t("common.cancel"), role: .cancel) { }
            Button(l10n.t("general.userDictionaryClearAll"), role: .destructive) {
                userDictionary.removeAll()
            }
        } message: {
            Text(l10n.t("general.userDictionaryClearConfirmMessage"))
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        if userDictionary.learn(trimmed) {
            newWord = ""
        }
    }
}

// MARK: - Launch at Login Helper

enum LaunchAtLoginHelper {
    static func setLaunchAtLogin(_ enabled: Bool) {
        // SMAppService (macOS 13+) is managed by system or bundle helper
    }
}
