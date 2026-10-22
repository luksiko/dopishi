import SwiftUI
import AppKit

// MARK: - Apps Settings Tab
// Unified UI for managing per-application rules: layout conversion exclusions,
// auto-correction, and AI autocompletion custom settings.

struct AppsSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    @State private var runningApps: [NSRunningApplication] = []
    @State private var appMetadataCache: [String: (name: String, icon: NSImage?)] = [:]
    @State private var expandedBundleID: String?
    @State private var vocabularyDrafts: [String: String] = [:]

    private var configuredBundleIDs: [String] {
        var set = Set(settingsManager.excludedAppBundleIDs)
        set.formUnion(settingsManager.perAppAISettings.keys)
        return Array(set).sorted {
            metadata(for: $0).name.localizedCaseInsensitiveCompare(metadata(for: $1).name) == .orderedAscending
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t("apps.title"))
                        .font(.headline)
                    Text(l10n.t("apps.description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section {
                if configuredBundleIDs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 36))
                            .foregroundStyle(.tertiary)
                        Text(l10n.t("apps.empty"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(configuredBundleIDs, id: \.self) { bundleID in
                        appRuleRow(for: bundleID)
                    }
                }
            } header: {
                HStack {
                    Text(l10n.t("apps.title"))
                    Spacer()

                    // Add from Running Apps Menu
                    Menu {
                        ForEach(runningApps, id: \.processIdentifier) { app in
                            if let bid = app.bundleIdentifier, !configuredBundleIDs.contains(bid) {
                                Button {
                                    addApp(bundleID: bid, name: app.localizedName ?? bid)
                                } label: {
                                    HStack {
                                        if let icon = app.icon {
                                            Image(nsImage: icon)
                                        }
                                        Text(app.localizedName ?? bid)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(l10n.t("apps.addRunning"), systemImage: "plus")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)

                    // Add from Applications Folder
                    Button {
                        chooseAppFromDisk()
                    } label: {
                        Label(l10n.t("apps.chooseFromDisk"), systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshRunningApps()
            populateMetadata()
        }
    }

    // MARK: - App Row View

    @ViewBuilder
    private func appRuleRow(for bundleID: String) -> some View {
        let meta = metadata(for: bundleID)
        let isExpanded = expandedBundleID == bundleID
        let isLayoutExcluded = settingsManager.isAppExcluded(bundleID: bundleID)
        let aiSetting = settingsManager.perAppAISettings[bundleID]
        let isAIOff = aiSetting != nil && !aiSetting!.isAIEnabled
        let hasCustomPrompt = aiSetting != nil && (!aiSetting!.customInstructions.isEmpty || !aiSetting!.customVocabulary.isEmpty)

        VStack(alignment: .leading, spacing: 8) {
            // Summary Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedBundleID = isExpanded ? nil : bundleID
                }
            } label: {
                HStack(spacing: 10) {
                    if let icon = meta.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 22))
                            .frame(width: 26, height: 26)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text(bundleID)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Status Badges
                    if isLayoutExcluded {
                        Text(l10n.t("apps.badge.layoutOff"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }

                    if isAIOff {
                        Text(l10n.t("apps.badge.aiOff"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.18))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }

                    if hasCustomPrompt {
                        Text(l10n.t("apps.badge.customPrompt"))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.18))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Controls
            if isExpanded {
                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    // Layout exclusion toggle
                    Toggle(
                        l10n.t("apps.disableLayout"),
                        isOn: Binding(
                            get: { settingsManager.isAppExcluded(bundleID: bundleID) },
                            set: { disabled in
                                if disabled {
                                    settingsManager.addExcludedApp(bundleID: bundleID)
                                } else {
                                    settingsManager.removeExcludedApp(bundleID: bundleID)
                                }
                            }
                        )
                    )

                    // AI completion toggle
                    Toggle(
                        l10n.t("apps.enableAI"),
                        isOn: Binding(
                            get: { settingsManager.perAppAISettings[bundleID]?.isAIEnabled ?? true },
                            set: { enabled in
                                var setting = settingsManager.perAppAISettings[bundleID] ?? AppAISettings(bundleID: bundleID, appName: meta.name)
                                setting.isAIEnabled = enabled
                                settingsManager.setAppAISettings(setting)
                            }
                        )
                    )

                    // AI Details if enabled
                    if settingsManager.perAppAISettings[bundleID]?.isAIEnabled ?? true {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(l10n.t("apps.customInstructions"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ProBadge()
                            }

                            TextEditor(text: Binding(
                                get: { settingsManager.perAppAISettings[bundleID]?.customInstructions ?? "" },
                                set: { newText in
                                    var setting = settingsManager.perAppAISettings[bundleID] ?? AppAISettings(bundleID: bundleID, appName: meta.name)
                                    setting.customInstructions = newText
                                    settingsManager.setAppAISettings(setting)
                                }
                            ))
                            .font(.caption)
                            .frame(height: 54)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(l10n.t("apps.customVocabulary"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ProBadge()
                            }

                            TextField("", text: Binding(
                                get: {
                                    vocabularyDrafts[bundleID] ?? (settingsManager.perAppAISettings[bundleID]?.customVocabulary.joined(separator: ", ") ?? "")
                                },
                                set: { newValue in
                                    vocabularyDrafts[bundleID] = newValue
                                    var setting = settingsManager.perAppAISettings[bundleID] ?? AppAISettings(bundleID: bundleID, appName: meta.name)
                                    setting.customVocabulary = newValue.components(separatedBy: ",")
                                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                    settingsManager.setAppAISettings(setting)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        }
                    }

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            removeAppRules(bundleID: bundleID)
                        } label: {
                            Label(l10n.t("apps.remove"), systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 36)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Actions

    private func addApp(bundleID: String, name: String) {
        let setting = AppAISettings(bundleID: bundleID, appName: name)
        settingsManager.setAppAISettings(setting)
        expandedBundleID = bundleID
    }

    private func removeAppRules(bundleID: String) {
        settingsManager.removeExcludedApp(bundleID: bundleID)
        settingsManager.removeAppAISettings(bundleID: bundleID)
        vocabularyDrafts.removeValue(forKey: bundleID)
        if expandedBundleID == bundleID {
            expandedBundleID = nil
        }
    }

    private func refreshRunningApps() {
        let currentBundleID = Bundle.main.bundleIdentifier ?? "com.dopishi.app"
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != currentBundleID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseAppFromDisk() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                addApp(bundleID: bundleID, name: name)
            }
        }
    }

    private func populateMetadata() {
        for bid in configuredBundleIDs {
            _ = metadata(for: bid)
        }
    }

    private func metadata(for bundleID: String) -> (name: String, icon: NSImage?) {
        if let cached = appMetadataCache[bundleID] {
            return cached
        }
        let name: String
        var icon: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            if let bundle = Bundle(url: url) {
                name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
            } else {
                name = url.deletingPathExtension().lastPathComponent
            }
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            name = bundleID
        }
        let data = (name: name, icon: icon)
        DispatchQueue.main.async {
            self.appMetadataCache[bundleID] = data
        }
        return data
    }
}

// MARK: - Compatibility Alias
typealias ExcludedAppsSettingsView = AppsSettingsTab
