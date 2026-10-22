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
    static func renderBadge(text: String) -> NSImage {
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
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Status Bar Controller
// Manages the menu bar icon and dropdown menu

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    
    private var statusBar: NSStatusBar
    private var statusItem: NSStatusItem
    private var menu: NSMenu
    private let settingsManager: SettingsManager
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    
    var onConvertAction: (() -> Void)?
    var onPreviewRecoveryAction: (() -> Void)?
    var onSwitchLayoutAction: (() -> Void)?
    
    private var l10n: LocalizationManager { LocalizationManager.shared }
    
    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        self.statusBar = NSStatusBar.system
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()
        
        super.init()
        
        menu.delegate = self
        setupStatusBarButton()
        setupMenu()
        setupObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    // MARK: - NSMenuDelegate
    
    func menuWillOpen(_ menu: NSMenu) {
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
        
        switch settingsManager.statusBarIconStyle {
        case .keyboardIcon:
            let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Dopishi")
            image?.isTemplate = true
            button.image = image
        case .languageBadge:
            let currentLayout = KeyboardLayoutDetector.getCurrentLayout()
            let badgeText = StatusBarBadgeRenderer.languageCode(for: currentLayout)
            let image = StatusBarBadgeRenderer.renderBadge(text: badgeText)
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
            selector: #selector(statusBarIconStyleChanged),
            name: .statusBarIconStyleChanged,
            object: nil
        )
        
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(keyboardLayoutDidChange),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
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
        
        // Header
        let headerItem = NSMenuItem(title: "Dopishi", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 13)
        ]
        headerItem.attributedTitle = NSAttributedString(string: l10n.t("menu.header"), attributes: attrs)
        menu.addItem(headerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Convert action
        let convertItem = NSMenuItem(
            title: "\(l10n.t("menu.convertText")) (\(settingsManager.hotkeyDescription))",
            action: #selector(convertAction),
            keyEquivalent: ""
        )
        convertItem.target = self
        menu.addItem(convertItem)

        // Thought Recovery preview
        let previewItem = NSMenuItem(
            title: l10n.t("menu.previewRecovery"),
            action: #selector(previewRecoveryAction),
            keyEquivalent: ""
        )
        previewItem.target = self
        previewItem.isEnabled = settingsManager.thoughtRecoveryEnabled
        menu.addItem(previewItem)

        // Direct switch layout action
        let switchKeyTitle: String
        if settingsManager.layoutSwitchKey != .disabled {
            switchKeyTitle = "\(l10n.t("menu.switchLayout")) (\(settingsManager.layoutSwitchKey.displayName))"
        } else {
            switchKeyTitle = l10n.t("menu.switchLayout")
        }
        let switchItem = NSMenuItem(
            title: switchKeyTitle,
            action: #selector(switchLayoutAction),
            keyEquivalent: ""
        )
        switchItem.target = self
        menu.addItem(switchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Active layouts info
        let layoutsHeader = NSMenuItem(title: l10n.t("menu.activeLayouts"), action: nil, keyEquivalent: "")
        layoutsHeader.isEnabled = false
        menu.addItem(layoutsHeader)
        
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
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Stats
        let statsItem = NSMenuItem(
            title: "\(l10n.t("menu.conversions")) \(settingsManager.conversionCount)",
            action: nil,
            keyEquivalent: ""
        )
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(
            title: l10n.t("menu.settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(
            title: l10n.t("menu.about"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: l10n.t("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }
    
    // MARK: - Actions
    
    @objc private func convertAction() {
        onConvertAction?()
    }

    @objc private func previewRecoveryAction() {
        onPreviewRecoveryAction?()
    }

    @objc private func switchLayoutAction() {
        onSwitchLayoutAction?()
    }
    
    @objc private func selectLayoutAction(_ sender: NSMenuItem) {
        if let targetID = sender.representedObject as? String {
            KeyboardLayoutDetector.switchToLayout(targetID)
        }
    }
    
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        let settingsView = SettingsView()
            .environmentObject(settingsManager)
            .environmentObject(l10n)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n.t("settings.windowTitle")
        window.center()
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        
        settingsWindow = window
    }
    
    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = aboutWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
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
        window.makeKeyAndOrderFront(nil)
        
        aboutWindow = window
    }
    
    /// Refresh the menu (call after settings change)
    func refreshMenu() {
        setupMenu()
        updateStatusBarIcon()
    }
}
