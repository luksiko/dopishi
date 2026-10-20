import Foundation

// MARK: - English Strings
// To add a new language, copy this file as Strings_xx.swift,
// translate every value, and call register() in initializeLocalization().

enum Strings_en {

    static let strings: [String: String] = [

        // ── Menu (StatusBarController) ──────────────────────────────
        "menu.header":                   "⌨ LangSwitcher",
        "menu.convertText":              "Convert Text",
        "menu.switchLayout":             "Switch Keyboard Layout",
        "menu.activeLayouts":            "Active Layouts:",
        "menu.conversions":              "Conversions:",
        "menu.settings":                 "Settings...",
        "menu.about":                    "About LangSwitcher",
        "menu.quit":                     "Quit LangSwitcher",
        "menu.tooltip":                  "LangSwitcher — %@ to convert",

        // ── Settings Window ─────────────────────────────────────────
        "settings.windowTitle":          "LangSwitcher Settings",
        "settings.tab.general":          "General",
        "settings.tab.layouts":          "Layouts",
        "settings.tab.hotkey":           "Hotkey",
        "settings.tab.permissions":      "Permissions",
        "settings.tab.log":              "Log",
        "settings.iconStyle.languageBadge": "Language badge in frame (RU, EN)",
        "settings.iconStyle.keyboardIcon":  "Keyboard icon",

        // ── General Tab ─────────────────────────────────────────────
        "general.language":              "Language",
        "general.statusBarIcon":         "Menu Bar Icon",
        "general.launchAtLogin":         "Launch at Login",
        "general.playSound":             "Play Sound on Conversion",
        "general.showNotifications":     "Show Notifications",
        "general.smartConversion":       "Smart Conversion (No Selection)",
        "general.mode":                  "Mode:",
        "general.layoutSwitch":          "Layout Switch after Conversion",
        "general.howItWorks":            "How It Works",
        "general.howItWorksText":        "When text is selected, the shortcut converts the selection.\nWhen no text is selected, the behavior depends on the Smart Conversion mode above.",
        "general.statistics":            "Statistics",
        "general.totalConversions":      "Total Conversions:",

        // ── Smart Conversion Modes ──────────────────────────────────
        "smartMode.lastWord.name":       "Last Word Only",
        "smartMode.greedyLine.name":     "Greedy (Entire Phrase)",
        "smartMode.disabled.name":       "Disabled",
        "smartMode.lastWord.desc":       "Converts only the last typed word before the cursor.",
        "smartMode.greedyLine.desc":     "Selects text to the start of line, finds where the wrong layout begins, and converts the entire wrong-layout phrase.",
        "smartMode.disabled.desc":       "Smart conversion is off. You must manually select text before pressing the hotkey.",

        // ── Layout Switch Modes ─────────────────────────────────────
        "layoutSwitchMode.always.name":          "Always switch layout",
        "layoutSwitchMode.ifLastWord.name":      "Switch if last word was converted",
        "layoutSwitchMode.ifAnyWord.name":       "Switch if any word required conversion",
        "layoutSwitchMode.never.name":           "Do not switch layout",
        "layoutSwitchMode.always.desc":          "Always switch the keyboard layout after pressing the hotkey, regardless of whether text was converted.",
        "layoutSwitchMode.ifLastWord.desc":      "Switch the layout only if the last word before the cursor was typed in the wrong layout and got reconverted.",
        "layoutSwitchMode.ifAnyWord.desc":       "Switch the layout if any word in the converted text needed reconversion to the correct layout.",
        "layoutSwitchMode.never.desc":           "Convert text without changing the keyboard layout.",

        // ── Layouts Tab ─────────────────────────────────────────────
        "layouts.title":                 "Active Keyboard Layouts",
        "layouts.description":           "These layouts are detected from your system keyboard settings. The converter maps characters between them based on physical key positions.",
        "layouts.refresh":               "Refresh from System",
        "layouts.count":                 "%d layouts detected",

        // ── Single Key Layout Switching ──────────────────────────────
        "layoutSwitchKey.title":         "Keyboard Language Switch Key",
        "layoutSwitchKey.description":   "Quickly switch the system keyboard layout with a single key, without converting text.",
        "layoutSwitchKey.current":       "Switch key:",
        "layoutSwitchKey.disabled":      "Disabled",
        "layoutSwitchKey.capsLock":      "Caps Lock",
        "layoutSwitchKey.rightOption":   "Right Option (⌥)",
        "layoutSwitchKey.rightCommand":  "Right Command (⌘)",
        "layoutSwitchKey.rightShift":    "Right Shift (⇧)",
        "layoutSwitchKey.rightControl":  "Right Control (⌃)",
        "layoutSwitchKey.leftOption":    "Left Option (⌥)",
        "layoutSwitchKey.leftControl":   "Left Control (⌃)",
        "layoutSwitchKey.leftCommand":   "Left Command (⌘)",
        "layoutSwitchKey.leftShift":     "Left Shift (⇧)",
        "layoutSwitchKey.fn":            "Fn / Globe (fn)",
        "layoutSwitchKey.hint":          "Tap this key to cycle through enabled keyboard layouts. Fast and responsive, independent of text conversion.",

        // ── Hotkey Tab ──────────────────────────────────────────────
        "hotkey.title":                  "Keyboard Shortcut",
        "hotkey.description":            "Press this shortcut to convert text. If text is selected it converts the selection; otherwise it auto-selects the last word.",
        "hotkey.current":                "Current shortcut:",
        "hotkey.useDoubleShift":         "Use Double Shift (⇧⇧) as shortcut",
        "hotkey.doubleShiftHint":        "Quickly press Shift twice to trigger conversion. This is the recommended shortcut — fast and doesn't conflict with other apps.",
        "hotkey.customTitle":            "Custom Shortcut",

        // ── Hotkey Recorder ─────────────────────────────────────────
        "hotkeyRecorder.prompt":         "Click \"Record\" and press your desired shortcut:",
        "hotkeyRecorder.pressKey":       "Press a key combination...",
        "hotkeyRecorder.cancel":         "Cancel",
        "hotkeyRecorder.record":         "Record",

        // ── Permissions Tab ─────────────────────────────────────────
        "permissions.title":             "Permissions",
        "permissions.description":       "LangSwitcher needs Accessibility access to read and replace selected text in other applications.",
        "permissions.accessibilityTitle":"Accessibility Access",
        "permissions.granted":           "Granted — LangSwitcher can convert text",
        "permissions.notGranted":        "Not granted — Please enable in System Settings",
        "permissions.grantAccess":       "Grant Access",
        "permissions.howToEnable":       "How to enable:",
        "permissions.step1":             "1. Open System Settings > Privacy & Security > Accessibility",
        "permissions.step2":             "2. Click the lock icon to make changes",
        "permissions.step3":             "3. Enable LangSwitcher in the list",
        "permissions.step4":             "4. Restart LangSwitcher if needed",
        "permissions.openSettings":      "Open System Settings",
        "permissions.refreshStatus":     "Refresh Status",

        // ── Conversion Log Tab ──────────────────────────────────────
        "log.title":                     "Conversion Log",
        "log.entries":                   "%d entries",
        "log.exportJSON":                "Export JSON",
        "log.clearAll":                  "Clear All",
        "log.ratingHint":                "Rate each conversion as correct or incorrect to build training data. Click to cycle: unrated -> correct -> incorrect -> unrated.",
        "log.emptyTitle":                "No conversions logged yet.",
        "log.emptyHint":                 "Use the hotkey to convert text and entries will appear here.",
        "log.clearConfirmTitle":         "Clear All Logs?",
        "log.clearConfirmMessage":       "This will permanently delete all conversion log entries. This cannot be undone.",
        "log.cancel":                    "Cancel",
        "log.deleteEntry":               "Delete this entry",
        "log.exportPanelTitle":          "Export Conversion Log",
        "log.ratingUnrated":             "Unrated — click to mark as correct",
        "log.ratingCorrect":             "Correct — click to mark as incorrect",
        "log.ratingIncorrect":           "Incorrect — click to clear rating",

        // ── Logging Settings (General Tab) ─────────────────────────
        "general.logging":               "Conversion Logging",
        "general.loggingEnabled":        "Enable Conversion Logging",
        "general.loggingDisabledNote":   "Logging is disabled by default for your privacy. When enabled, conversions are stored locally on your Mac.",
        "general.logMaxEntries":         "Maximum Log Entries",
        "general.logUnlimited":          "0 = unlimited",

        // ── Logging Disabled (Log Tab) ─────────────────────────────
        "log.unlimited":                 "Unlimited",
        "log.disabledTitle":             "Logging is Disabled",
        "log.disabledHint":              "Enable logging above to start recording conversions.",

        // ── About Window ────────────────────────────────────────────
        "about.windowTitle":             "About LangSwitcher",
        "about.appName":                 "LangSwitcher",
        "about.version":                 "Version 1.3.0",
        "about.tagline":                 "Open-source keyboard layout text converter for macOS",
        "about.howToUse":                "How to use:",
        "about.step1":                   "Select text typed in wrong layout",
        "about.step2":                   "Press ⇧⇧ (double Shift)",
        "about.step3":                   "Text is automatically converted!",
        "about.github":                  "GitHub",
        "about.license":                 "MIT License",

        // ── Alerts (AppDelegate) ────────────────────────────────────
        "alert.accessibilityTitle":      "Accessibility Access Required",
        "alert.accessibilityMessage":    """
LangSwitcher needs Accessibility permission to read and replace text.

Go to System Settings → Privacy & Security → Accessibility and enable LangSwitcher.

If running from Xcode: add the built app from DerivedData or add Xcode itself.

If you already granted permission but it still doesn't work:
1. Remove LangSwitcher from the Accessibility list
2. Re-add it
3. Restart the app

Also check: Privacy & Security → Input Monitoring — LangSwitcher may need to be listed there too.
""",
        "alert.openSystemSettings":      "Open System Settings",
        "alert.continueAnyway":          "Continue Anyway",

        // ── Common ──────────────────────────────────────────────────
        "common.cancel":                 "Cancel",

        "menu.previewRecovery":          "Preview Recovery...",
        "general.autoCorrectOnSpace":      "Auto-correct on Space",
        "general.autoCorrectOnSpaceHint":  "Automatically convert the last word when Space is pressed if it looks like the wrong layout.",
        "general.thoughtRecovery":         "Thought Recovery",
        "general.thoughtRecoveryEnabled":  "Recover mixed-layout lines",
        "general.thoughtRecoveryPreview":  "Show preview before applying",
        "general.thoughtRecoveryHint":     "Rewrites only wrong-layout words inside mixed lines, leaving code, links and intentional English words untouched. Reverting in the preview teaches your personal dictionary.",
        "general.recoveryStats":           "Recoveries:",
        "general.recoveryRevertRate":      "reverted",
        "hotkey.doubleShiftMode":        "Double Shift (⇧⇧)",
        "hotkey.doubleOptionMode":       "Double Option (⌥⌥)",
        "hotkey.customMode":             "Custom Shortcut",
        "hotkey.doubleOptionHint":       "Quickly press Option twice to trigger conversion. Option+key shortcuts (⌥+key) are ignored and won't trigger conversion.",
        "permissions.inputMonitoringTitle":   "Input Monitoring",
        "permissions.inputMonitoringGranted": "Granted — conversion hotkeys work system-wide",
        "permissions.inputMonitoringNotGranted": "Not granted — hotkeys may not fire in other apps",
        "permissions.crossAppTitle":     "Current App",
        "permissions.crossAppFrontmost": "Frontmost app:",
        "permissions.crossAppFull":      "Conversion is expected to work in this app",
        "permissions.crossAppLimited":   "Conversion is known to be limited in this app (e.g. terminal) — verify the result",
        "recovery.title":                "Thought Recovery",
        "recovery.subtitle":             "Only the highlighted words will change.",
        "recovery.nothingToChange":      "Nothing to recover in this line — it already reads as natural text.",
        "recovery.original":             "Original",
        "recovery.reconstructed":        "Recovered",
        "recovery.alternatives":         "Other alternatives",
        "recovery.changedSpans":         "Changed words",
        "recovery.confidence":           "Confidence: %@",
        "recovery.apply":                "Apply",
        "recovery.copy":                 "Copy",
        "recovery.revert":               "Keep original",
        "recovery.revertHint":           "Keeping the original also teaches these words to your personal dictionary — they won't be rewritten again.",
        "recovery.kind.wrongLayout":     "wrong layout",
        "recovery.kind.intentionalForeign": "foreign word",
        "recovery.kind.code":            "code",
        "recovery.kind.url":             "link",
        "recovery.kind.properName":      "name",
        "recovery.kind.ambiguous":       "ambiguous",
        "recovery.kind.correct":         "correct",
        "recovery.kind.separator":       "separator",

        "notification.layoutSwitched":   "Layout: %@",

        // ── Auto-Correction ────────────────────────────────────────
        "general.autoCorrection":                "Auto-Correction",
        "general.autoCorrectionEnabled":         "Auto-correct wrong layout on Space/Enter",
        "general.autoCorrectionDesc":            "Automatically detects and corrects words typed in the wrong keyboard layout when you press Space, Enter, or punctuation. Uses system spell checker to reduce false positives.",
        "general.autoCorrectionSpellCheck":      "Validate with system spell checker",
        "general.autoCorrectionSpellCheckDesc":  "Only auto-correct when the converted word is recognized by macOS spell checker. Reduces false positives but may miss some valid words.",
        "general.autoCorrectionSwitchLayout":    "Switch layout after auto-correction",
        "general.autoCorrectionSwitchLayoutDesc": "Automatically switch system keyboard layout to match the corrected text language.",

        // ── Autocompletion ──────────────────────────────────────────
        "general.autocompletion":                "Word Autocompletion",
        "autocompletion.enabled":                "Show word suggestions while typing",
        "autocompletion.desc":                   "Displays floating suggestions near the caret as you type. Suggests words in active and cross-layout languages.",
        "autocompletion.acceptKey":              "Accept next word key",
        "autocompletion.acceptKey.tab":          "Tab (⇥)",
        "autocompletion.acceptKey.space":        "Space (␣)",
        "autocompletion.acceptKey.enter":        "Enter (↩)",
        "autocompletion.acceptKey.rightArrow":   "Right Arrow (→)",
        "autocompletion.acceptKey.custom":       "Custom Key",
        "autocompletion.acceptAllKey":           "Accept entire phrase key",
        "autocompletion.acceptAllKey.shiftTab":   "Shift + Tab (⇧⇥)",
        "autocompletion.acceptAllKey.cmdReturn":  "Cmd + Enter (⌘↩)",
        "autocompletion.acceptAllKey.optionTab":  "Option + Tab (⌥⇥)",
        "autocompletion.acceptAllKey.custom":    "Custom Key",
        "autocompletion.customKey":              "Custom key:",
        "autocompletion.recordKey":              "Press a key...",
        "autocompletion.changeKey":              "Change",
        "autocompletion.useNumberShortcuts":     "Select with number keys (1–5)",
        "autocompletion.includeCrossLayout":     "Include cross-layout suggestions",
        "autocompletion.crossLayoutDesc":        "e.g. typing 'ghbd' suggests 'привет' and automatically switches layout.",
        "autocompletion.maxSuggestions":         "Max suggestions:",
        "autocompletion.minPrefixLength":        "Min prefix length:",
        "autocompletion.hint.toAccept":          "to insert",
        "autocompletion.displayMode":            "Display style",
        "autocompletion.displayMode.popup":      "Popup Menu",
        "autocompletion.displayMode.ghostText":  "Inline Ghost Text",
        "autocompletion.displayMode.both":       "Both (Popup + Ghost Text)",
        "autocompletion.displayModeDesc.popup":     "Shows a floating list of suggestion candidates below the cursor.",
        "autocompletion.displayModeDesc.ghostText": "Displays a subtle inline completion tail directly at the cursor.",
        "autocompletion.displayModeDesc.both":      "Shows inline ghost text tail with a floating list of alternatives.",
        "autocompletion.resetAdaptive":          "Reset Learned Vocabulary",
        "autocompletion.adaptiveResetDone":      "Vocabulary reset successfully.",

        // ── Excluded Apps ────────────────────────────────────────────
        "excludedApps.title":                    "Excluded Applications",
        "excludedApps.desc":                     "Auto-correction and autocompletion will be disabled in these applications.",
        "excludedApps.empty":                    "No excluded applications. Add apps where you want typing assistants disabled.",
        "excludedApps.addRunning":               "Add Running App...",
        "excludedApps.chooseFromDisk":           "Choose from Disk...",
        "permissions.serviceTitle": "Auto-correction service",
        "permissions.service.disabled": "Disabled in settings",
        "permissions.service.permissionRequired": "Accessibility permission required",
        "permissions.service.running": "Keyboard monitoring is active",
        "permissions.service.failed": "Could not start monitoring; retrying automatically",
        "permissions.serviceDetail": "Checks permission and monitoring every 5 seconds and after wake. Active monitoring does not mean every word will be corrected.",
        "permissions.restartService": "Restart service",
        "permissions.copiesTitle": "Application copies",
        "permissions.copiesDetail": "Copies known to macOS are listed below. Only one copy can run per user. Accessibility applies to the current copy; macOS does not expose other copies’ permission status here. Keep the installed app in /Applications; remove unwanted copies using Finder.",
        "permissions.currentCopy": "Current copy",
        "permissions.otherCopy": "Other copy",
        "permissions.revealCopy": "Show in Finder",
        "permissions.instanceError": "Could not protect against duplicate launch",
        "permissions.instanceErrorDetail": "LangSwitcher will quit to avoid running multiple keyboard monitors. Check access to its Application Support folder.",
    ]

    @MainActor static func register() {
        LocalizationManager.shared.register(language: "en", strings: strings)
    }
}
