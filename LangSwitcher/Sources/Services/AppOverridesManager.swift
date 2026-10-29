import Foundation
import AppKit

// MARK: - App Overrides Manager
// Manages per-application rules, presets (IDEs, games, virtualization),
// and determines whether automatic or manual-only completion is permitted.

@MainActor
final class AppOverridesManager {
    static let shared = AppOverridesManager()

    // MARK: - Known App Categories

    /// Known IDEs and code editors where inline auto-triggers might conflict with native language servers
    static let knownDevelopmentApps: [String: String] = [
        "com.apple.dt.Xcode": "Xcode",
        "com.microsoft.VSCode": "Visual Studio Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.visualstudio.code.oss": "Code - OSS",
        "com.vscodium": "VSCodium",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "com.sublimetext.3": "Sublime Text",
        "com.sublimetext.4": "Sublime Text",
        "com.barebones.bbedit": "BBEdit",
        "com.panic.Nova": "Nova",
        "com.jetbrains.intellij": "IntelliJ IDEA",
        "com.jetbrains.intellij.ce": "IntelliJ IDEA CE",
        "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.pycharm.ce": "PyCharm CE",
        "com.jetbrains.webstorm": "WebStorm",
        "com.jetbrains.CLion": "CLion",
        "com.jetbrains.goland": "GoLand",
        "com.jetbrains.rider": "Rider",
        "com.jetbrains.rustrover": "RustRover",
        "com.jetbrains.AppCode": "AppCode",
        "com.google.android.studio": "Android Studio"
    ]

    /// Known games, launchers, and virtualization apps where suggestions should be suppressed by default
    static let knownGamingAndVirtualizationApps: [String: String] = [
        "com.valvesoftware.steam": "Steam",
        "com.epicgames.EpicGamesLauncher": "Epic Games",
        "net.battle.net": "Battle.net",
        "com.mojang.minecraftlauncher": "Minecraft",
        "com.roblox.RobloxPlayer": "Roblox",
        "com.parallels.desktop.console": "Parallels Desktop",
        "com.vmware.fusion": "VMware Fusion",
        "com.utmapp.UTM": "UTM",
        "com.microsoft.rdc.macos": "Remote Desktop",
        "com.anydesk.anydesk": "AnyDesk",
        "com.teamviewer.TeamViewer": "TeamViewer"
    ]

    // MARK: - Querying Completion Modes

    /// Returns the effective completion mode for a given bundle ID.
    func completionMode(for bundleID: String?) -> AppCompletionMode {
        guard let bundleID = bundleID, !bundleID.isEmpty else { return .automatic }

        // 1. Explicit user per-app settings take highest priority
        if let userSetting = SettingsManager.shared.perAppAISettings[bundleID] {
            return userSetting.completionMode
        }

        // 2. Default rule: Gaming and virtualization apps are disabled by default
        if Self.knownGamingAndVirtualizationApps[bundleID] != nil {
            return .disabled
        }

        // 3. Fallback: standard automatic mode
        return .automatic
    }

    /// Whether automatic suggestions / ghost text should be triggered while typing in this app.
    func shouldAutoTrigger(for bundleID: String?) -> Bool {
        completionMode(for: bundleID) == .automatic
    }

    /// Whether completions can be activated (taking manual invocation into account).
    func isAllowed(for bundleID: String?, isManualTrigger: Bool) -> Bool {
        let mode = completionMode(for: bundleID)
        switch mode {
        case .disabled:
            return false
        case .manualOnly:
            return isManualTrigger
        case .automatic:
            return true
        }
    }

    /// Helper to identify if an app is a development tool
    func isDevelopmentApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.knownDevelopmentApps[bundleID] != nil
    }

    /// Helper to identify if an app is a game or virtualization tool
    func isGamingOrVirtualizationApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return Self.knownGamingAndVirtualizationApps[bundleID] != nil
    }

    // MARK: - Mutating Per-App Rules

    /// Updates or creates the completion mode for a specific bundle ID.
    func setCompletionMode(_ mode: AppCompletionMode, for bundleID: String, appName: String) {
        var setting = SettingsManager.shared.perAppAISettings[bundleID] ?? AppAISettings(bundleID: bundleID, appName: appName)
        setting.completionMode = mode
        SettingsManager.shared.setAppAISettings(setting)
    }
}
