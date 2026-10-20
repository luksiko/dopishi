import SwiftUI
import AppKit

// MARK: - Excluded Apps Settings View
// UI for managing applications where autocompletion and auto-correction are disabled.

struct ExcludedAppsSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    
    @State private var runningApps: [NSRunningApplication] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("excludedApps.desc"))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // List of excluded apps
            if settingsManager.excludedAppBundleIDs.isEmpty {
                Text(l10n.t("excludedApps.empty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                List {
                    ForEach(settingsManager.excludedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            if let icon = iconForBundle(bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app")
                                    .frame(width: 20, height: 20)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName(for: bundleID))
                                    .font(.subheadline)
                                Text(bundleID)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                settingsManager.removeExcludedApp(bundleID: bundleID)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(minHeight: 120, maxHeight: 180)
                .listStyle(.bordered)
            }
            
            // Action buttons
            HStack(spacing: 10) {
                // Add from Running Apps Menu
                Menu {
                    ForEach(runningApps, id: \.processIdentifier) { app in
                        if let bid = app.bundleIdentifier, !settingsManager.isAppExcluded(bundleID: bid) {
                            Button {
                                settingsManager.addExcludedApp(bundleID: bid)
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
                    Label(l10n.t("excludedApps.addRunning"), systemImage: "plus.app")
                }
                .menuStyle(.borderedButton)
                
                // Add from Applications Folder
                Button {
                    chooseAppFromDisk()
                } label: {
                    Label(l10n.t("excludedApps.chooseFromDisk"), systemImage: "folder")
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .onAppear {
            refreshRunningApps()
        }
    }
    
    private func refreshRunningApps() {
        let currentBundleID = Bundle.main.bundleIdentifier ?? "com.langswitcher.app"
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != currentBundleID }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    private func chooseAppFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                settingsManager.addExcludedApp(bundleID: bundleID)
            }
        }
    }
    
    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let bundle = Bundle(url: url) {
            return bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }
    
    private func iconForBundle(_ bundleID: String) -> NSImage? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }
}
