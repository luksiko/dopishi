import Foundation
import Carbon
import Cocoa

// MARK: - Hotkey Manager
// Registers and manages global keyboard shortcuts
// Supports both regular hotkeys (modifier+key) and double-tap modifier keys (e.g. double Shift)

final class HotkeyManager {
    
    typealias HotkeyAction = () -> Void
    
    private var action: HotkeyAction?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var flagsGlobalMonitor: Any?
    private var flagsLocalMonitor: Any?
    
    // Double-tap detection state
    private var doubleTapDetector = DoubleTapDetector()
    
    // Configuration
    private(set) var isDoubleTapMode: Bool = false
    private(set) var doubleTapModifier: DoubleTapModifier = .shift

    /// Backwards compatibility property
    var isDoubleShiftMode: Bool {
        isDoubleTapMode && doubleTapModifier == .shift
    }
    
    /// Plain Space keycode on Apple keyboards
    static let spaceKeyCode: UInt16 = 0x31
    
    deinit {
        unregister()
    }
    
    // MARK: - Double-Tap Registration
    
    /// Register double-shift as the hotkey trigger (convenience)
    func registerDoubleShift(action: @escaping HotkeyAction) {
        registerDoubleTap(modifier: .shift, action: action)
    }

    /// Register double-tap of a modifier key (Shift ⇧⇧ or Option ⌥⌥) as the hotkey trigger
    func registerDoubleTap(
        modifier: DoubleTapModifier,
        action: @escaping HotkeyAction
    ) {
        unregister()
        self.action = action
        self.isDoubleTapMode = true
        self.doubleTapModifier = modifier
        doubleTapDetector = DoubleTapDetector()
        
        // Monitor flagsChanged events for modifier key detection
        flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        
        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        
        // We also need to cancel a pending double-tap when any key is pressed
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.doubleTapDetector.handleOtherKeyDown(
                at: ProcessInfo.processInfo.systemUptime)
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.doubleTapDetector.handleOtherKeyDown(
                at: ProcessInfo.processInfo.systemUptime)
            return event
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Only the tracked modifier pressed, no other modifiers.
        // Command/Control always disqualify; the other tracked modifier
        // (Shift vs Option) also disqualifies — that's a combo, not a tap.
        let otherModifiers = flags.subtracting(.capsLock)
        let onlyTrackedModifier = otherModifiers == doubleTapModifier.eventFlag
        
        if onlyTrackedModifier {
            // Tracked modifier just pressed down (possibly with Caps Lock on)
            let now = ProcessInfo.processInfo.systemUptime
            if doubleTapDetector.handleModifierDown(doubleTapModifier, at: now) {
                // Double tap detected!
                action?()
            }
        } else if !flags.isEmpty {
            // Some other modifier involved — cancel any pending pair
            doubleTapDetector.reset()
        }
    }
    
    // MARK: - Regular Hotkey Registration
    
    /// Register a regular global hotkey (modifier + key)
    func register(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        action: @escaping HotkeyAction
    ) {
        unregister()
        self.action = action
        self.isDoubleTapMode = false
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let targetMods = modifiers.intersection(.deviceIndependentFlagsMask)
            
            if event.keyCode == keyCode && eventMods == targetMods {
                self.action?()
            }
        }
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let targetMods = modifiers.intersection(.deviceIndependentFlagsMask)
            
            if event.keyCode == keyCode && eventMods == targetMods {
                self.action?()
                return nil
            }
            return event
        }
    }
    
    /// Unregister all monitors
    func unregister() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = flagsGlobalMonitor { NSEvent.removeMonitor(m); flagsGlobalMonitor = nil }
        if let m = flagsLocalMonitor { NSEvent.removeMonitor(m); flagsLocalMonitor = nil }
        action = nil
        isDoubleTapMode = false
        doubleTapDetector.reset()
    }
    
    // MARK: - Space Detection Helper
    
    /// Pure predicate: is this key event a plain word-separating Space?
    /// Excludes modified Spaces (⌘Space = Spotlight, ⌥Space = non-breaking
    /// space, ⌃Space = input switcher) and key-repeat events from held Space.
    /// Shift+Space still counts — it inserts a word separator in most apps.
    static func isPlainSpaceEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> Bool {
        guard keyCode == spaceKeyCode, !isRepeat else { return false }
        let mods = modifierFlags.intersection(.deviceIndependentFlagsMask)
        return mods.intersection([.command, .option, .control]).isEmpty
    }
    
    // MARK: - Display Helpers
    
    static func modifierFlagsToString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
    
    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
            0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
            0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
            0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
            0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x28: "K", 0x2C: "/", 0x2D: "N",
            0x2E: "M", 0x31: "Space", 0x24: "Return", 0x30: "Tab",
            0x33: "Delete", 0x35: "Escape",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }
}
