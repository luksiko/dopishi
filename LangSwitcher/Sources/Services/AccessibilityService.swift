import Foundation
import AppKit
import ApplicationServices

// MARK: - Caret Context
// Represents the surrounding text and cursor state in the active text field.

struct CaretContext: Equatable {
    let fieldIdentifier: String
    let textBeforeCaret: String
    let textAfterCaret: String
    let selectedText: String
    let caretLocation: Int
    let fullTextLength: Int

    var hasUsablePredictionContext: Bool {
        fullTextLength > 0 && caretLocation > 0 && selectedText.isEmpty
            && !textBeforeCaret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Accessibility Service
// Handles getting and replacing selected text via macOS Accessibility API & pasteboard

final class AccessibilityService {
    let extractionCache = ExtractionCacheManager()
    private let electronPIDLock = NSLock()
    private var preparedElectronPIDs = Set<pid_t>()

    func isElectronOrChromiumApp(pid: pid_t) -> Bool {
        electronPIDLock.lock()
        defer { electronPIDLock.unlock() }
        return preparedElectronPIDs.contains(pid)
    }
    private var pendingPaste: PasteConfirmation?
    private var pendingSelection: PasteConfirmation?
    private var workspaceObserver: NSObjectProtocol?

    func recordKeystroke(_ characters: String, time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        extractionCache.advance(characters: characters, time: time)
    }

    func invalidateExtractionCache(reason: CursorRetryPlan.InvalidationReason) {
        extractionCache.invalidate(reason: reason)
    }

    init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                ?? NSWorkspace.shared.frontmostApplication
            guard let app else { return }
            self?.prepareBrowserAccessibilityAsync(for: app)
            self?.extractionCache.invalidate(reason: .focusChanged)
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            prepareBrowserAccessibilityAsync(for: frontmost)
        }
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var hasPendingPaste: Bool {
        pendingPaste != nil
    }

    func finalizePendingPaste() {
        pendingSelection?.cancel()
        pendingPaste?.check(final: true)
    }

    func confirmPendingPasteBeforeInput() {
        pendingSelection?.cancel()
        pendingPaste?.check()
    }

    func cancelPendingReplacement() {
        pendingSelection?.cancel()
        pendingPaste?.check(final: true)
    }


    /// Check if the app has accessibility permissions
    static var hasAccessibilityPermission: Bool {
        let trusted = AXIsProcessTrusted()
        NSLog("[LangSwitcher] AXIsProcessTrusted() = \(trusted), bundle = \(Bundle.main.bundlePath)")
        return trusted
    }

    /// Request accessibility permissions (opens System Preferences)
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        NSLog("[LangSwitcher] AXIsProcessTrustedWithOptions(prompt=true) = \(result)")
    }

    /// Opens macOS System Settings directly to Privacy & Security > Accessibility
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Selected Text Conversion

    /// Get selected text and replace it using clipboard-based approach.
    /// Returns false if no text was selected/copied.
    func getAndReplaceSelectedText(with converter: (String) -> String?) -> Bool {
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard()

        // Copy selected text (try native AX menu action first, fallback to ⌘C)
        pasteboard.clearContents()
        performCopy()
        usleep(150_000) // 150ms — give target app time to process copy

        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.isEmpty else {
            NSLog("[LangSwitcher] getAndReplaceSelectedText: no text on clipboard after ⌘C")
            restorePasteboard(savedContents)
            return false
        }

        NSLog("[LangSwitcher] getAndReplaceSelectedText: copied text = '\(selectedText)'")

        guard let convertedText = converter(selectedText) else {
            NSLog("[LangSwitcher] getAndReplaceSelectedText: converter returned nil")
            restorePasteboard(savedContents)
            return false
        }

        NSLog("[LangSwitcher] getAndReplaceSelectedText: pasting converted text = '\(convertedText)'")

        // Paste converted text
        TransientPasteboard.writeString(convertedText)
        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.restorePasteboard(savedContents)
        }

        return true
    }

    // MARK: - Smart Selection (Greedy Line)

    /// Select from cursor to start of line (⌘⇧←), copy, pass to converter,
    /// paste the result back. The converter is responsible for determining
    /// which portion to convert and returning the full replacement text.
    func selectLineAndReplace(with converter: (String) -> String?) -> Bool {
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard()

        NSLog("[LangSwitcher] selectLineAndReplace: selecting to line start (⌘⇧←)...")

        // Select from cursor to beginning of line: Cmd+Shift+Left
        simulateSelectToLineStart()
        usleep(150_000) // 150ms

        // Copy the selection (native AX menu copy first, fallback to ⌘C)
        pasteboard.clearContents()
        performCopy()
        usleep(150_000) // 150ms

        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.isEmpty else {
            NSLog("[LangSwitcher] selectLineAndReplace: no text copied, deselecting")
            simulateRightArrow()
            restorePasteboard(savedContents)
            return false
        }

        NSLog("[LangSwitcher] selectLineAndReplace: copied line = '\(selectedText)' (len=\(selectedText.count))")

        guard let convertedText = converter(selectedText) else {
            NSLog("[LangSwitcher] selectLineAndReplace: converter returned nil, deselecting")
            simulateRightArrow()
            restorePasteboard(savedContents)
            return false
        }

        NSLog("[LangSwitcher] selectLineAndReplace: pasting = '\(convertedText)'")

        // Paste (replaces the entire selection from cursor to line start)
        TransientPasteboard.writeString(convertedText)
        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.restorePasteboard(savedContents)
        }

        return true
    }

    // MARK: - Smart Selection (Last Word)

    /// When no text is selected, select the last typed word/chunk via
    /// Option+Shift+Left (select word left), copy it, convert, paste back.
    /// This selects the word just before the cursor.
    func selectAndReplaceLastWord(with converter: (String) -> String?) -> Bool {
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard()

        NSLog("[LangSwitcher] selectAndReplaceLastWord: selecting word left...")

        // First, try selecting last word: Shift+Option+Left arrow selects one word left
        simulateSelectWordLeft()
        usleep(150_000) // 150ms — give target app time to process selection

        // Copy the selection (native AX menu copy first, fallback to ⌘C)
        pasteboard.clearContents()
        performCopy()
        usleep(150_000) // 150ms — give target app time to process ⌘C

        var selectedText = pasteboard.string(forType: .string) ?? ""
        if !selectedText.isEmpty && selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Only whitespace was selected (user had typed a trailing space). Extend selection one more word left!
            NSLog("[LangSwitcher] selectAndReplaceLastWord: only whitespace selected, extending selection left...")
            simulateSelectWordLeft()
            usleep(150_000)
            pasteboard.clearContents()
            performCopy()
            usleep(150_000)
            selectedText = pasteboard.string(forType: .string) ?? ""
        }

        guard !selectedText.isEmpty else {
            NSLog("[LangSwitcher] selectAndReplaceLastWord: no text copied after selection+copy, deselecting")
            simulateRightArrow()
            restorePasteboard(savedContents)
            return false
        }

        NSLog("[LangSwitcher] selectAndReplaceLastWord: copied word = '\(selectedText)'")

        guard let convertedText = converter(selectedText) else {
            NSLog("[LangSwitcher] selectAndReplaceLastWord: converter returned nil, deselecting")
            // No conversion needed — deselect by pressing Right arrow
            simulateRightArrow()
            restorePasteboard(savedContents)
            return false
        }

        NSLog("[LangSwitcher] selectAndReplaceLastWord: pasting converted = '\(convertedText)'")

        // Paste converted text (replaces the selection)
        TransientPasteboard.writeString(convertedText)
        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.restorePasteboard(savedContents)
        }

        return true
    }

    // MARK: - Keyboard Simulation

    /// Helper: post a key event with modifiers.
    /// Uses .hidSystemState to avoid interference with current keyboard state
    /// (e.g., if Shift is still physically held from double-shift trigger).
    private func postKeyEvent(virtualKey: CGKeyCode, keyDown: Bool, modifiers: CGEventFlags = []) {
        // Use .hidSystemState instead of .combinedSessionState to create events
        // independent of the current modifier state (avoids Shift bleed from double-tap)
        let source = CGEventSource(stateID: .hidSystemState)

        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            NSLog("[LangSwitcher] ERROR: Failed to create CGEvent (key=\(virtualKey), down=\(keyDown))")
            return
        }

        // Set flags explicitly — this overrides any current keyboard state
        event.flags = modifiers
        event.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
        event.post(tap: .cgAnnotatedSessionEventTap)

        NSLog("[LangSwitcher] Posted key event: key=0x\(String(virtualKey, radix: 16)), down=\(keyDown), mods=\(modifiers.rawValue)")
    }

    /// Simulate a full keystroke (key down + key up) with modifiers
    private func simulateKeystroke(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
        postKeyEvent(virtualKey: virtualKey, keyDown: true, modifiers: modifiers)
        postKeyEvent(virtualKey: virtualKey, keyDown: false, modifiers: modifiers)
    }

    /// Types text directly into the focused field using synthetic Unicode CGEvent keystrokes.
    /// This bypasses the clipboard completely, making it ideal for terminals (Terminal, iTerm2),
    /// password/secure inputs, or environments where clipboard paste is prohibited or desynchronized.
    func typeTextDirectly(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let characters = Array(text)
        var charIndex = 0

        // Chunk into slices of up to 16 UTF-16 code units (safely below macOS CGEvent limit).
        // Extended grapheme clusters (Characters) are kept intact to prevent splitting surrogate pairs.
        while charIndex < characters.count {
            var chunkString = ""
            while charIndex < characters.count {
                let nextCount = chunkString.utf16.count + characters[charIndex].utf16.count
                if nextCount > 16 && !chunkString.isEmpty {
                    break
                }
                chunkString.append(characters[charIndex])
                charIndex += 1
            }
            var chunk = Array(chunkString.utf16)

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)

            for event in [keyDown, keyUp] {
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                event.post(tap: .cgAnnotatedSessionEventTap)
            }
        }
    }

    /// Attempts to trigger Copy via native AX menu action first; falls back to synthetic ⌘C.
    private func performCopy() {
        if pressCopyMenuItem() {
            NSLog("[LangSwitcher] performCopy: successfully executed native AX copy menu action")
        } else {
            simulateCopy()
        }
    }

    /// Triggers the frontmost application's "Edit -> Copy" menu item action via Accessibility API.
    /// This bypasses synthetic keyboard simulation, avoiding modifier collisions and layout-dependent keys.
    func pressCopyMenuItem() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        return Self.pressCopyMenuItem(in: AXUIElementCreateApplication(frontApp.processIdentifier))
    }

    /// Internal search for Edit -> Copy menu item in the given application element.
    static func pressCopyMenuItem(in appElement: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(appElement, 0.05)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            return false
        }

        var menuBarItemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &menuBarItemsRef) == .success,
              let menuBarItems = menuBarItemsRef as? [AXUIElement] else {
            return false
        }

        // Scan menus (Edit is typically among the first 8 menus)
        for menuBarItem in menuBarItems.prefix(8) {
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menuBarItem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                  let menus = childrenRef as? [AXUIElement] else {
                continue
            }

            for menu in menus {
                var itemsRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(menu, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                      let items = itemsRef as? [AXUIElement] else {
                    continue
                }

                for item in items {
                    // Check cmd key shortcut (Cmd+C)
                    var cmdCharRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(item, "AXMenuItemCmdChar" as CFString, &cmdCharRef) == .success,
                       let cmdChar = cmdCharRef as? String, cmdChar.lowercased() == "c" {
                        var enabledRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabledRef) == .success,
                           let isEnabled = enabledRef as? Bool, !isEnabled {
                            // Copy menu is present but disabled -> nothing selected
                            return false
                        }
                        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                    }

                    // Fallback: check localized title
                    var titleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success,
                       let title = (titleRef as? String)?.lowercased() {
                        if title == "copy" || title == "копировать" || title == "скопировать" ||
                           title == "copier" || title == "kopieren" || title == "copiar" {
                            var enabledRef: CFTypeRef?
                            if AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabledRef) == .success,
                               let isEnabled = enabledRef as? Bool, !isEnabled {
                                return false
                            }
                            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                        }
                    }
                }
            }
        }

        return false
    }

    private func simulateCopy() {
        NSLog("[LangSwitcher] Simulating ⌘C...")
        simulateKeystroke(virtualKey: 0x08, modifiers: .maskCommand) // C key
    }

    private func simulatePaste() {
        NSLog("[LangSwitcher] Simulating ⌘V...")
        simulateKeystroke(virtualKey: 0x09, modifiers: .maskCommand) // V key
    }

    /// Simulate Cmd+Shift+Left to select from cursor to start of line
    private func simulateSelectToLineStart() {
        NSLog("[LangSwitcher] Simulating ⌘⇧←...")
        simulateKeystroke(virtualKey: 0x7B, modifiers: [.maskShift, .maskCommand]) // Left arrow + Cmd+Shift
    }

    /// Simulate Shift+Option+Left to select one word to the left
    private func simulateSelectWordLeft() {
        NSLog("[LangSwitcher] Simulating ⇧⌥←...")
        simulateKeystroke(virtualKey: 0x7B, modifiers: [.maskShift, .maskAlternate]) // Left arrow
    }

    /// Simulate Right arrow to deselect (move cursor to end of selection)
    private func simulateRightArrow() {
        NSLog("[LangSwitcher] Simulating →...")
        simulateKeystroke(virtualKey: 0x7C) // Right arrow, no modifiers
    }

    // MARK: - Thought Recovery Preview

    /// Select from the cursor to the start of the line and copy it, but keep
    /// the selection active instead of pasting. Used by the recovery preview,
    /// which decides what to paste while the user looks at the options. The
    /// caller must put the target app back in front before pasting or
    /// deselecting (the selection survives the app losing focus).
    func selectLineKeepingSelection() -> String? {
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard()

        NSLog("[LangSwitcher] selectLineKeepingSelection: selecting to line start...")
        simulateSelectToLineStart()
        usleep(150_000)

        pasteboard.clearContents()
        performCopy()
        usleep(150_000)

        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.isEmpty else {
            NSLog("[LangSwitcher] selectLineKeepingSelection: no text copied, deselecting")
            simulateRightArrow()
            restorePasteboard(savedContents)
            return nil
        }

        NSLog("[LangSwitcher] selectLineKeepingSelection: copied '\(selectedText)'")
        restorePasteboard(savedContents)
        return selectedText
    }

    /// Paste `text` into the focused app, replacing the active selection.
    /// The caller is responsible for bringing the target app to the front.
    func pasteReplacingSelection(_ text: String) {
        TransientPasteboard.writeString(text)
        NSLog("[LangSwitcher] pasteReplacingSelection: '\(text)'")
        simulatePaste()
    }

    struct PreparedReplacement: Equatable {
        let text: String
        let prependLeadingSpace: Bool
        let appendTrailingSpace: Bool
    }

    /// Prepares replacement text for clipboard paste. Modern macOS apps (browsers, Electron, Qt,
    /// messaging apps) strip trailing ASCII whitespace on pasteboard import, causing concatenated
    /// words ("семейныйдоступ") when replacing words triggered by space. Additionally, Microsoft Office
    /// ("Smart Cut and Paste") strips both leading and trailing boundary spaces.
    /// Trailing space is always typed via synthetic space keystrokes; leading space is stripped and typed for smart-paste apps.
    static func prepareClipboardReplacement(for replacement: String, bundleID: String?) -> PreparedReplacement {
        let isSmartPasteApp = Self.isSmartPasteApp(bundleID: bundleID)
        let hasLeadingSpace = isSmartPasteApp && replacement.hasPrefix(" ")
        let hasTrailingSpace = replacement.hasSuffix(" ")

        var clipboardReplacement = replacement
        if hasLeadingSpace { clipboardReplacement = String(clipboardReplacement.dropFirst()) }
        if hasTrailingSpace && clipboardReplacement.hasSuffix(" ") { clipboardReplacement = String(clipboardReplacement.dropLast()) }

        return PreparedReplacement(
            text: clipboardReplacement,
            prependLeadingSpace: hasLeadingSpace,
            appendTrailingSpace: hasTrailingSpace
        )
    }

    /// Replaces trailing text using synthetic Backspace strokes followed by clipboard paste.
    /// Used as a universal hardware-level fallback when Accessibility API cannot manipulate selection directly
    /// (e.g. Electron apps, Chromium contenteditable web inputs, chat boxes).
    func replaceWithBackspaces(count: Int, replacement: String, completion: ((Bool) -> Void)? = nil) {
        guard count > 0, !replacement.isEmpty else {
            completion?(false)
            return
        }

        let appBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let prepared = Self.prepareClipboardReplacement(for: replacement, bundleID: appBundleID)

        let pasteboard = NSPasteboard.general
        let savedContents = TransientPasteboard.snapshot(pasteboard: pasteboard)
        let revision = TransientPasteboard.writeString(prepared.text, pasteboard: pasteboard)

        for _ in 0..<count {
            simulateKeystroke(virtualKey: 0x33) // Backspace key
        }

        let delay = max(0.045, Double(count) * 0.008 + 0.02)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { completion?(false); return }
            if prepared.prependLeadingSpace {
                self.simulateKeystroke(virtualKey: 0x31)
            }
            self.simulatePaste()
            if prepared.appendTrailingSpace {
                self.simulateKeystroke(virtualKey: 0x31) // Space key
            }
            completion?(true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if pasteboard.changeCount == revision {
                    TransientPasteboard.restore(savedContents, pasteboard: pasteboard)
                }
            }
        }
    }

    /// Checks if the expected text suffix in the target element is immediately preceded by a word character
    /// (letter or number), which indicates that `expected` is only a partial tail of a larger word.
    func isTailOfLargerWord(expected: String, target: ReplacementTarget) -> Bool {
        guard isCurrentReplacementTarget(target) else { return false }
        var value: CFTypeRef?
        var selectionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, &selectionValue) == .success,
              let selectionValue, CFGetTypeID(selectionValue) == AXValueGetTypeID() else { return false }
        var selection = CFRange()
        guard AXValueGetValue(selectionValue as! AXValue, .cfRange, &selection) else { return false }
        return Self.isTailOfLargerWord(text: text, selection: selection, expected: expected)
    }

    static func isTailOfLargerWord(text: String, selection: CFRange, expected: String) -> Bool {
        let string = text as NSString
        let loc = selection.location

        let count = expected.utf16.count
        if count > 0, loc >= count, loc <= string.length {
            let range = NSRange(location: loc - count, length: count)
            if string.substring(with: range) == expected {
                if range.location > 0,
                   let preceding = (string.substring(to: range.location)).last,
                   preceding.isLetter || preceding.isNumber {
                    return true
                }
                return false
            }
        }

        // Also check if editor has word without trailing delimiter (e.g. space was not yet committed)
        if expected.hasSuffix(" ") || expected.hasSuffix("\n") {
            let trimmed = String(expected.dropLast())
            let trimmedCount = trimmed.utf16.count
            if trimmedCount > 0, loc >= trimmedCount, loc <= string.length {
                let range = NSRange(location: loc - trimmedCount, length: trimmedCount)
                if string.substring(with: range) == trimmed {
                    if range.location > 0,
                       let preceding = (string.substring(to: range.location)).last,
                       preceding.isLetter || preceding.isNumber {
                        return true
                    }
                    return false
                }
            }
        }

        return false
    }

    /// Determines the exact number of backspaces needed to delete `expected` text before the caret.
    /// If the editor has already committed the trailing delimiter (e.g. space), returns `expected.count`.
    /// If the editor only has the word without the trailing delimiter (e.g. space was not committed or delayed),
    /// returns the word count (`expected.count - 1`), preventing deletion of the character preceding the word.
    /// Returns nil if the editor text matches neither `expected` nor `trimmedExpected`.
    func effectiveBackspaceCount(expected: String, target: ReplacementTarget) -> Int? {
        guard isCurrentReplacementTarget(target) else { return expected.count }
        var value: CFTypeRef?
        var selectionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target.element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, &selectionValue) == .success,
              let selectionValue, CFGetTypeID(selectionValue) == AXValueGetTypeID() else {
            return expected.count
        }
        var selection = CFRange()
        guard AXValueGetValue(selectionValue as! AXValue, .cfRange, &selection) else { return expected.count }
        return Self.effectiveBackspaceCount(text: text, selection: selection, expected: expected)
    }

    static func effectiveBackspaceCount(text: String, selection: CFRange, expected: String) -> Int? {
        let string = text as NSString
        let loc = selection.location

        let fullCount = expected.utf16.count
        if fullCount > 0, loc >= fullCount, loc <= string.length {
            let fullRange = NSRange(location: loc - fullCount, length: fullCount)
            if string.substring(with: fullRange) == expected {
                return expected.count
            }
        }

        // Check if the editor has the word without trailing delimiter
        if expected.hasSuffix(" ") || expected.hasSuffix("\n") {
            let trimmed = String(expected.dropLast())
            let trimmedCount = trimmed.utf16.count
            if trimmedCount > 0, loc >= trimmedCount, loc <= string.length {
                let trimmedRange = NSRange(location: loc - trimmedCount, length: trimmedCount)
                if string.substring(with: trimmedRange) == trimmed {
                    NSLog("[LangSwitcher] effectiveBackspaceCount: editor has '\(trimmed)' without trailing delimiter, adjusting backspaces from \(expected.count) to \(trimmed.count)")
                    return trimmed.count
                }
            }
        }

        return nil
    }

    /// Copy text to the clipboard without touching any app.
    func copyToPasteboard(_ text: String) {
        TransientPasteboard.writeString(text)
    }

    /// Collapse the still-active selection (right arrow) after the user
    /// cancelled the preview.
    func collapseSelection() {
        simulateRightArrow()
    }

    // MARK: - Focused Field Inspection

    /// Role/subrole of the currently focused UI element, or nil when it
    /// cannot be determined (no AX permission, non-standard UI).
    /// Thin AX glue — policy lives in AutoCorrectionGate; callers fail
    /// closed on nil.
    func focusedFieldRole() -> (role: String?, subrole: String?)? {
        let axElement: AXUIElement
        if let element = focusedTextElement() {
            axElement = element
        } else {
            let system = AXUIElementCreateSystemWide()
            var directValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &directValue) != .success,
               let app = NSWorkspace.shared.frontmostApplication {
                AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                              kAXFocusedUIElementAttribute as CFString, &directValue)
            }
            guard let directValue, CFGetTypeID(directValue) == AXUIElementGetTypeID() else {
                NSLog("[LangSwitcher] focusedFieldRole: no confirmed text editor")
                return nil
            }
            axElement = directValue as! AXUIElement
        }
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue)
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleValue)

        let role = roleValue as? String
        let subrole = subroleValue as? String
        NSLog("[LangSwitcher] focusedFieldRole: role='\(role ?? "nil")' subrole='\(subrole ?? "nil")'")
        return (role, subrole)
    }

    // MARK: - Caret Context Inspection

    // MARK: WebKit AXTextMarker Dynamic Bindings
    private typealias AXTextMarkerRangeCopyMarkerFunc = @convention(c) (CFTypeRef) -> CFTypeRef?
    private typealias AXTextMarkerRangeCreateFunc = @convention(c) (CFAllocator?, CFTypeRef, CFTypeRef) -> CFTypeRef?

    private static let copyStartMarkerFn: AXTextMarkerRangeCopyMarkerFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "AXTextMarkerRangeCopyStartMarker") else { return nil }
        return unsafeBitCast(sym, to: AXTextMarkerRangeCopyMarkerFunc.self)
    }()

    private static let copyEndMarkerFn: AXTextMarkerRangeCopyMarkerFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "AXTextMarkerRangeCopyEndMarker") else { return nil }
        return unsafeBitCast(sym, to: AXTextMarkerRangeCopyMarkerFunc.self)
    }()

    private static let createRangeFn: AXTextMarkerRangeCreateFunc? = {
        guard let handle = dlopen(nil, RTLD_NOW) else { return nil }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "AXTextMarkerRangeCreate") else { return nil }
        return unsafeBitCast(sym, to: AXTextMarkerRangeCreateFunc.self)
    }()

    private func copyStartMarker(from range: CFTypeRef, element: AXUIElement) -> CFTypeRef? {
        if let fn = Self.copyStartMarkerFn, let marker = fn(range) {
            return marker
        }
        var startRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, "AXStartTextMarkerForTextMarkerRange" as CFString, range, &startRef) == .success {
            return startRef
        }
        return nil
    }

    private func copyEndMarker(from range: CFTypeRef, element: AXUIElement) -> CFTypeRef? {
        if let fn = Self.copyEndMarkerFn, let marker = fn(range) {
            return marker
        }
        var endRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, "AXEndTextMarkerForTextMarkerRange" as CFString, range, &endRef) == .success {
            return endRef
        }
        return nil
    }

    private func createMarkerRange(start: CFTypeRef, end: CFTypeRef, element: AXUIElement) -> CFTypeRef? {
        if let fn = Self.createRangeFn, let range = fn(kCFAllocatorDefault, start, end) {
            return range
        }
        var rangeRef: CFTypeRef?
        let pair = [start, end] as CFArray
        if AXUIElementCopyParameterizedAttributeValue(element, "AXTextMarkerRangeForUnorderedTextMarkers" as CFString, pair, &rangeRef) == .success {
            return rangeRef
        }
        return nil
    }

    /// WebKit / Safari / Apple Mail / Google Docs context extraction using AXTextMarker and AXTextMarkerRange.
    /// Used when standard kAXSelectedTextRangeAttribute is unsupported or omitted by the web engine.
    func captureWebKitMarkerCaretContext(element: AXUIElement, fieldIdentifier: String, maxSurroundingLength: Int = 200) -> CaretContext? {
        var selectedMarkerRangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &selectedMarkerRangeRef) == .success,
              let selectedMarkerRange = selectedMarkerRangeRef else { return nil }

        var selectedTextRef: CFTypeRef?
        var selectedText = ""
        if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, selectedMarkerRange, &selectedTextRef) == .success,
           let str = selectedTextRef as? String {
            selectedText = str
        }

        guard let caretStartMarker = copyStartMarker(from: selectedMarkerRange, element: element),
              let caretEndMarker = copyEndMarker(from: selectedMarkerRange, element: element) else { return nil }

        // Scope bounds: Attempt paragraph first, then line, then full element boundaries
        var scopeStartMarker: CFTypeRef?
        var scopeEndMarker: CFTypeRef?

        var scopeRangeRef: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, "AXParagraphTextMarkerRangeForTextMarker" as CFString, selectedMarkerRange, &scopeRangeRef) == .success,
           let scopeRange = scopeRangeRef {
            scopeStartMarker = copyStartMarker(from: scopeRange, element: element)
            scopeEndMarker = copyEndMarker(from: scopeRange, element: element)
        }

        if scopeStartMarker == nil {
            if AXUIElementCopyParameterizedAttributeValue(element, "AXLineTextMarkerRangeForTextMarker" as CFString, selectedMarkerRange, &scopeRangeRef) == .success,
               let scopeRange = scopeRangeRef {
                scopeStartMarker = copyStartMarker(from: scopeRange, element: element)
                scopeEndMarker = copyEndMarker(from: scopeRange, element: element)
            }
        }

        if scopeStartMarker == nil {
            var docStartRef: CFTypeRef?
            var docEndRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, "AXStartTextMarker" as CFString, &docStartRef)
            AXUIElementCopyAttributeValue(element, "AXEndTextMarker" as CFString, &docEndRef)
            scopeStartMarker = docStartRef
            scopeEndMarker = docEndRef
        }

        var textBefore = ""
        if let start = scopeStartMarker,
           let rangeBefore = createMarkerRange(start: start, end: caretStartMarker, element: element) {
            var strRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, rangeBefore, &strRef) == .success,
               let str = strRef as? String {
                textBefore = str
            }
        }

        var textAfter = ""
        if let end = scopeEndMarker,
           let rangeAfter = createMarkerRange(start: caretEndMarker, end: end, element: element) {
            var strRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, rangeAfter, &strRef) == .success,
               let str = strRef as? String {
                textAfter = str
            }
        }

        if textBefore.count > maxSurroundingLength {
            textBefore = String(textBefore.suffix(maxSurroundingLength))
        }
        if textAfter.count > maxSurroundingLength {
            textAfter = String(textAfter.prefix(maxSurroundingLength))
        }

        return CaretContext(
            fieldIdentifier: fieldIdentifier,
            textBeforeCaret: textBefore,
            textAfterCaret: textAfter,
            selectedText: selectedText,
            caretLocation: textBefore.utf16.count,
            fullTextLength: textBefore.utf16.count + selectedText.utf16.count + textAfter.utf16.count
        )
    }

    /// Fast, lightweight identifier for currently focused text element.
    func focusedFieldIdentifier() -> String? {
        guard let element = focusedTextElement(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier ?? "unknown"
        let pid = app.processIdentifier
        let elementHash = CFHash(element)
        return "\(bundleID):\(pid):\(elementHash)"
    }

    /// Returns the frontmost app name, bundle identifier, and focused window title.
    /// Fast query (<0.1ms) used to ground AI completion prompts in application context.
    func activeWindowContext() -> (appName: String?, bundleID: String?, windowTitle: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return (nil, nil, nil) }
        let appName = app.localizedName
        let bundleID = app.bundleIdentifier

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        var windowTitle: String?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID() {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let str = titleRef as? String {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !AutoCorrectionGate.containsSensitiveInformation(trimmed) {
                    windowTitle = String(trimmed.prefix(120))
                }
            }
        }
        return (appName, bundleID, windowTitle)
    }

    /// Captures the surrounding text before/after caret and identifies the focused field.
    /// When `preferCache` is true and valid typing prediction is cached, returns it with 0 AX IPC latency.
    func captureCaretContext(maxSurroundingLength: Int = 200, preferCache: Bool = false) -> CaretContext? {
        let uptime = ProcessInfo.processInfo.systemUptime
        if preferCache, let cached = extractionCache.getCachedContext(currentTime: uptime), !cached.textBeforeCaret.isEmpty {
            return cached
        }

        guard let element = focusedTextElement(),
              let app = NSWorkspace.shared.frontmostApplication else {
            extractionCache.recordFailure()
            return nil
        }

        let bundleID = app.bundleIdentifier ?? "unknown"
        let pid = app.processIdentifier
        let elementHash = CFHash(element)
        let fieldID = "\(bundleID):\(pid):\(elementHash)"

        // Terminal support: com.apple.Terminal (terminalLastPage) and xtermScreen (iTerm2, Ghostty, Alacritty, Warp)
        if AutoCorrectionGate.isTerminalApp(bundleID: bundleID) {
            let approach: TextExtractionApproach = (bundleID == "com.apple.Terminal") ? .terminalLastPage : .xtermScreen
            if let (termCtx, parsed) = captureTerminalCaretContext(element: element, bundleID: bundleID, approach: approach, maxSurroundingLength: maxSurroundingLength) {
                let bounds = resolveTerminalCaretBounds(element: element, bundleID: bundleID, approach: approach, promptText: termCtx.textBeforeCaret, parsedResult: parsed)
                extractionCache.update(
                    context: termCtx,
                    bundleID: bundleID,
                    elementHash: elementHash,
                    approach: approach,
                    caretRect: bounds?.caret,
                    fieldRect: bounds?.fieldRect,
                    estimatedCharWidth: 8.5,
                    time: uptime
                )
                return termCtx
            }
        }

        var rangeRef: CFTypeRef?
        var selectedRange = CFRange(location: 0, length: 0)
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID(),
           AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange),
           selectedRange.location >= 0, selectedRange.length >= 0 {
            var selectedTextRef: CFTypeRef?
            var selectedText = ""
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
               let str = selectedTextRef as? String {
                selectedText = str
            }

            var valueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
               let fullText = (valueRef as? String) ?? (valueRef as? NSAttributedString)?.string {
                // Do not silently clamp a stale AX caret into a newer, shorter value.
                guard selectedRange.location <= (fullText as NSString).length,
                      selectedRange.length <= (fullText as NSString).length - selectedRange.location else { return nil }
                let ctx = Self.makeCaretContext(fieldIdentifier: fieldID, text: fullText,
                                             selection: selectedRange, selectedText: selectedText,
                                             maxSurroundingLength: maxSurroundingLength)
                extractionCache.update(
                    context: ctx,
                    bundleID: bundleID,
                    elementHash: elementHash,
                    approach: .standardAX,
                    caretRect: nil,
                    fieldRect: nil,
                    estimatedCharWidth: 8.5,
                    time: uptime
                )
                return ctx
            }

            // Fallback: If kAXValueAttribute is unavailable (common in AppKit NSTextView, Xcode, etc.),
            // use parameterized attribute kAXStringForRangeParameterizedAttribute around the caret.
            let queryStart = max(0, selectedRange.location - maxSurroundingLength)
            let queryLength = (selectedRange.location - queryStart) + selectedRange.length + maxSurroundingLength
            var queryRange = CFRange(location: queryStart, length: queryLength)
            if let rangeValue = AXValueCreate(.cfRange, &queryRange) {
                var strRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &strRef) == .success {
                    let chunk = (strRef as? String) ?? (strRef as? NSAttributedString)?.string
                    if let chunk = chunk, !chunk.isEmpty {
                        let caretOffsetInChunk = min(selectedRange.location - queryStart, (chunk as NSString).length)
                        let textBefore = (chunk as NSString).substring(to: caretOffsetInChunk)
                        let selLengthInChunk = min(selectedRange.length, (chunk as NSString).length - caretOffsetInChunk)
                        let textAfterStart = caretOffsetInChunk + selLengthInChunk
                        let textAfter = textAfterStart <= (chunk as NSString).length
                            ? (chunk as NSString).substring(from: textAfterStart)
                            : ""
                        let selText = selectedText.isEmpty && selLengthInChunk > 0
                            ? (chunk as NSString).substring(with: NSRange(location: caretOffsetInChunk, length: selLengthInChunk))
                            : selectedText

                        let ctx = CaretContext(
                            fieldIdentifier: fieldID,
                            textBeforeCaret: textBefore,
                            textAfterCaret: textAfter,
                            selectedText: selText,
                            caretLocation: selectedRange.location,
                            fullTextLength: max(selectedRange.location + (chunk as NSString).length - caretOffsetInChunk, (chunk as NSString).length)
                        )
                        extractionCache.update(
                            context: ctx,
                            bundleID: bundleID,
                            elementHash: elementHash,
                            approach: .standardAX,
                            caretRect: nil,
                            fieldRect: nil,
                            estimatedCharWidth: 8.5,
                            time: uptime
                        )
                        return ctx
                    }
                }
            }

            let ctx = CaretContext(
                fieldIdentifier: fieldID,
                textBeforeCaret: "",
                textAfterCaret: "",
                selectedText: selectedText,
                caretLocation: selectedRange.location,
                fullTextLength: 0
            )
            extractionCache.update(
                context: ctx,
                bundleID: bundleID,
                elementHash: elementHash,
                approach: .standardAX,
                caretRect: nil,
                fieldRect: nil,
                estimatedCharWidth: 8.5,
                time: uptime
            )
            return ctx
        }

        // WebKit / Safari / Apple Mail / Google Docs AXTextMarker fallback
        if let markerContext = captureWebKitMarkerCaretContext(element: element, fieldIdentifier: fieldID, maxSurroundingLength: maxSurroundingLength) {
            extractionCache.update(
                context: markerContext,
                bundleID: bundleID,
                elementHash: elementHash,
                approach: .webKitMarker,
                caretRect: nil,
                fieldRect: nil,
                estimatedCharWidth: 8.5,
                time: uptime
            )
            return markerContext
        }

        extractionCache.recordFailure()
        return nil
    }

    /// AX ranges and stored caret locations are UTF-16 offsets. Expand only
    /// the context window edges so a small window never splits an emoji.
    static func makeCaretContext(fieldIdentifier: String, text: String, selection: CFRange,
                                 selectedText: String, maxSurroundingLength: Int = 200) -> CaretContext {
        let string = text as NSString
        let count = string.length
        let caret = max(0, min(selection.location, count))
        let selectionEnd = caret + min(max(0, selection.length), count - caret)
        let limit = min(max(0, maxSurroundingLength), count)
        var start = caret - min(caret, limit)
        var end = selectionEnd + min(count - selectionEnd, limit)
        if start < caret { start = string.rangeOfComposedCharacterSequence(at: start).location }
        if end > selectionEnd {
            let last = string.rangeOfComposedCharacterSequence(at: end - 1)
            end = last.location + last.length
        }
        return CaretContext(fieldIdentifier: fieldIdentifier,
            textBeforeCaret: string.substring(with: NSRange(location: start, length: caret - start)),
            textAfterCaret: string.substring(with: NSRange(location: selectionEnd, length: end - selectionEnd)),
            selectedText: selectionEnd > caret
                ? string.substring(with: NSRange(location: caret, length: selectionEnd - caret)) : selectedText,
            caretLocation: caret, fullTextLength: count)
    }

    // MARK: - Caret Positioning

    /// Retrieves both the measured caret insertion rect and the enclosing input field bounds
    /// converted to Cocoa screen coordinates (`primaryScreenMaxY - pt.y - sz.height`).
    func caretAndFieldBounds(preferCache: Bool = false) -> (caret: CGRect, fieldRect: CGRect?)? {
        let uptime = ProcessInfo.processInfo.systemUptime
        if preferCache, let cached = extractionCache.getCachedCaretBounds(currentTime: uptime) {
            return cached
        }

        guard let element = focusedTextElement(), let primaryScreen = NSScreen.screens.first else {
            extractionCache.recordFailure()
            return nil
        }
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Terminal cursor resolution fallback
        if let frontmostID, AutoCorrectionGate.isTerminalApp(bundleID: frontmostID) {
            let approach: TextExtractionApproach = (frontmostID == "com.apple.Terminal") ? .terminalLastPage : .xtermScreen
            let promptText = extractionCache.currentRecord?.textBeforeCaret
            if let bounds = resolveTerminalCaretBounds(element: element, bundleID: frontmostID, approach: approach, promptText: promptText) {
                if var rec = extractionCache.currentRecord {
                    rec.caretRect = bounds.caret
                    rec.fieldRect = bounds.fieldRect
                    extractionCache.update(
                        context: rec.toCaretContext(),
                        bundleID: frontmostID,
                        elementHash: rec.elementHash,
                        approach: approach,
                        caretRect: bounds.caret,
                        fieldRect: bounds.fieldRect,
                        estimatedCharWidth: rec.estimatedCharWidth,
                        time: uptime
                    )
                }
                return bounds
            }
        }

        var selectedValue: CFTypeRef?
        var selectedRange: CFRange?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                         &selectedValue) == .success,
           let value = selectedValue, CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(value as! AXValue, .cfRange, &range) { selectedRange = range }
        }
        let primaryScreenMaxY = primaryScreen.frame.maxY
        let caret = Self.resolveCaretBounds(selectedRange: selectedRange,
            primaryScreenMaxY: primaryScreenMaxY,
            rangeBounds: { query in
                var query = query
                guard let value = AXValueCreate(.cfRange, &query) else { return nil }
                return self.parameterizedRect(element, attribute: kAXBoundsForRangeParameterizedAttribute as String,
                                              parameter: value)
            }, markerBounds: { self.selectedMarkerCaretBounds(element) })
        guard let caret, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(caret) }) else {
            extractionCache.recordFailure()
            return nil
        }
        let adjustedCaret = Self.adjustCaretForApp(caret: caret, bundleID: frontmostID)

        var fieldRect: CGRect?
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let position = positionValue, let size = sizeValue,
           CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &pt),
               AXValueGetValue(size as! AXValue, .cgSize, &sz),
               pt.x.isFinite, pt.y.isFinite, sz.width.isFinite, sz.height.isFinite,
               sz.width > 0, sz.height > 0 {
                fieldRect = CGRect(x: pt.x, y: primaryScreenMaxY - pt.y - sz.height,
                                   width: sz.width, height: sz.height)
            }
        }

        if var rec = extractionCache.currentRecord, let frontmostID {
            extractionCache.update(
                context: rec.toCaretContext(),
                bundleID: frontmostID,
                elementHash: rec.elementHash,
                approach: rec.approach,
                caretRect: adjustedCaret,
                fieldRect: fieldRect,
                estimatedCharWidth: rec.estimatedCharWidth,
                time: uptime
            )
        }

        return (caret: adjustedCaret, fieldRect: fieldRect)
    }

    /// Only return measured insertion bounds. Field bounds and mouse location
    /// are not cursor positions and must never anchor inline suggestions.
    func caretScreenRect(preferCache: Bool = false) -> CGRect? {
        caretAndFieldBounds(preferCache: preferCache)?.caret
    }

    // MARK: - Terminal Text & Caret Extraction
    
    /// Extracts the terminal screen text or command prompt from Apple Terminal or xterm-based emulators.
    func captureTerminalCaretContext(
        element: AXUIElement,
        bundleID: String,
        approach: TextExtractionApproach,
        maxSurroundingLength: Int = 200
    ) -> (context: CaretContext, parsed: TerminalPromptExtractor.TerminalExtractionResult)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let elementHash = CFHash(element)
        let fieldID = "terminal:\(bundleID):\(pid):\(elementHash)"
        
        guard let screenText = extractTerminalScreenText(element: element) else { return nil }
        let parsed = TerminalPromptExtractor.parseTerminalBuffer(screenText)
        
        let command = parsed.currentCommand ?? ""
        let textBefore = String(command.suffix(maxSurroundingLength))
        let context = CaretContext(
            fieldIdentifier: fieldID,
            textBeforeCaret: textBefore,
            textAfterCaret: "",
            selectedText: "",
            caretLocation: textBefore.utf16.count,
            fullTextLength: textBefore.utf16.count
        )
        return (context: context, parsed: parsed)
    }
    
    /// Traverses terminal window and text view nodes to extract the visible terminal screen text.
    func extractTerminalScreenText(element: AXUIElement) -> String? {
        // 1. Direct value on element (e.g. Apple Terminal AXTextArea or iTerm2 view)
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success {
            if let str = valueRef as? String, !str.isEmpty {
                return str
            } else if let attrStr = valueRef as? NSAttributedString, !attrStr.string.isEmpty {
                return attrStr.string
            }
        }
        
        // 2. Visible character range parameterized string
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXVisibleCharacterRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var cfRange = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange), cfRange.length > 0 {
                let boundedLength = min(cfRange.length, 4000)
                var query = CFRange(location: cfRange.location, length: boundedLength)
                if let val = AXValueCreate(.cfRange, &query) {
                    var strRef: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, val, &strRef) == .success {
                        if let s = strRef as? String, !s.isEmpty { return s }
                        if let attr = strRef as? NSAttributedString, !attr.string.isEmpty { return attr.string }
                    }
                }
            }
        }
        
        // 3. Inspect children of the element (e.g. AXScrollArea -> AXTextArea or AXGroup)
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                var childVal: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &childVal) == .success {
                    if let s = childVal as? String, !s.isEmpty { return s }
                    if let attr = childVal as? NSAttributedString, !attr.string.isEmpty { return attr.string }
                }
            }
        }
        
        // 4. Description attribute fallback (used by some xterm emulators)
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let str = descRef as? String, !str.isEmpty {
            return str
        }
        
        return nil
    }

    /// Resolves caret bounds and viewport rect for terminal emulators.
    func resolveTerminalCaretBounds(
        element: AXUIElement,
        bundleID: String,
        approach: TextExtractionApproach,
        promptText: String?,
        parsedResult: TerminalPromptExtractor.TerminalExtractionResult? = nil
    ) -> (caret: CGRect, fieldRect: CGRect?)? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        let primaryScreenMaxY = primaryScreen.frame.maxY
        
        // 1. Determine element frame
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        var pt = CGPoint.zero
        var sz = CGSize.zero
        
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let p = positionValue, let s = sizeValue,
           CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() {
            _ = AXValueGetValue(p as! AXValue, .cgPoint, &pt)
            _ = AXValueGetValue(s as! AXValue, .cgSize, &sz)
        }
        
        if sz.width <= 0 || sz.height <= 0 {
            // Try window level if element size is unpopulated
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
               let win = windowRef, CFGetTypeID(win) == AXUIElementGetTypeID() {
                var wPos: CFTypeRef?
                var wSize: CFTypeRef?
                if AXUIElementCopyAttributeValue(win as! AXUIElement, kAXPositionAttribute as CFString, &wPos) == .success,
                   AXUIElementCopyAttributeValue(win as! AXUIElement, kAXSizeAttribute as CFString, &wSize) == .success,
                   let wp = wPos, let ws = wSize {
                    _ = AXValueGetValue(wp as! AXValue, .cgPoint, &pt)
                    _ = AXValueGetValue(ws as! AXValue, .cgSize, &sz)
                }
            }
        }
        
        guard sz.width > 20, sz.height > 20 else { return nil }
        let fieldRect = CGRect(x: pt.x, y: primaryScreenMaxY - pt.y - sz.height, width: sz.width, height: sz.height)
        
        // 2. Try native parameterized range bounds if terminal supports it
        var query = CFRange(location: (promptText?.utf16.count ?? 0), length: 0)
        if let queryVal = AXValueCreate(.cfRange, &query),
           let rect = parameterizedRect(element, attribute: kAXBoundsForRangeParameterizedAttribute as String, parameter: queryVal),
           fieldRect.contains(CGPoint(x: rect.midX, y: rect.midY)) {
            return (caret: rect, fieldRect: fieldRect)
        }
        
        // 3. Monospace font cell prediction
        let font: NSFont = {
            if Thread.isMainThread {
                return MainActor.assumeIsolated {
                    EditorFontCustomizer.shared.font(for: bundleID, caretHeight: nil)
                        ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                }
            } else {
                return NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            }
        }()
        
        let cellWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: font]).width
        let cellHeight: CGFloat = max(14, font.ascender - font.descender + font.leading)
        
        // Padding defaults: Apple Terminal ~10pt left / 6pt bottom, iTerm2 ~8pt left / 5pt bottom
        let paddingLeft: CGFloat = (bundleID == "com.apple.Terminal") ? 10.0 : 8.0
        let paddingBottom: CGFloat = (bundleID == "com.apple.Terminal") ? 6.0 : 5.0
        let paddingTop: CGFloat = (bundleID == "com.apple.Terminal") ? 6.0 : 4.0
        
        let parsed = parsedResult ?? {
            if let screenText = extractTerminalScreenText(element: element) {
                return TerminalPromptExtractor.parseTerminalBuffer(screenText)
            }
            return nil
        }()
        
        let column: Int
        if let parsed, parsed.cursorColumn > 0 {
            column = parsed.cursorColumn
        } else {
            let commandLen = promptText?.count ?? 0
            let promptPrefixLen = 2 // typical prompt marker "$ " or "❯ "
            column = promptPrefixLen + commandLen
        }
        
        let caretX = min(fieldRect.minX + paddingLeft + CGFloat(column) * cellWidth, fieldRect.maxX - 4)
        
        let caretY: CGFloat
        if let parsed, let lineIdx = parsed.promptLineIndex {
            let computedY = fieldRect.maxY - paddingTop - CGFloat(lineIdx + 1) * cellHeight
            caretY = max(fieldRect.minY + paddingBottom, min(computedY, fieldRect.maxY - paddingTop - cellHeight))
        } else {
            caretY = fieldRect.minY + paddingBottom
        }
        
        let caretRect = CGRect(x: caretX, y: caretY, width: 2, height: cellHeight)
        
        return (caret: caretRect, fieldRect: fieldRect)
    }

    /// App-specific coordinate corrections for applications with uncompensated container insets.
    static func adjustCaretForApp(caret: CGRect, bundleID: String?) -> CGRect {
        // Universal TextKit caret baseline resolution in `resolveCaretBounds` dynamically
        // aligns coordinates across all editors (Apple Notes, Telegram, TextEdit, Pages).
        return caret
    }

    /// Detects applications whose rich text / paste handlers strip trailing spaces (e.g. Microsoft Word Smart Cut and Paste).
    static func isSmartPasteApp(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == "com.microsoft.Word"
            || bundleID == "com.microsoft.Powerpoint"
            || bundleID == "com.microsoft.Outlook"
            || bundleID == "com.microsoft.Excel"
            || bundleID == "com.microsoft.onenote.mac"
    }

    /// Popup fallback only. This is deliberately never used for inline text.
    func focusedFieldScreenRect() -> CGRect? {
        guard let element = focusedTextElement(), let screen = NSScreen.screens.first else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.05)
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let position = positionValue, let size = sizeValue,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        let rect = CGRect(x: point.x, y: screen.frame.maxY - point.y - dimensions.height,
                          width: dimensions.width, height: dimensions.height)
        guard let visible = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) })?.visibleFrame else { return nil }
        return rect.intersection(visible)
    }

    func focusedTextElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) != .success,
           let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.05)
            AXUIElementCopyAttributeValue(appElement,
                                          kAXFocusedUIElementAttribute as CFString, &value)
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let root = value as! AXUIElement
        AXUIElementSetMessagingTimeout(root, 0.05)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.04
        let resolved = Self.resolveFocusedTextNode(root: root, attributes: { element in
            AXUIElementSetMessagingTimeout(element, 0.05)
            var role: CFTypeRef?
            var subrole: CFTypeRef?
            var focused: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focused)
            return (role as? String, subrole as? String, (focused as? Bool) == true)
        }, focusedChild: { element in
            AXUIElementSetMessagingTimeout(element, 0.05)
            var child: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString,
                                                &child) == .success,
                  let child, CFGetTypeID(child) == AXUIElementGetTypeID() else { return nil }
            return child as! AXUIElement
        }, children: { element in
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            return children as? [AXUIElement] ?? []
        }, shouldContinue: { ProcessInfo.processInfo.systemUptime < deadline })

        if resolved == nil, let app = NSWorkspace.shared.frontmostApplication,
           AutoCorrectionGate.isTerminalApp(bundleID: app.bundleIdentifier) {
            return root
        }
        return resolved
    }

    /// Follow confirmed focus, including nested web editors, never a merely
    /// editable descendant. Bound the traversal and reject ambiguous focus.
    static func resolveFocusedTextNode<Node: Hashable>(
        root: Node, attributes: (Node) -> (role: String?, subrole: String?, focused: Bool),
        focusedChild: (Node) -> Node?, children: (Node) -> [Node],
        limit: Int = 128, shouldContinue: () -> Bool = { true }
    ) -> Node? {
        let leafTextRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]
        var pending: [(Node, Bool)] = [(root, true)]
        var visited: Set<Node> = []
        var result: Node?
        var webAreaFallback: Node?
        while !pending.isEmpty {
            guard visited.count < limit, shouldContinue() else { break }
            let (node, linkedFocus) = pending.removeLast()
            guard visited.insert(node).inserted else { continue }
            let info = attributes(node)
            let confirmed = linkedFocus || info.focused
            if AutoCorrectionGate.isSecureField(role: info.role, subrole: info.subrole) {
                if confirmed { return nil }
                continue
            }
            if leafTextRoles.contains(info.role ?? "") {
                if confirmed {
                    guard result == nil || result == node else { return nil }
                    result = node
                }
                continue
            }
            if info.role == "AXWebArea" && confirmed && webAreaFallback == nil {
                webAreaFallback = node
            }
            if let child = focusedChild(node), child != node {
                pending.append((child, true))
                continue
            }
            if ["AXWindow", "AXGroup", "AXWebArea", "AXScrollArea", "AXSplitGroup"].contains(info.role ?? "") {
                pending.append(contentsOf: children(node).reversed().map { ($0, false) })
            }
        }
        return result ?? webAreaFallback
    }

    func prepareBrowserAccessibilityAsync(for app: NSRunningApplication) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.prepareBrowserAccessibility(for: app)
        }
    }

    /// Electron and Chromium document these attributes for third-party assistive applications.
    /// Request once per active process asynchronously on app activation, not on every keystroke.
    func prepareBrowserAccessibility(for app: NSRunningApplication? = nil) {
        guard let app = app ?? NSWorkspace.shared.frontmostApplication,
              AXIsProcessTrusted() else { return }

        let pid = app.processIdentifier
        electronPIDLock.lock()
        if preparedElectronPIDs.contains(pid) {
            electronPIDLock.unlock()
            return
        }
        electronPIDLock.unlock()

        let bundlePath = app.bundleURL?.path ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        let isElectronOrChromium = bundlePath.contains("Electron") ||
                                   bundlePath.contains("Chrome") ||
                                   bundlePath.contains("Opera") ||
                                   bundlePath.contains("Brave") ||
                                   bundlePath.contains("Edge") ||
                                   bundlePath.contains("Arc") ||
                                   bundlePath.contains("Antigravity") ||
                                   bundleID.contains("antigravity") ||
                                   bundleID.contains("vscode") ||
                                   bundleID.contains("cursor") ||
                                   FileManager.default.fileExists(atPath: (app.bundleURL?.appendingPathComponent(
                                    "Contents/Frameworks/Electron Framework.framework").path) ?? "")

        guard isElectronOrChromium else { return }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)

        electronPIDLock.lock()
        preparedElectronPIDs.insert(pid)
        electronPIDLock.unlock()
    }

    private func parameterizedRect(_ element: AXUIElement, attribute: String, parameter: CFTypeRef) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    private func selectedMarkerCaretBounds(_ element: AXUIElement) -> CGRect? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString,
                                           &markerRange) == .success, let markerRange else { return nil }
        // A selected span is not an insertion point. Require an empty marker string.
        var selectedText: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString,
            markerRange, &selectedText) == .success, let text = selectedText as? String, text.isEmpty else { return nil }
        return parameterizedRect(element, attribute: "AXBoundsForTextMarkerRange", parameter: markerRange)
    }

    /// Minimum vertical offset (in Cocoa points) between zero-length layout fragment top
    /// and actual character baseline to detect TextKit 2 insertion-point rendering anomaly.
    static let textKitBaselineAnomalyThreshold: CGFloat = 4.0

    static func resolveCaretBounds(selectedRange: CFRange?, primaryScreenMaxY: CGFloat,
                                   rangeBounds: (CFRange) -> CGRect?, markerBounds: () -> CGRect?) -> CGRect? {
        if let range = selectedRange {
            guard range.location >= 0, range.length == 0 else { return nil }
            let zeroBounds = rangeBounds(range)
            let prevBounds = range.location > 0 ? rangeBounds(CFRange(location: range.location - 1, length: 1)) : nil

            // 1. If preceding character is available, verify and compensate for TextKit 2 layout offset anomaly:
            // in Apple Notes and TextKit 2 apps, zero-length ranges return paragraph/layout fragment tops
            // (shifted up ~1 line height in screen space), while the preceding character's maxX strictly matches X.
            if let prev = prevBounds,
               let prevCaret = normalizedCaretBounds(prev, primaryScreenMaxY: primaryScreenMaxY, precedingCharacter: true) {
                if let zero = zeroBounds,
                   let zeroCaret = normalizedCaretBounds(zero, primaryScreenMaxY: primaryScreenMaxY, precedingCharacter: false) {
                    // Check if X coordinates align horizontally (same line, not a soft wrap)
                    if abs(zeroCaret.minX - prevCaret.minX) <= 1.5 {
                        // Same line: if zero-length Y is substantially higher than preceding char Y (TextKit 2 bug),
                        // use the true line baseline from preceding character.
                        if zeroCaret.origin.y > prevCaret.origin.y + textKitBaselineAnomalyThreshold {
                            return prevCaret
                        }
                        return zeroCaret
                    } else {
                        // Soft wrap or start of newline: check if succeeding character provides the true line baseline
                        if let next = rangeBounds(CFRange(location: range.location, length: 1)),
                           let nextCaret = normalizedCaretBounds(next, primaryScreenMaxY: primaryScreenMaxY, precedingCharacter: false),
                           abs(zeroCaret.minX - nextCaret.minX) <= 1.5,
                           zeroCaret.origin.y > nextCaret.origin.y + textKitBaselineAnomalyThreshold {
                            return nextCaret
                        }
                        return zeroCaret
                    }
                }
                return prevCaret
            }

            // 2. If at start of line (or document), check succeeding character (length: 1 at location)
            // for the same TextKit 2 top-offset anomaly.
            if let zero = zeroBounds,
               let zeroCaret = normalizedCaretBounds(zero, primaryScreenMaxY: primaryScreenMaxY, precedingCharacter: false) {
                if let next = rangeBounds(CFRange(location: range.location, length: 1)),
                   let nextCaret = normalizedCaretBounds(next, primaryScreenMaxY: primaryScreenMaxY, precedingCharacter: false) {
                    if abs(zeroCaret.minX - nextCaret.minX) <= 1.5,
                       zeroCaret.origin.y > nextCaret.origin.y + textKitBaselineAnomalyThreshold {
                        return nextCaret
                    }
                }
                return zeroCaret
            }
        }
        guard let bounds = markerBounds(), bounds.width <= 2 else { return nil }
        return normalizedCaretBounds(bounds, primaryScreenMaxY: primaryScreenMaxY, precedingCharacter: false)
    }

    static func normalizedCaretBounds(_ rect: CGRect, primaryScreenMaxY: CGFloat,
                                      precedingCharacter: Bool) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.width <= 100, rect.height > 0, rect.height <= 80 else { return nil }
        return CGRect(x: precedingCharacter ? rect.maxX : rect.minX,
                      y: primaryScreenMaxY - rect.maxY, width: 1, height: rect.height)
    }

    struct ReplacementTarget {
        let element: AXUIElement
        let processID: pid_t
    }

    func captureReplacementTarget() -> ReplacementTarget? {
        guard let element = focusedTextElement(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        // Appending at the caret only needs a readable insertion point. Web
        // editors can support paste while exposing AX selection as read-only.
        return ReplacementTarget(element: element, processID: app.processIdentifier)
    }

    func isCurrentReplacementTarget(_ target: ReplacementTarget) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID,
              let element = focusedTextElement() else { return false }
        return CFEqual(element, target.element)
    }

    /// Direct AX replacement is synchronous and must be confirmed by reading
    /// the resulting text. An acknowledged setter may still be a no-op.
    func replaceVerifiedSuffix(_ expected: String, with replacement: String, target: ReplacementTarget,
                               preferPasteInWebEditors: Bool = false) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processID,
              let focused = focusedTextElement(), CFEqual(focused, target.element) else { return false }
        // Electron acknowledges AX writes before its renderer applies them.
        // Use the confirmed asynchronous selection/paste path instead.
        guard !preferPasteInWebEditors || !isElectronOrChromiumApp(pid: target.processID) else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString,
                                            &settable) == .success, settable.boolValue else { return false }
        var value: CFTypeRef?
        var selectionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString,
                                            &selectionValue) == .success,
              let selectionValue, CFGetTypeID(selectionValue) == AXValueGetTypeID() else { return false }
        var selection = CFRange()
        guard AXValueGetValue(selectionValue as! AXValue, .cfRange, &selection),
              let plan = Self.verifiedSuffixRange(text: text, selection: selection, expected: expected)
        else { return false }
        var range = CFRange(location: plan.location, length: plan.length)
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString,
                                            rangeValue) == .success else { return false }
        // Recheck the editor's actual selection before replacing any content.
        var actual: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &actual) == .success,
              actual as? String == expected else {
            restoreSelectionIfUnchanged(focused, selectedRange: range, original: selection)
            return false
        }
        AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, replacement as CFString)
        var updated: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &updated)
        guard Self.replacementWasApplied(original: text, range: plan, replacement: replacement,
                                         observed: updated as? String) else {
            // Never leave a word highlighted after an ignored/failed setter.
            restoreSelectionIfUnchanged(focused, selectedRange: range, original: selection)
            return false
        }
        var endRange = CFRange(location: plan.location + (replacement as NSString).length, length: 0)
        if let rangeValue = AXValueCreate(.cfRange, &endRange) {
            AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, rangeValue)
        }
        return true
    }

    /// Inserts text directly at the current insertion point (caret) without replacing existing content.
    func insertAtCaret(_ text: String, target: ReplacementTarget) -> Bool {
        guard isCurrentReplacementTarget(target) else { return false }
        let element = target.element
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }

        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        return result == .success
    }

    /// Append without selecting/replacing existing text. Contenteditable fields
    /// may expose a readable caret but no AXSelectedText or writable AX range.
    func pasteContinuationAtCaret(_ text: String, target: ReplacementTarget,
                                  onApplied: @escaping (Bool) -> Void) -> Bool {
        pendingSelection?.cancel()
        pendingPaste?.check(final: true)
        guard !text.isEmpty, isCurrentReplacementTarget(target) else { return false }
        let element = target.element
        let appBundleID = NSRunningApplication(processIdentifier: target.processID)?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let prepared = Self.prepareClipboardReplacement(for: text, bundleID: appBundleID)
        let source = CGEventSource(stateID: .hidSystemState)

        // If pure whitespace cannot be pasted via Cmd+V, send as synthetic keystroke.
        if (prepared.prependLeadingSpace || prepared.appendTrailingSpace) && prepared.text.isEmpty {
            guard let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                  let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) else { return false }
            spaceDown.flags = []
            spaceUp.flags = []
            spaceDown.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
            spaceUp.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
            spaceDown.post(tap: .cgAnnotatedSessionEventTap)
            spaceUp.post(tap: .cgAnnotatedSessionEventTap)
            onApplied(true)
            return true
        }

        func caret() -> Int? {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(value as! AXValue, .cfRange, &range), range.length == 0 {
                    return range.location
                }
            }
            if let context = captureWebKitMarkerCaretContext(element: element, fieldIdentifier: "") {
                return context.caretLocation
            }
            return nil
        }
        func value() -> String? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            return (value as? String) ?? (value as? NSAttributedString)?.string
        }
        let originalCaret = caret()
        let original = value()
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return false }

        let pasteboard = NSPasteboard.general
        let saved = TransientPasteboard.snapshot(pasteboard: pasteboard)
        let revision = TransientPasteboard.writeString(prepared.text, pasteboard: pasteboard)
        let sent = Self.dispatchVerifiedPaste(to: target.processID, verifySelection: {
            self.isCurrentReplacementTarget(target) && (originalCaret == nil || caret() == originalCaret)
                && (original == nil || value() == original)
        }, post: { _ in
            if prepared.prependLeadingSpace {
                if let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                   let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) {
                    spaceDown.flags = []
                    spaceUp.flags = []
                    spaceDown.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                    spaceUp.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                    spaceDown.post(tap: .cgAnnotatedSessionEventTap)
                    spaceUp.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
            for event in [down, up] {
                event.flags = .maskCommand
                event.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                event.post(tap: .cgAnnotatedSessionEventTap)
            }
            if prepared.appendTrailingSpace {
                if let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                   let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) {
                    spaceDown.flags = []
                    spaceUp.flags = []
                    spaceDown.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                    spaceUp.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                    spaceDown.post(tap: .cgAnnotatedSessionEventTap)
                    spaceUp.post(tap: .cgAnnotatedSessionEventTap)
                }
            }
        })
        guard sent else {
            if pasteboard.changeCount == revision { TransientPasteboard.restore(saved, pasteboard: pasteboard) }
            return false
        }
        let receipt = PasteConfirmation(applied: {
            if AutoCorrectionGate.isTerminalApp(bundleID: appBundleID) {
                return true
            }
            if let origCaret = originalCaret {
                return Self.continuationWasApplied(original: original, observed: value(),
                    caretBefore: origCaret, caretAfter: caret(), inserted: text)
            }
            // When the editor does not expose kAXSelectedTextRangeAttribute (e.g. Chromium/Electron custom webviews),
            // check kAXValueAttribute if available, otherwise consider the dispatched Cmd+V applied.
            if let orig = original, let obs = value() {
                return obs != orig && obs.count >= orig.count + text.count
            }
            return true
        }, finish: { [weak self] applied in
            guard let self else { return }
            self.pendingPaste = nil
            if pasteboard.changeCount == revision {
                TransientPasteboard.restore(saved, pasteboard: pasteboard)
            }
            onApplied(applied)
        })
        pendingPaste = receipt
        for attempt in 1...25 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.01) {
                receipt.check(final: attempt == 25)
            }
        }
        return true
    }

    static func continuationWasApplied(original: String?, observed: String?,
                                       caretBefore: Int, caretAfter: Int?, inserted: String) -> Bool {
        if let original, let observed {
            return replacementWasApplied(original: original,
                range: NSRange(location: caretBefore, length: 0), replacement: inserted,
                observed: observed, allowFollowingInput: true)
        }
        return caretAfter == caretBefore + inserted.utf16.count
    }

    /// Fallback for automatic word correction in editors with ignored AX setters.
    /// Re-read the text and focus before selecting anything; never send backspaces.
    func pasteVerifiedSuffix(_ expected: String, with replacement: String, target: ReplacementTarget,
                             completion: @escaping (Bool) -> Void,
                             onApplied: ((Bool) -> Void)? = nil) {
        // A stop/restart may have cancelled the old correction session while
        // its clipboard receipt is still pending. Finalize it before replacing it.
        pendingSelection?.cancel()
        pendingPaste?.check(final: true)
        guard isCurrentReplacementTarget(target) else { completion(false); return }
        let appBundleID = NSRunningApplication(processIdentifier: target.processID)?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let appBundleID, AutoCorrectionGate.isTerminalApp(bundleID: appBundleID) {
            replaceWithBackspaces(count: expected.utf16.count, replacement: replacement) { applied in
                completion(applied)
                onApplied?(applied)
            }
            return
        }
        let element = target.element
        var value: CFTypeRef?
        var selectionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &selectionValue) == .success,
              let selectionValue, CFGetTypeID(selectionValue) == AXValueGetTypeID() else { completion(false); return }
        var original = CFRange()
        guard AXValueGetValue(selectionValue as! AXValue, .cfRange, &original) else {
            completion(false); return
        }
        let fallbackCaret = original.length == 0 ? original : CFRange(location: original.location + original.length, length: 0)

        let plan: NSRange
        if original.length == 0 {
            guard let suffixPlan = Self.verifiedSuffixRange(text: text, selection: original, expected: expected) else {
                completion(false); return
            }
            plan = suffixPlan
        } else if original.length == expected.utf16.count {
            // Text is already selected (e.g. from replaceVerifiedSuffix attempt)
            var selected: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
                  selected as? String == expected else {
                completion(false); return
            }
            plan = NSRange(location: original.location, length: original.length)
        } else {
            completion(false); return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            completion(false); return
        }
        var range = CFRange(location: plan.location, length: plan.length)
        if Self.requiresSelectionWrite(original: original, replacementRange: plan) {
            guard let rangeValue = AXValueCreate(.cfRange, &range),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success else {
                completion(false); return
            }
        }
        // AX range changes can arrive asynchronously in Chromium editors.
        // Wait for the exact text AND range before touching the clipboard.
        let selectionConfirmation = PasteConfirmation(applied: { [self] in
            guard isCurrentReplacementTarget(target) else { return false }
            var observed: CFTypeRef?
            var selected: CFTypeRef?
            var selectedRange: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &observed) == .success,
               let obs = observed as? String, obs != text {
                return false
            }
            guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
                  selected as? String == expected,
                  AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
                  let selectedRange, CFGetTypeID(selectedRange) == AXValueGetTypeID() else { return false }
            var current = CFRange()
            return AXValueGetValue(selectedRange as! AXValue, .cfRange, &current)
                && current.location == range.location && current.length == range.length
        }, finish: { [self] ready in
            pendingSelection = nil
            guard ready else {
                if isCurrentReplacementTarget(target) {
                    restoreSelectionIfUnchanged(element, selectedRange: range, original: fallbackCaret)
                }
                completion(false)
                return
            }
            let appBundleID = NSRunningApplication(processIdentifier: target.processID)?.bundleIdentifier
                ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let prepared = Self.prepareClipboardReplacement(for: replacement, bundleID: appBundleID)

            let pasteboard = NSPasteboard.general
            let saved = TransientPasteboard.snapshot(pasteboard: pasteboard)
            let pasteboardRevision = TransientPasteboard.writeString(prepared.text, pasteboard: pasteboard)
            let sent = Self.dispatchVerifiedPaste(to: target.processID, verifySelection: {
                guard self.isCurrentReplacementTarget(target) else { return false }
                var selectedText: CFTypeRef?
                var selectedRangeValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText) == .success,
                      selectedText as? String == expected,
                      AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success,
                      let selectedRangeValue, CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else { return false }
                var currentRange = CFRange()
                return AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &currentRange)
                    && currentRange.location == range.location && currentRange.length == range.length
            }, post: { _ in
                if prepared.prependLeadingSpace {
                    if let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                       let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) {
                        spaceDown.flags = []
                        spaceUp.flags = []
                        spaceDown.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                        spaceUp.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                        spaceDown.post(tap: .cgAnnotatedSessionEventTap)
                        spaceUp.post(tap: .cgAnnotatedSessionEventTap)
                    }
                }
                for event in [down, up] {
                    event.flags = .maskCommand
                    event.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                    event.post(tap: .cgAnnotatedSessionEventTap)
                }
                if prepared.appendTrailingSpace {
                    if let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true),
                       let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false) {
                        spaceDown.flags = []
                        spaceUp.flags = []
                        spaceDown.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                        spaceUp.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                        spaceDown.post(tap: .cgAnnotatedSessionEventTap)
                        spaceUp.post(tap: .cgAnnotatedSessionEventTap)
                    }
                }
            })
            guard sent else {
                if pasteboard.changeCount == pasteboardRevision {
                    TransientPasteboard.restore(saved, pasteboard: pasteboard)
                }
                if isCurrentReplacementTarget(target) {
                    restoreSelectionIfUnchanged(element, selectedRange: range, original: fallbackCaret)
                }
                completion(false)
                return
            }
            // Once verified selection was matched and paste was posted via Cmd+V,
            // notify completion immediately so layout can switch without lag.
            completion(true)

            let confirmation = PasteConfirmation(applied: {
                var observed: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &observed) == .success,
                   let obs = observed as? String {
                    return Self.replacementWasApplied(original: text, range: plan, replacement: replacement,
                                                      observed: obs, allowFollowingInput: true)
                }
                // When kAXValueAttribute is unsupported (Electron, Chromium, WebKit contenteditable),
                // the paste is considered applied once dispatched.
                return true
            }, finish: { [weak self] applied in
                guard let self else { return }
                self.pendingPaste = nil
                onApplied?(applied)
                var observed: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &observed)
                if !applied, observed as? String == text, self.isCurrentReplacementTarget(target) {
                    self.restoreSelectionIfUnchanged(element, selectedRange: range, original: fallbackCaret)
                }
                // Restore only our clipboard contents; preserve any subsequent user copy.
                if pasteboard.changeCount == pasteboardRevision {
                    TransientPasteboard.restore(saved, pasteboard: pasteboard)
                }
            })
            pendingPaste = confirmation
            // Usually confirm within a few milliseconds, rather than leaving the
            // layout and correction state pending for a fixed 100 ms.
            for attempt in 1...20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.005) {
                    confirmation.check(final: attempt == 20)
                }
            }
        })
        pendingSelection = selectionConfirmation
        selectionConfirmation.check()
        for attempt in 1...20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt) * 0.005) {
                selectionConfirmation.check(final: attempt == 20)
            }
        }
    }

    static func requiresSelectionWrite(original: CFRange, replacementRange: NSRange) -> Bool {
        original.length == 0 && replacementRange.length > 0
    }

    static func dispatchVerifiedPaste(to processID: pid_t, verifySelection: () -> Bool,
                                      post: (pid_t) -> Void) -> Bool {
        guard verifySelection() else { return false }
        post(processID)
        return true
    }

    static func replacementWasApplied(original: String, range: NSRange,
                                      replacement: String, observed: String?,
                                      allowFollowingInput: Bool = false) -> Bool {
        let originalString = original as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
              range.location <= originalString.length,
              range.length <= originalString.length - range.location,
              let observed else { return false }
        let expected = originalString.replacingCharacters(in: range, with: replacement)
        guard allowFollowingInput else { return observed == expected }
        let prefix = originalString.substring(to: range.location) + replacement
        let suffix = originalString.substring(from: range.location + range.length)
        return observed.hasPrefix(prefix) && observed.hasSuffix(suffix)
            && observed.utf16.count >= prefix.utf16.count + suffix.utf16.count
    }

    private func restoreSelectionIfUnchanged(_ element: AXUIElement, selectedRange: CFRange, original: CFRange) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return }
        var current = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &current),
              current.location == selectedRange.location, current.length == selectedRange.length else { return }
        var original = original
        if let range = AXValueCreate(.cfRange, &original) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, range)
        }
    }

    static func verifiedSuffixRange(text: String, selection: CFRange, expected: String) -> NSRange? {
        let string = text as NSString
        let count = expected.utf16.count
        guard count > 0, selection.length == 0, selection.location >= count,
              selection.location <= string.length else { return nil }
        let range = NSRange(location: selection.location - count, length: count)
        guard string.substring(with: range) == expected else { return nil }
        // A stale buffer must not match the tail of a larger word.
        if range.location > 0,
           let preceding = (string.substring(to: range.location)).last,
           preceding.isLetter || preceding.isNumber { return nil }
        return range
    }

    // MARK: - Pasteboard Save/Restore

    private func savePasteboard() -> [[(NSPasteboard.PasteboardType, Data)]] {
        TransientPasteboard.snapshot()
    }

    private func restorePasteboard(_ items: [[(NSPasteboard.PasteboardType, Data)]]) {
        TransientPasteboard.restore(items)
    }
}


/// One receipt per paste. Physical input can request confirmation before the
/// next key is passed on, and queued timer checks cannot complete it twice.
final class PasteConfirmation {
    private let applied: () -> Bool
    private let finish: (Bool) -> Void
    private var finished = false

    init(applied: @escaping () -> Bool, finish: @escaping (Bool) -> Void) {
        self.applied = applied
        self.finish = finish
    }

    /// Cancel selection preparation without authorizing a paste, even if the
    /// renderer has just acknowledged the range as a physical key arrives.
    func cancel() {
        guard !finished else { return }
        finished = true
        finish(false)
    }

    func check(final: Bool = false) {
        guard !finished else { return }
        let success = applied()
        guard success || final else { return }
        finished = true
        finish(success)
    }
}
