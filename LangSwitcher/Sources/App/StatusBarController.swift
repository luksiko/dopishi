import Cocoa
import SwiftUI
import Carbon

// MARK: - Status Bar Badge Renderer

struct StatusBarBadgeRenderer {

    /// Resolve 2-letter uppercase badge code (e.g. "RU", "EN", "UK") from a KeyboardLayout
    static func languageCode(for layout: KeyboardLayout?) -> String {
        guard let layout = layout else { return "EN" }
        return languageCode(layoutId: layout.id, languageCode: layout.languageCode, localizedName: layout.localizedName)
    }

    /// Pure function mapping layout identifiers, language codes and names to badge text
    static func languageCode(layoutId: String, languageCode: String, localizedName: String) -> String {
        // Priority 1: use valid ISO language code if known (e.g. "en", "ru", "it-IT", "uk_UA")
        var code = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hyphenIndex = code.firstIndex(of: "-") {
            code = String(code[..<hyphenIndex])
        }
        if let underscoreIndex = code.firstIndex(of: "_") {
            code = String(code[..<underscoreIndex])
        }
        if !code.isEmpty && code.lowercased() != "unknown" {
            return String(code.prefix(2)).uppercased()
        }

        // Priority 2: match known layout IDs (ensure "russian" comes before "us")
        let idLower = layoutId.lowercased()
        if idLower.contains("russian") { return "RU" }
        if idLower.contains("ukrainian") { return "UK" }
        if idLower.contains("german") { return "DE" }
        if idLower.contains("french") { return "FR" }
        if idLower.contains("spanish") { return "ES" }
        if idLower.contains("italian") { return "IT" }
        if idLower.contains("tajik") { return "TG" }
        if idLower.contains("kazakh") { return "KZ" }
        if idLower.contains("belarusian") { return "BE" }
        if idLower.contains("turkish") { return "TR" }
        if idLower.contains("hebrew") { return "HE" }
        if idLower.contains("greek") { return "EL" }
        if idLower.contains(".us") || idLower.contains("us-") || idLower.contains("us_") || idLower.hasSuffix(".us") || idLower.contains("abc") || idLower.contains("english") {
            return "EN"
        }

        // Priority 3: first 2 characters of localized name
        let trimmedName = localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.count >= 2 {
            return String(trimmedName.prefix(2)).uppercased()
        }

        return "EN"
    }

    /// Renders an NSImage with the language text enclosed in a rounded-corner frame
    static func renderBadge(text: String, hasAttentionDot: Bool = false) -> NSImage {
        let font = NSFont.systemFont(ofSize: 9.0, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = (text as NSString).size(withAttributes: attrs)
        let badgeWidth = max(24.0, ceil(textSize.width) + 8.0)
        let badgeHeight: CGFloat = 16.0
        let imageSize = NSSize(width: badgeWidth, height: badgeHeight)

        let image = NSImage(size: imageSize, flipped: false) { rect in
            let borderRect = NSRect(x: 1.0, y: 1.0, width: badgeWidth - 2.0, height: badgeHeight - 2.0)
            let path = NSBezierPath(roundedRect: borderRect, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.2
            NSColor.black.setStroke()
            path.stroke()

            let textY = (badgeHeight - font.capHeight) / 2.0 + font.descender
            let textRect = NSRect(x: 0, y: textY, width: badgeWidth, height: textSize.height)
            (text as NSString).draw(in: textRect, withAttributes: attrs)

            if hasAttentionDot {
                let dotRect = NSRect(x: badgeWidth - 5.0, y: badgeHeight - 5.0, width: 4.0, height: 4.0)
                let dotPath = NSBezierPath(ovalIn: dotRect)
                NSColor.systemOrange.setFill()
                dotPath.fill()
            }
            return true
        }
        image.isTemplate = !hasAttentionDot
        return image
    }
}

// MARK: - Status Bar Controller
// Manages the menu bar icon and dropdown menu

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {

    static weak var shared: StatusBarController?
    static let openSettingsNotification = Notification.Name("OpenSettingsRequested")

    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private let settingsManager: SettingsManager
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var lastActiveExternalApp: NSRunningApplication?

    var onConvertAction: (() -> Void)?
    var onPreviewRecoveryAction: (() -> Void)?
    var onSwitchLayoutAction: (() -> Void)?

    private var l10n: LocalizationManager { LocalizationManager.shared }

    private var currentTargetApp: NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           bid != Bundle.main.bundleIdentifier,
           bid != "com.apple.dock",
           bid != "com.apple.systemuiserver" {
            return front
        }
        return lastActiveExternalApp
    }

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.statusBar = NSStatusBar.system
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        super.init()
        Self.shared = self

        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           bid != Bundle.main.bundleIdentifier {
            self.lastActiveExternalApp = front
        }

        menu.delegate = self
        setupStatusBarButton()
        setupMenu()
        setupObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        settingsManager.refreshSystemLayouts()
        setupMenu()
    }

    // MARK: - Setup

    private func setupStatusBarButton() {
        updateStatusBarIcon()
        statusItem.menu = menu
    }

    /// Updates status bar icon based on user settings and current layout
    @objc func updateStatusBarIcon() {
        guard let button = statusItem.button else { return }
        let hasAttention = AttentionCenter.shared.hasWarningOrCriticalIssues

        switch settingsManager.statusBarIconStyle {
        case .keyboardIcon:
            if hasAttention {
                let base = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Dopishi")
                let size = base?.size ?? NSSize(width: 18, height: 16)
                let image = NSImage(size: size, flipped: false) { rect in
                    base?.draw(in: rect)
                    let dotRect = NSRect(x: size.width - 4.5, y: size.height - 4.5, width: 4.0, height: 4.0)
                    let dotPath = NSBezierPath(ovalIn: dotRect)
                    NSColor.systemOrange.setFill()
                    dotPath.fill()
                    return true
                }
                button.image = image
            } else {
                let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Dopishi")
                image?.isTemplate = true
                button.image = image
            }
        case .languageBadge:
            let currentLayout = KeyboardLayoutDetector.getCurrentLayout()
            let badgeText = StatusBarBadgeRenderer.languageCode(for: currentLayout)
            let image = StatusBarBadgeRenderer.renderBadge(text: badgeText, hasAttentionDot: hasAttention)
            button.image = image
        }

        let tooltip = l10n.t("menu.tooltip").replacingOccurrences(of: "%@", with: settingsManager.hotkeyDescription)
        button.toolTip = tooltip
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardLayoutDidChange),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardLayoutDidChange),
            name: .keyboardLayoutSelectionChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardLayoutDidChange),
            name: .enabledLayoutsDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(statusBarIconStyleChanged),
            name: .statusBarIconStyleChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: Self.openSettingsNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardLayoutDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           let bid = app.bundleIdentifier,
           bid != Bundle.main.bundleIdentifier,
           bid != "com.apple.dock",
           bid != "com.apple.systemuiserver" {
            lastActiveExternalApp = app
        }
    }

    @objc private func keyboardLayoutDidChange() {
        Task { @MainActor in
            self.updateStatusBarIcon()
        }
    }

    @objc private func statusBarIconStyleChanged() {
        Task { @MainActor in
            self.updateStatusBarIcon()
        }
    }

    private func setupMenu() {
        menu.removeAllItems()

        // ── 1. Attention Center (Only shown when there are issues) ──
        AttentionCenter.shared.refreshIssues()
        if AttentionCenter.shared.hasActiveIssues {
            let attentionHeader = NSMenuItem(title: l10n.t("attention.header"), action: nil, keyEquivalent: "")
            attentionHeader.isEnabled = false
            let attentionAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 12),
                .foregroundColor: NSColor.systemOrange
            ]
            attentionHeader.attributedTitle = NSAttributedString(
                string: "⚠️ " + l10n.t("attention.header"),
                attributes: attentionAttrs
            )
            menu.addItem(attentionHeader)

            for issue in AttentionCenter.shared.activeIssues {
                let item = NSMenuItem(
                    title: "  " + l10n.t(issue.titleKey),
                    action: #selector(handleAttentionIssue(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = issue.id.rawValue
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
        }

        // ── 2. App Context & Active Control ─────────────────────────
        if let app = currentTargetApp, let bundleID = app.bundleIdentifier {
            let appName = app.localizedName ?? bundleID
            let isExcluded = settingsManager.isAppExcluded(bundleID: bundleID)
            let title = isExcluded
                ? l10n.t("menu.appDisabled").replacingOccurrences(of: "%@", with: appName)
                : l10n.t("menu.appActive").replacingOccurrences(of: "%@", with: appName)
            let appItem = NSMenuItem(title: title, action: #selector(toggleCurrentAppExclusion(_:)), keyEquivalent: "")
            appItem.target = self
            appItem.representedObject = bundleID
            menu.addItem(appItem)
        }

        if settingsManager.isTemporarilyPaused {
            let remainingMinutes = max(1, Int(ceil((settingsManager.temporaryPauseUntil?.timeIntervalSinceNow ?? 0) / 60.0)))
            let title = l10n.t("menu.resumeNow").replacingOccurrences(of: "%d", with: "\(remainingMinutes)")
            let resumeItem = NSMenuItem(title: title, action: #selector(resumeAction), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        } else {
            let pauseItem = NSMenuItem(title: l10n.t("menu.pause30Min"), action: #selector(pause30MinAction), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)
        }

        menu.addItem(NSMenuItem.separator())

        // ── 3. Core Status & Toggles ────────────────────────────────
        // AI suggestions toggle
        let aiToggleItem = NSMenuItem(
            title: l10n.t("menu.aiAssistant"),
            action: #selector(toggleAIAssistant),
            keyEquivalent: ""
        )
        aiToggleItem.target = self
        aiToggleItem.state = settingsManager.aiPredictiveEnabled ? .on : .off
        menu.addItem(aiToggleItem)

        // Compact Layouts Submenu with active codes
        let layoutsSubmenu = NSMenu()
        let currentLayout = KeyboardLayoutDetector.getCurrentLayout()
        for layout in settingsManager.enabledLayouts {
            let isCurrent = (layout.id == currentLayout?.id || layout.languageCode.lowercased() == currentLayout?.languageCode.lowercased())
            let prefix = isCurrent ? "✓ " : "   "
            let item = NSMenuItem(
                title: "\(prefix)\(layout.displayName)",
                action: #selector(selectLayoutAction(_:)),
                keyEquivalent: ""
            )
            item.representedObject = layout.id
            item.target = self
            layoutsSubmenu.addItem(item)
        }
        let codes = settingsManager.enabledLayouts.map { $0.languageCode.uppercased() }.filter { !$0.isEmpty }
        let summary = codes.isEmpty ? "" : " (\(codes.joined(separator: ", ")))"
        let layoutsParentItem = NSMenuItem(
            title: "\(l10n.t("menu.layoutsSubmenu"))\(summary)",
            action: nil,
            keyEquivalent: ""
        )
        layoutsParentItem.submenu = layoutsSubmenu
        menu.addItem(layoutsParentItem)

        // Conversion History
        let historyItem = NSMenuItem(
            title: l10n.t("menu.conversionHistory"),
            action: #selector(openHistorySettings),
            keyEquivalent: "h"
        )
        historyItem.keyEquivalentModifierMask = [.command]
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())

        // ── 4. Settings & Quit ──────────────────────────────────────
        let settingsItem = NSMenuItem(
            title: l10n.t("menu.settings"),
            action: #selector(openSettingsDefault),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: l10n.t("menu.checkForUpdates"),
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: l10n.t("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleCurrentAppExclusion(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if settingsManager.isAppExcluded(bundleID: bundleID) {
            settingsManager.removeExcludedApp(bundleID: bundleID)
        } else {
            settingsManager.addExcludedApp(bundleID: bundleID)
        }
        setupMenu()
    }

    @objc private func resumeAction() {
        settingsManager.resumeFromPause()
        setupMenu()
    }

    @objc private func pause30MinAction() {
        settingsManager.pauseTemporarily(minutes: 30)
        setupMenu()
    }

    @objc private func toggleAIAssistant() {
        settingsManager.aiPredictiveEnabled.toggle()
        if settingsManager.aiPredictiveEnabled {
            Task { @MainActor in
                await AIInferenceEngine.shared.ensureRunning()
            }
        } else {
            AIInferenceEngine.shared.stop()
        }
        setupMenu()
    }

    @objc private func toggleBatteryEcoMode() {
        settingsManager.aiBatteryModeEnabled.toggle()
        setupMenu()
    }

    @objc private func openAISettings() {
        openSettings(tab: SettingsSidebarTab.ai.rawValue)
    }

    @objc private func openHistorySettings() {
        openSettings(tab: SettingsSidebarTab.history.rawValue)
    }

    @objc private func openSettingsDefault() {
        openSettings(tab: SettingsSidebarTab.general.rawValue)
    }

    @objc private func handleAttentionIssue(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let issueType = AttentionIssueType(rawValue: idString) else { return }
        AttentionCenter.shared.resolve(issue: issueType)
        updateStatusBarIcon()
    }

    @objc private func convertAction() {
        onConvertAction?()
    }

    @objc private func previewRecoveryAction() {
        onPreviewRecoveryAction?()
    }

    @objc private func thesaurusAction() {
        ThesaurusController.shared.triggerForCurrentSelection()
    }

    @objc private func smartRepliesAction() {
        SmartRepliesController.shared.triggerSmartReplies()
    }

    @objc private func switchLayoutAction() {
        onSwitchLayoutAction?()
    }

    @objc private func selectLayoutAction(_ sender: NSMenuItem) {
        if let targetID = sender.representedObject as? String {
            KeyboardLayoutDetector.switchToLayout(targetID)
        }
    }

    @objc func openSettings() {
        openSettings(tab: SettingsSidebarTab.general.rawValue)
    }

    func openSettings(tab: Int = SettingsSidebarTab.general.rawValue) {
        settingsManager.selectedSettingsTab = tab
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(settingsManager)
            .environmentObject(l10n)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 520)
        window.title = l10n.t("settings.windowTitle")
        window.center()
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
    }

    @objc private func openSetupWizard() {
        NotificationCenter.default.post(name: NSNotification.Name("OpenOnboardingRequested"), object: nil)
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = aboutWindow, window.isVisible {
            window.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n.t("about.windowTitle")
        window.center()
        window.contentView = NSHostingView(rootView: AboutView().environmentObject(l10n))
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        aboutWindow = window
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    /// Refresh the menu (call after settings change)
    func refreshMenu() {
        setupMenu()
        updateStatusBarIcon()
    }
}
