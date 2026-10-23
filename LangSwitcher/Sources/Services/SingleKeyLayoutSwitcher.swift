import Foundation
import Cocoa
import Carbon

// MARK: - Single Key Detector
/// Pure state detector for single-key modifier taps (e.g. Right Option, Right Command, Caps Lock)
final class SingleKeyDetector {
    
    var targetKey: LayoutSwitchKey = .disabled
    var maxTapDuration: TimeInterval = 0.45 // 450ms max between down and up
    var minTapDuration: TimeInterval = 0.01 // 10ms min to avoid hardware jitter
    
    private(set) var isKeyDown: Bool = false
    private(set) var keyDownTime: TimeInterval = 0
    private(set) var comboUsed: Bool = false
    private var lastTriggerTime: TimeInterval = 0
    
    func reset() {
        isKeyDown = false
        keyDownTime = 0
        comboUsed = false
    }
    
    /// Called when any regular key event occurs (e.g. keyDown or non-target modifier)
    func notifyOtherEventOccurred() {
        if isKeyDown {
            comboUsed = true
        }
    }
    
    /// Process a flagsChanged event
    /// - Returns: true if this event completes a valid single-key tap and should trigger a layout switch
    func handleModifierChange(
        keyCode: UInt16,
        flagsRaw: UInt,
        timestamp: TimeInterval
    ) -> Bool {
        guard targetKey != .disabled, let targetKeyCode = targetKey.keyCode else {
            return false
        }
        
        // Caps Lock special handling:
        // In macOS, pressing Caps Lock generates flagsChanged with keyCode 57
        if targetKey == .capsLock {
            if keyCode == targetKeyCode {
                if timestamp - lastTriggerTime > 0.2 { // 200ms debounce
                    lastTriggerTime = timestamp
                    return true
                }
            }
            return false
        }
        
        // Target modifier key changed
        if keyCode == targetKeyCode {
            let isDown: Bool
            if let mask = targetKey.deviceMask, (UInt32(flagsRaw) & mask) != 0 {
                isDown = true
            } else {
                isDown = isModifierDownFallback(flagsRaw: flagsRaw)
            }
            
            if isDown {
                // Key pressed down
                isKeyDown = true
                keyDownTime = timestamp
                comboUsed = false
                return false
            } else {
                // Key released
                let wasDown = isKeyDown
                let hadNoCombo = !comboUsed
                let duration = timestamp - keyDownTime
                reset()
                
                if wasDown && hadNoCombo && duration <= maxTapDuration && duration >= minTapDuration {
                    lastTriggerTime = timestamp
                    return true
                }
                return false
            }
        } else {
            // Another modifier changed while our target key was held down
            if isKeyDown {
                comboUsed = true
            }
            return false
        }
    }
    
    private func isModifierDownFallback(flagsRaw: UInt) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: flagsRaw)
        switch targetKey {
        case .rightOption, .leftOption:
            return flags.contains(.option)
        case .rightCommand, .leftCommand:
            return flags.contains(.command)
        case .rightShift, .leftShift:
            return flags.contains(.shift)
        case .rightControl, .leftControl:
            return flags.contains(.control)
        case .fn:
            return flags.contains(.function)
        default:
            return false
        }
    }
}

// MARK: - Single Key Layout Switcher
/// Listens globally for a single key press (e.g. Right Option, Caps Lock) and triggers layout switching
final class SingleKeyLayoutSwitcher {
    
    typealias SwitchAction = () -> Void
    
    private var action: SwitchAction?
    let detector = SingleKeyDetector()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private var flagsGlobalMonitor: Any?
    private var flagsLocalMonitor: Any?
    private var keyGlobalMonitor: Any?
    private var keyLocalMonitor: Any?
    private var mouseGlobalMonitor: Any?
    private var mouseLocalMonitor: Any?
    
    deinit {
        unregister()
    }
    
    /// Register a designated key for layout switching
    func register(key: LayoutSwitchKey, action: @escaping SwitchAction) {
        unregister()
        
        guard key != .disabled else { return }
        
        self.action = action
        detector.targetKey = key
        
        // First try creating a CGEventTap for zero latency and event consumption (Caps Lock)
        if !installEventTap() {
            NSLog("[LangSwitcher] SingleKeyLayoutSwitcher: CGEventTap not available, falling back to NSEvent monitors")
            installNSEventMonitors()
        }
    }
    
    /// Unregister all active monitors and event taps
    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                runLoopSource = nil
            }
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        
        if let m = flagsGlobalMonitor { NSEvent.removeMonitor(m); flagsGlobalMonitor = nil }
        if let m = flagsLocalMonitor { NSEvent.removeMonitor(m); flagsLocalMonitor = nil }
        if let m = keyGlobalMonitor { NSEvent.removeMonitor(m); keyGlobalMonitor = nil }
        if let m = keyLocalMonitor { NSEvent.removeMonitor(m); keyLocalMonitor = nil }
        if let m = mouseGlobalMonitor { NSEvent.removeMonitor(m); mouseGlobalMonitor = nil }
        if let m = mouseLocalMonitor { NSEvent.removeMonitor(m); mouseLocalMonitor = nil }
        
        action = nil
        detector.reset()
        detector.targetKey = .disabled
    }
    
    // MARK: - Event Tap
    
    private func installEventTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let switcher = Unmanaged<SingleKeyLayoutSwitcher>.fromOpaque(refcon).takeUnretainedValue()
            return switcher.handleCGEvent(proxy: proxy, type: type, event: event)
        }
        
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            return false
        }
        
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        
        self.eventTap = tap
        self.runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)

        // Install passive mouse monitors so clicks notify the detector without intercepting in CGEventTap
        if mouseGlobalMonitor == nil {
            let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            mouseGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
                self?.detector.notifyOtherEventOccurred()
            }
        }
        if mouseLocalMonitor == nil {
            let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            mouseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
                self?.detector.notifyOtherEventOccurred()
                return event
            }
        }
        
        NSLog("[LangSwitcher] SingleKeyLayoutSwitcher: CGEventTap installed successfully for key \(detector.targetKey.rawValue)")
        return true
    }
    
    private func handleCGEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        
        if type == .keyDown {
            detector.notifyOtherEventOccurred()
            return Unmanaged.passUnretained(event)
        }
        
        if type == .flagsChanged {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flagsRaw = UInt(event.flags.rawValue)
            let now = ProcessInfo.processInfo.systemUptime
            
            let shouldTrigger = detector.handleModifierChange(
                keyCode: keyCode,
                flagsRaw: flagsRaw,
                timestamp: now
            )
            
            // Caps Lock special handling: always consume the event to prevent OS caps-lock toggle
            if detector.targetKey == .capsLock && keyCode == 57 {
                if shouldTrigger {
                    DispatchQueue.main.async { [weak self] in
                        self?.action?()
                    }
                }
                return nil
            }
            
            if shouldTrigger {
                DispatchQueue.main.async { [weak self] in
                    self?.action?()
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    // MARK: - NSEvent Monitors Fallback
    
    private func installNSEventMonitors() {
        flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEventFlags(event)
        }
        
        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleNSEventFlags(event)
            return event
        }
        
        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.detector.notifyOtherEventOccurred()
        }
        
        keyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.detector.notifyOtherEventOccurred()
            return event
        }
        
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        mouseGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.detector.notifyOtherEventOccurred()
        }
        mouseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.detector.notifyOtherEventOccurred()
            return event
        }
    }
    
    private func handleNSEventFlags(_ event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let shouldTrigger = detector.handleModifierChange(
            keyCode: event.keyCode,
            flagsRaw: event.modifierFlags.rawValue,
            timestamp: now
        )
        if shouldTrigger {
            DispatchQueue.main.async { [weak self] in
                self?.action?()
            }
        }
    }
}
