import Cocoa
import SwiftUI
import UserNotifications
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    let settingsManager = SettingsManager.shared
    let conversionLogStore = ConversionLogStore.shared
    private var statusBarController: StatusBarController?
    private let hotkeyManager = HotkeyManager()
    private let layoutSwitcher = SingleKeyLayoutSwitcher()
    private let accessibilityService = AccessibilityService()
    private lazy var textConverter = TextConverter(settingsManager: settingsManager)
    private lazy var autoCorrectionService = AutoCorrectionService(
        settingsManager: settingsManager,
        textConverter: textConverter
    )
    
    private var healthTimer: Timer?
    private var instanceLock: AppInstanceLock?
    private var ownsInstance = false
    private var onboardingWindow: NSWindow?

    private var l10n: LocalizationManager { LocalizationManager.shared }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The test host must not compete with the installed app or start monitors.
        guard NSClassFromString("XCTestCase") == nil else { return }
        let identifier = Bundle.main.bundleIdentifier ?? "com.dopishi.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                    && $0.isFinishedLaunching && !$0.isTerminated
            }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("Dopishi", isDirectory: true)
        let legacyDirectory = appSupport.appendingPathComponent("LangSwitcher", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) && FileManager.default.fileExists(atPath: legacyDirectory.path) {
            try? FileManager.default.copyItem(at: legacyDirectory, to: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let lock = try AppInstanceLock(url: directory.appendingPathComponent("instance.lock"))
            guard others.isEmpty, lock.acquired else {
                others.first?.activate(options: [.activateIgnoringOtherApps])
                NSApp.terminate(nil)
                return
            }
            instanceLock = lock
            ownsInstance = true
        } catch {
            let alert = NSAlert()
            alert.messageText = l10n.t("permissions.instanceError")
            alert.informativeText = l10n.t("permissions.instanceErrorDetail")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ownsInstance else { return }
        NSLog("[LangSwitcher] App launched. Bundle: \(Bundle.main.bundlePath)")
        NSLog("[LangSwitcher] Executable: \(Bundle.main.executablePath ?? "unknown")")
        NSLog("[LangSwitcher] PID: \(ProcessInfo.processInfo.processIdentifier)")
        
        // Setup status bar
        statusBarController = StatusBarController(settingsManager: settingsManager)
        statusBarController?.onConvertAction = { [weak self] in
            self?.performConversion()
        }
        statusBarController?.onPreviewRecoveryAction = { [weak self] in
            self?.performRecoveryPreview()
        }
        statusBarController?.onSwitchLayoutAction = { [weak self] in
            self?.performDirectLayoutSwitch()
        }
        
        // Register hotkeys
        registerHotkey()
        registerLayoutSwitchKey()
        
        // Check accessibility permissions and log status
        let trusted = AccessibilityService.hasAccessibilityPermission
        NSLog("[LangSwitcher] Initial AXIsProcessTrusted = \(trusted)")
        if !trusted {
            NSLog("[LangSwitcher] Requesting accessibility permission prompt...")
            AccessibilityService.requestAccessibilityPermission()
        }
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        // Sync launch at login with system ServiceManagement
        LaunchAtLoginHelper.syncStatus(preferenceEnabled: settingsManager.launchAtLogin)
        
        // Listen for settings changes to re-register hotkeys
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsChanged),
            name: .hotkeySettingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(layoutSwitchKeyChanged),
            name: .layoutSwitchKeyChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoCorrectionSettingsChanged),
            name: .autoCorrectionSettingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoCorrectionSettingsChanged),
            name: .autoCompletionSettingsChanged,
            object: nil
        )
        
        ServiceStatus.shared.onRestart = { [weak self] in
            self?.autoCorrectionService.restart()
            self?.autoCorrectionService.checkHealth()
        }
        autoCorrectionService.checkHealth()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoCorrectionService.checkHealth() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        
        // Warm up AI inference engine if enabled
        if settingsManager.isAIAllowed {
            Task { @MainActor in
                await AIInferenceEngine.shared.ensureRunning()
            }
        }

        // Show onboarding on first launch or when accessibility is not granted
        if !settingsManager.hasCompletedOnboarding || !AccessibilityService.hasAccessibilityPermission {
            showOnboarding()
        }

        // Observe request to open onboarding from menu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openOnboardingRequested),
            name: NSNotification.Name("OpenOnboardingRequested"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(closeOnboardingWindow),
            name: NSNotification.Name("CloseOnboardingWindow"),
            object: nil
        )
    }

    @objc private func systemDidWake() {
        guard ownsInstance else { return }
        autoCorrectionService.checkHealth()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ownsInstance else { return }
        autoCorrectionService.checkHealth()
    }

    func applicationWillTerminate(_ notification: Notification) {
        healthTimer?.invalidate()
        AIInferenceEngine.shared.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if ownsInstance { autoCorrectionService.stop() }
        ServiceStatus.shared.onRestart = nil
        instanceLock = nil
    }

    // MARK: - Hotkey Registration
    
    func registerHotkey() {
        if settingsManager.useDoubleShift {
            hotkeyManager.registerDoubleShift { [weak self] in
                Task { @MainActor in
                    self?.performConversion()
                }
            }
        } else {
            hotkeyManager.register(
                keyCode: settingsManager.hotkeyKeyCode,
                modifiers: settingsManager.hotkeyModifierFlags
            ) { [weak self] in
                Task { @MainActor in
                    self?.performConversion()
                }
            }
        }
    }
    
    @objc private func hotkeySettingsChanged() {
        registerHotkey()
    }
    
    @objc private func autoCorrectionSettingsChanged() {
        autoCorrectionService.restart()
    }
    
    // MARK: - Single Key Layout Switch Registration
    
    func registerLayoutSwitchKey() {
        layoutSwitcher.register(key: settingsManager.layoutSwitchKey) { [weak self] in
            MainActor.assumeIsolated {
                self?.performDirectLayoutSwitch()
            }
        }
    }
    
    @objc private func layoutSwitchKeyChanged() {
        registerLayoutSwitchKey()
    }
    
    func performDirectLayoutSwitch() {
        guard let newLayout = KeyboardLayoutDetector.switchToNextLayout(among: settingsManager.enabledLayouts) else {
            return
        }
        playFeedback()
        showLayoutSwitchNotification(layout: newLayout)
    }
    
    // MARK: - Core Conversion Logic
    
    /// Track whether we've already shown the permission alert this session
    private var hasShownPermissionAlert = false
    
    func performConversion() {
        let hasPerm = AccessibilityService.hasAccessibilityPermission
        NSLog("[LangSwitcher] performConversion() called, hasAccessibilityPermission=\(hasPerm)")
        
        if !hasPerm {
            NSLog("[LangSwitcher] AXIsProcessTrusted=false. Will attempt conversion anyway (CGEvent may work with Input Monitoring).")
            if !hasShownPermissionAlert {
                hasShownPermissionAlert = true
                NSLog("[LangSwitcher] TIP: If conversion doesn't work, remove the app from Accessibility list in System Settings and re-add it. Also check Input Monitoring.")
            }
        }
        
        // Try clipboard-based approach first (works when text is selected)
        var capturedInput: String?
        var capturedOutput: String?
        var capturedTargetLayout: String?
        let success = accessibilityService.getAndReplaceSelectedText { [weak self] (text: String) -> String? in
            NSLog("[LangSwitcher] getAndReplaceSelectedText got text: '\(text)' (len=\(text.count))")
            capturedInput = text
            if let info = self?.textConverter.convertSelectedTextWithInfo(text) {
                capturedOutput = info.text
                capturedTargetLayout = info.targetLayoutID
                NSLog("[LangSwitcher] convertSelectedText returned: \(info.text)")
                return info.text
            }
            NSLog("[LangSwitcher] convertSelectedText returned: nil")
            return nil
        }
        
        if success {
            NSLog("[LangSwitcher] Direct conversion succeeded")
            settingsManager.incrementConversionCount()
            logConversion(input: capturedInput, output: capturedOutput, mode: "direct")
            switchLayoutIfNeeded(targetLayoutID: capturedTargetLayout, conversionOccurred: true)
            playFeedback()
            showConversionNotification(input: capturedInput, output: capturedOutput)
            return
        }
        
        // Smart conversion fallback when no text is explicitly selected
        NSLog("[LangSwitcher] Direct conversion failed/no selection. Trying smart conversion after short delay...")
        usleep(50_000) // 50ms — give time for physical modifier release to settle
        let converted = performSmartConversion()
        if !converted {
            switchLayoutIfNeeded(targetLayoutID: nil, conversionOccurred: false)
        }
    }
    
    // MARK: - Smart Conversion Modes
    
    /// Routes to the appropriate smart conversion strategy based on user settings
    @discardableResult
    private func performSmartConversion() -> Bool {
        let mode = settingsManager.smartConversionMode
        NSLog("[LangSwitcher] performSmartConversion() mode=\(mode.displayName)")
        
        switch mode {
        case .disabled:
            NSLog("[LangSwitcher] Smart conversion is disabled")
            return false
            
        case .lastWord:
            return performLastWordConversion()
            
        case .greedyLine:
            return performGreedyLineConversion()
        }
    }
    
    /// Last Word mode: select one word left, convert if it looks wrong
    @discardableResult
    private func performLastWordConversion() -> Bool {
        var capturedInput: String?
        var capturedOutput: String?
        var capturedTargetLayout: String?
        let success = accessibilityService.selectAndReplaceLastWord { [weak self] (text: String) -> String? in
            guard let self = self else { return nil }
            NSLog("[LangSwitcher] lastWord got: '\(text)'")
            
            if self.textConverter.looksLikeWrongLayout(text) {
                capturedInput = text
                if let info = self.textConverter.convertSelectedTextWithInfo(text) {
                    capturedOutput = info.text
                    capturedTargetLayout = info.targetLayoutID
                    return info.text
                }
            }
            return nil
        }
        
        if success {
            settingsManager.incrementConversionCount()
            logConversion(input: capturedInput, output: capturedOutput, mode: "lastWord")
            switchLayoutIfNeeded(targetLayoutID: capturedTargetLayout, conversionOccurred: true)
            playFeedback()
            showConversionNotification(input: capturedInput, output: capturedOutput)
        }
        return success
    }
    
    /// Greedy Line mode: select to line start, find boundary, convert wrong-layout tail.
    /// If Thought Recovery is enabled, span-level reconstruction runs first.
    @discardableResult
    private func performGreedyLineConversion() -> Bool {
        if settingsManager.thoughtRecoveryPreview, settingsManager.thoughtRecoveryEnabled {
            performRecoveryPreview()
            return true
        }

        var capturedInput: String?
        var capturedOutput: String?
        var capturedTargetLayout: String?
        var usedRecovery = false
        let success = accessibilityService.selectLineAndReplace { [weak self] (lineText: String) -> String? in
            guard let self = self else { return nil }
            NSLog("[LangSwitcher] greedyLine got line: '\(lineText)' (len=\(lineText.count))")
            
            capturedInput = lineText

            // Thought Recovery (span level) runs first
            if let recovered = self.textConverter.recoverLine(lineText) {
                capturedOutput = recovered.text
                capturedTargetLayout = recovered.targetLayoutID
                usedRecovery = true
                return recovered.text
            }

            // Fall back to boundary heuristic
            let result = self.textConverter.convertLineGreedyWithInfo(lineText)
            capturedOutput = result?.text
            capturedTargetLayout = result?.targetLayoutID
            return result?.text
        }
        
        if success {
            settingsManager.incrementConversionCount()
            if usedRecovery {
                settingsManager.incrementRecoveryCount()
            }
            logConversion(
                input: capturedInput,
                output: capturedOutput,
                mode: usedRecovery ? "thoughtRecovery" : "greedyLine"
            )
            switchLayoutIfNeeded(targetLayoutID: capturedTargetLayout, conversionOccurred: true)
            playFeedback()
            showConversionNotification(input: capturedInput, output: capturedOutput)
        }
        return success
    }

    // MARK: - Thought Recovery Preview

    private var recoveryPreviewWindow: NSWindow?
    private var recoveryTargetApp: NSRunningApplication?
    private var recoveryOriginalText: String?
    private var recoveryPlan: ThoughtRecovery.Plan?

    /// Select the line but keep the selection active, decode it and show the
    /// reconstruction with its alternatives. The app the line came from gets the
    /// paste back (or its selection collapsed) once the user decides.
    func performRecoveryPreview() {
        guard recoveryPreviewWindow == nil else { return }
        recoveryTargetApp = NSWorkspace.shared.frontmostApplication

        guard let line = accessibilityService.selectLineKeepingSelection() else {
            resetRecoveryState()
            return
        }
        guard let plan = textConverter.recoveryPlan(for: line) else {
            restorationAfterRecovery(action: .collapse)
            resetRecoveryState()
            return
        }

        recoveryOriginalText = line
        recoveryPlan = plan
        showRecoveryPreview(plan: plan)
    }

    private func showRecoveryPreview(plan: ThoughtRecovery.Plan) {
        NSApp.activate(ignoringOtherApps: true)

        let view = RecoveryPreviewView(
            plan: plan,
            onApply: { [weak self] text in
                self?.applyRecovery(text)
            },
            onCopy: { [weak self] text in
                guard let self = self else { return }
                self.accessibilityService.copyToPasteboard(text)
                self.closeRecoveryPreview()
                self.restorationAfterRecovery(action: .collapse)
                self.resetRecoveryState()
            },
            onRevert: { [weak self] in
                self?.revertRecovery()
            },
            onCancel: { [weak self] in
                guard let self = self else { return }
                self.closeRecoveryPreview()
                self.restorationAfterRecovery(action: .collapse)
                self.resetRecoveryState()
            }
        )
        .environmentObject(l10n)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n.t("recovery.title")
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        recoveryPreviewWindow = window
    }

    /// Paste the chosen reconstruction into the app the line came from.
    private func applyRecovery(_ text: String) {
        let original = recoveryOriginalText
        let target = recoveryPlan?.primaryTargetLayoutID
        closeRecoveryPreview()
        restorationAfterRecovery(action: .paste(text))

        settingsManager.incrementConversionCount()
        settingsManager.incrementRecoveryCount()
        logConversion(input: original, output: text, mode: "thoughtRecovery")
        switchLayoutIfNeeded(targetLayoutID: target, conversionOccurred: true)
        playFeedback()
        showConversionNotification(input: original, output: text)
        resetRecoveryState()
    }

    /// Undo: keep the original text and teach the personal dictionary so it is
    /// never rewritten again.
    private func revertRecovery() {
        let original = recoveryOriginalText
        closeRecoveryPreview()
        restorationAfterRecovery(action: .collapse)

        if let original = original {
            let learned = UserDictionary.shared.learnWords(in: original)
            NSLog("[LangSwitcher] revertRecovery: learned words=\(learned)")
        }
        settingsManager.incrementRecoveryRevertCount()
        resetRecoveryState()
    }

    private enum RecoveryRestoration {
        case paste(String)
        case collapse
    }

    /// Put the target app back in front and finish the interaction there.
    private func restorationAfterRecovery(action: RecoveryRestoration) {
        guard let target = recoveryTargetApp else { return }
        target.activate(options: [.activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            switch action {
            case .paste(let text):
                self.accessibilityService.pasteReplacingSelection(text)
            case .collapse:
                self.accessibilityService.collapseSelection()
            }
        }
    }

    private func closeRecoveryPreview() {
        recoveryPreviewWindow?.orderOut(nil)
        recoveryPreviewWindow = nil
    }

    private func resetRecoveryState() {
        recoveryTargetApp = nil
        recoveryOriginalText = nil
        recoveryPlan = nil
    }


    
    // MARK: - Conversion Logging
    
    private func logConversion(input: String?, output: String?, mode: String) {
        guard settingsManager.loggingEnabled else { return }
        guard let input = input, let output = output else { return }
        
        let layouts = settingsManager.enabledLayouts
        let layoutIDs = layouts.map(\.id)
        
        let sourceLayout = LayoutMapper.detectSourceLayout(text: input, candidateLayouts: layoutIDs) ?? "unknown"
        let targetLayout = layouts.first(where: { $0.id != sourceLayout })?.id ?? "unknown"
        
        conversionLogStore.log(
            inputText: input,
            outputText: output,
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            conversionMode: mode
        )
        
        // Trim old entries if max is set
        let maxEntries = settingsManager.logMaxEntries
        if maxEntries > 0 {
            conversionLogStore.trimToMaxEntries(maxEntries)
        }
    }
    
    // MARK: - Layout Switch
    
    /// Switch system keyboard layout to the target after conversion, based on user's setting.
    private func switchLayoutIfNeeded(targetLayoutID: String?, conversionOccurred: Bool) {
        switch settingsManager.layoutSwitchMode {
        case .always:
            if let targetLayoutID = targetLayoutID, !targetLayoutID.isEmpty {
                KeyboardLayoutDetector.switchToLayout(targetLayoutID)
            } else {
                _ = KeyboardLayoutDetector.switchToNextLayout(among: settingsManager.enabledLayouts)
            }
        case .ifLastWordConverted, .ifAnyWordConverted:
            if conversionOccurred, let targetLayoutID = targetLayoutID, !targetLayoutID.isEmpty {
                KeyboardLayoutDetector.switchToLayout(targetLayoutID)
            }
        case .never:
            break
        }
    }
    
    // MARK: - Notifications
    
    /// Show a macOS notification about the conversion result.
    private func showConversionNotification(input: String?, output: String?) {
        guard settingsManager.showNotifications else { return }
        guard let input = input, let output = output else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Dopishi"
        content.body = "\(input) → \(output)"
        content.sound = nil // Sound is handled separately by playSounds setting
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[LangSwitcher] Failed to show notification: \(error)")
            }
        }
    }
    
    /// Show a macOS notification when switching layout via single key.
    private func showLayoutSwitchNotification(layout: KeyboardLayout) {
        guard settingsManager.showNotifications else { return }
        
        let activeLayout = KeyboardLayoutDetector.getCurrentLayout() ?? layout
        
        let content = UNMutableNotificationContent()
        content.title = "Dopishi"
        content.body = l10n.t("notification.layoutSwitched").replacingOccurrences(of: "%@", with: activeLayout.displayName)
        content.sound = nil
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[LangSwitcher] Failed to show layout switch notification: \(error)")
            }
        }
    }
    
    // MARK: - Feedback
    
    private func playFeedback() {
        if settingsManager.playSounds {
            NSSound(named: .init("Tink"))?.play()
        }
    }
    
    // MARK: - Onboarding

    func showOnboarding() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = onboardingWindow, window.isVisible {
            window.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let onboardingView = OnboardingView()
            .environmentObject(settingsManager)
            .environmentObject(LocalizationManager.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 490),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = l10n.t("onboarding.windowTitle")
        window.center()
        window.contentView = NSHostingView(rootView: onboardingView)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        onboardingWindow = window
    }

    @objc private func openOnboardingRequested() {
        showOnboarding()
    }

    @objc private func closeOnboardingWindow() {
        onboardingWindow?.close()
    }

    private func showAccessibilityAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = l10n.t("alert.accessibilityTitle")
        alert.informativeText = l10n.t("alert.accessibilityMessage")
        alert.alertStyle = .warning
        alert.addButton(withTitle: l10n.t("alert.openSystemSettings"))
        alert.addButton(withTitle: l10n.t("alert.continueAnyway"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
    static let layoutSwitchKeyChanged = Notification.Name("layoutSwitchKeyChanged")
    static let autoCorrectionSettingsChanged = Notification.Name("autoCorrectionSettingsChanged")
    static let autoCompletionSettingsChanged = Notification.Name("autoCompletionSettingsChanged")
    static let statusBarIconStyleChanged = Notification.Name("statusBarIconStyleChanged")
    static let keyboardLayoutSelectionChanged = Notification.Name("keyboardLayoutSelectionChanged")
    static let enabledLayoutsDidChange = Notification.Name("enabledLayoutsDidChange")
    static let aiSettingsChanged = Notification.Name("aiSettingsChanged")
}

/// Kernel lock survives simultaneous launches and is released automatically on
/// crash. Keep the lock file: unlinking it can let two processes lock different inodes.
final class AppInstanceLock {
    private let descriptor: Int32
    let acquired: Bool

    init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        acquired = flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }

    deinit { close(descriptor) }
}
