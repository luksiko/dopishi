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
}

// MARK: - Accessibility Service
// Handles getting and replacing selected text via macOS Accessibility API & pasteboard

final class AccessibilityService {
    private var preparedElectronPID: pid_t?
    private var pendingPaste: PasteConfirmation?
    private var pendingSelection: PasteConfirmation?

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
    
    // MARK: - Selected Text Conversion
    
    /// Get selected text and replace it using clipboard-based approach.
    /// Returns false if no text was selected/copied.
    func getAndReplaceSelectedText(with converter: (String) -> String?) -> Bool {
        let pasteboard = NSPasteboard.general
        let savedContents = savePasteboard()
        
        // Copy selected text (⌘C)
        pasteboard.clearContents()
        simulateCopy()
        usleep(150_000) // 150ms — give target app time to process ⌘C
        
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
        pasteboard.clearContents()
        pasteboard.setString(convertedText, forType: .string)
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
        
        // Copy the selection
        pasteboard.clearContents()
        simulateCopy()
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
        pasteboard.clearContents()
        pasteboard.setString(convertedText, forType: .string)
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
        
        // Copy the selection
        pasteboard.clearContents()
        simulateCopy()
        usleep(150_000) // 150ms — give target app time to process ⌘C
        
        var selectedText = pasteboard.string(forType: .string) ?? ""
        if !selectedText.isEmpty && selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Only whitespace was selected (user had typed a trailing space). Extend selection one more word left!
            NSLog("[LangSwitcher] selectAndReplaceLastWord: only whitespace selected, extending selection left...")
            simulateSelectWordLeft()
            usleep(150_000)
            pasteboard.clearContents()
            simulateCopy()
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
        pasteboard.clearContents()
        pasteboard.setString(convertedText, forType: .string)
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
        event.post(tap: .cgAnnotatedSessionEventTap)
        
        NSLog("[LangSwitcher] Posted key event: key=0x\(String(virtualKey, radix: 16)), down=\(keyDown), mods=\(modifiers.rawValue)")
    }
    
    /// Simulate a full keystroke (key down + key up) with modifiers
    private func simulateKeystroke(virtualKey: CGKeyCode, modifiers: CGEventFlags = []) {
        postKeyEvent(virtualKey: virtualKey, keyDown: true, modifiers: modifiers)
        postKeyEvent(virtualKey: virtualKey, keyDown: false, modifiers: modifiers)
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
        simulateCopy()
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSLog("[LangSwitcher] pasteReplacingSelection: '\(text)'")
        simulatePaste()
    }

    /// Copy text to the clipboard without touching any app.
    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
    
    /// Captures the surrounding text before/after caret and identifies the focused field.
    func captureCaretContext(maxSurroundingLength: Int = 200) -> CaretContext? {
        guard let element = focusedTextElement(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        
        let bundleID = app.bundleIdentifier ?? "unknown"
        let pid = app.processIdentifier
        let elementHash = CFHash(element)
        let fieldID = "\(bundleID):\(pid):\(elementHash)"
        
        var rangeRef: CFTypeRef?
        var selectedRange = CFRange(location: 0, length: 0)
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            _ = AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange)
        }
        
        var selectedTextRef: CFTypeRef?
        var selectedText = ""
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
           let str = selectedTextRef as? String {
            selectedText = str
        }
        
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let fullText = valueRef as? String {
            return Self.makeCaretContext(fieldIdentifier: fieldID, text: fullText,
                                         selection: selectedRange, selectedText: selectedText,
                                         maxSurroundingLength: maxSurroundingLength)
        }
        
        return CaretContext(
            fieldIdentifier: fieldID,
            textBeforeCaret: "",
            textAfterCaret: "",
            selectedText: selectedText,
            caretLocation: selectedRange.location,
            fullTextLength: 0
        )
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
            selectedText: selectedText, caretLocation: caret, fullTextLength: count)
    }

    // MARK: - Caret Positioning
    
    /// Only return measured insertion bounds. Field bounds and mouse location
    /// are not cursor positions and must never anchor inline suggestions.
    func caretScreenRect() -> CGRect? {
        guard let element = focusedTextElement(), let primaryScreen = NSScreen.screens.first else { return nil }
        var selectedValue: CFTypeRef?
        var selectedRange: CFRange?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                         &selectedValue) == .success,
           let value = selectedValue, CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(value as! AXValue, .cfRange, &range) { selectedRange = range }
        }
        let caret = Self.resolveCaretBounds(selectedRange: selectedRange,
            primaryScreenMaxY: primaryScreen.frame.maxY,
            rangeBounds: { query in
                var query = query
                guard let value = AXValueCreate(.cfRange, &query) else { return nil }
                return self.parameterizedRect(element, attribute: kAXBoundsForRangeParameterizedAttribute as String,
                                              parameter: value)
            }, markerBounds: { self.selectedMarkerCaretBounds(element) })
        guard let caret, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(caret) }) else { return nil }
        return caret
    }

    /// Popup fallback only. This is deliberately never used for inline text.
    func focusedFieldScreenRect() -> CGRect? {
        guard let element = focusedTextElement(), let screen = NSScreen.screens.first else { return nil }
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

    private func focusedTextElement() -> AXUIElement? {
        prepareBrowserAccessibility()
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) != .success,
           let app = NSWorkspace.shared.frontmostApplication {
            AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                          kAXFocusedUIElementAttribute as CFString, &value)
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let root = value as! AXUIElement
        let deadline = ProcessInfo.processInfo.systemUptime + 0.04
        return Self.resolveFocusedTextNode(root: root, attributes: { element in
            var role: CFTypeRef?
            var subrole: CFTypeRef?
            var focused: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focused)
            return (role as? String, subrole as? String, (focused as? Bool) == true)
        }, focusedChild: { element in
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
    }

    /// Follow confirmed focus, including nested web editors, never a merely
    /// editable descendant. Bound the traversal and reject ambiguous focus.
    static func resolveFocusedTextNode<Node: Hashable>(
        root: Node, attributes: (Node) -> (role: String?, subrole: String?, focused: Bool),
        focusedChild: (Node) -> Node?, children: (Node) -> [Node],
        limit: Int = 128, shouldContinue: () -> Bool = { true }
    ) -> Node? {
        var pending: [(Node, Bool)] = [(root, true)]
        var visited: Set<Node> = []
        var result: Node?
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
            if AutoCorrectionGate.textInputRoles.contains(info.role ?? "") {
                if confirmed {
                    guard result == nil || result == node else { return nil }
                    result = node
                }
                continue
            }
            if let child = focusedChild(node), child != node {
                pending.append((child, true))
                continue
            }
            if ["AXGroup", "AXWebArea", "AXScrollArea", "AXSplitGroup"].contains(info.role ?? "") {
                pending.append(contentsOf: children(node).reversed().map { ($0, false) })
            }
        }
        return result
    }

    /// Electron documents this attribute for third-party assistive applications.
    /// Request once per active process, not on every keystroke. No permission is granted here.
    private func prepareBrowserAccessibility() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              preparedElectronPID != app.processIdentifier,
              let bundle = app.bundleURL,
              FileManager.default.fileExists(atPath: bundle.appendingPathComponent(
                "Contents/Frameworks/Electron Framework.framework").path), AXIsProcessTrusted() else { return }
        preparedElectronPID = app.processIdentifier
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                     "AXManualAccessibility" as CFString, kCFBooleanTrue)
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

    static func resolveCaretBounds(selectedRange: CFRange?, primaryScreenMaxY: CGFloat,
                                   rangeBounds: (CFRange) -> CGRect?, markerBounds: () -> CGRect?) -> CGRect? {
        if let range = selectedRange {
            guard range.location >= 0, range.length == 0 else { return nil }
            var queries = [range]
            if range.location > 0 { queries.append(CFRange(location: range.location - 1, length: 1)) }
            for query in queries {
                if let bounds = rangeBounds(query),
                   let caret = normalizedCaretBounds(bounds, primaryScreenMaxY: primaryScreenMaxY,
                                                     precedingCharacter: query.length == 1) { return caret }
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
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
              settable.boolValue else { return nil }
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
        guard !preferPasteInWebEditors || preparedElectronPID != target.processID else { return false }
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

    /// Fallback for automatic word correction in editors with ignored AX setters.
    /// Re-read the text and focus before selecting anything; never send backspaces.
    func pasteVerifiedSuffix(_ expected: String, with replacement: String, target: ReplacementTarget,
                             completion: @escaping (Bool) -> Void) {
        // A stop/restart may have cancelled the old correction session while
        // its clipboard receipt is still pending. Finalize it before replacing it.
        pendingSelection?.cancel()
        pendingPaste?.check(final: true)
        guard isCurrentReplacementTarget(target) else { completion(false); return }
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
        if original.length == 0 {
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
            let pasteboard = NSPasteboard.general
            let saved = savePasteboard()
            pasteboard.clearContents()
            guard pasteboard.setString(replacement, forType: .string) else {
                restorePasteboard(saved)
                restoreSelectionIfUnchanged(element, selectedRange: range, original: fallbackCaret)
                completion(false); return
            }
            pasteboard.setString("", forType: .init("org.nspasteboard.TransientType"))
            pasteboard.setString("", forType: .init("org.nspasteboard.AutoGeneratedType"))
            let pasteboardRevision = pasteboard.changeCount
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
                for event in [down, up] {
                    event.flags = .maskCommand
                    event.setIntegerValueField(.eventSourceUserData, value: AutoCorrectionService.syntheticEventMarker)
                    event.post(tap: .cgAnnotatedSessionEventTap)
                }
            })
            guard sent else {
                if pasteboard.changeCount == pasteboardRevision {
                    if saved.isEmpty { pasteboard.clearContents() } else { restorePasteboard(saved) }
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
                var observed: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &observed)
                if !applied, observed as? String == text, self.isCurrentReplacementTarget(target) {
                    self.restoreSelectionIfUnchanged(element, selectedRange: range, original: fallbackCaret)
                }
                // Restore only our clipboard contents; preserve any subsequent user copy.
                if pasteboard.changeCount == pasteboardRevision {
                    if saved.isEmpty { pasteboard.clearContents() } else { self.restorePasteboard(saved) }
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
        let pasteboard = NSPasteboard.general
        return pasteboard.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []
    }
    
    private func restorePasteboard(_ items: [[(NSPasteboard.PasteboardType, Data)]]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
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
