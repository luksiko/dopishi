import XCTest
@testable import LangSwitcher

final class SingleKeyLayoutSwitcherTests: XCTestCase {
    
    // MARK: - SingleKeyDetector Tests
    
    func testCleanTapRightOptionTriggers() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightOption
        
        let t0: TimeInterval = 100.0
        // Key down (mask 0x0040 is present)
        let downTrigger = detector.handleModifierChange(
            keyCode: 61,
            flagsRaw: 0x0040,
            timestamp: t0
        )
        XCTAssertFalse(downTrigger, "Modifier down should not trigger immediately")
        XCTAssertTrue(detector.isKeyDown)
        
        // Key up 80ms later (mask 0x0040 is cleared)
        let t1: TimeInterval = 100.08
        let upTrigger = detector.handleModifierChange(
            keyCode: 61,
            flagsRaw: 0,
            timestamp: t1
        )
        XCTAssertTrue(upTrigger, "Clean tap within maxTapDuration should trigger")
        XCTAssertFalse(detector.isKeyDown)
    }
    
    func testHoldTooLongDoesNotTrigger() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightOption
        
        // Key down
        _ = detector.handleModifierChange(keyCode: 61, flagsRaw: 0x0040, timestamp: 100.0)
        
        // Key up 600ms later (> maxTapDuration 450ms)
        let upTrigger = detector.handleModifierChange(keyCode: 61, flagsRaw: 0, timestamp: 100.6)
        XCTAssertFalse(upTrigger, "Holding modifier longer than maxTapDuration must not trigger")
    }
    
    func testComboWithOtherKeyDoesNotTrigger() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightOption
        
        // Key down
        _ = detector.handleModifierChange(keyCode: 61, flagsRaw: 0x0040, timestamp: 100.0)
        
        // Another key (e.g. 'A' or 'Tab') is pressed during hold
        detector.notifyOtherEventOccurred()
        XCTAssertTrue(detector.comboUsed)
        
        // Key up
        let upTrigger = detector.handleModifierChange(keyCode: 61, flagsRaw: 0, timestamp: 100.1)
        XCTAssertFalse(upTrigger, "Modifier used in combination with another key must not trigger")
    }
    
    func testComboWithAnotherModifierDoesNotTrigger() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightOption
        
        // Right Option down
        _ = detector.handleModifierChange(keyCode: 61, flagsRaw: 0x0040, timestamp: 100.0)
        
        // Shift modifier changes while Option is down (keyCode 56)
        _ = detector.handleModifierChange(keyCode: 56, flagsRaw: 0x0040 | 0x0002, timestamp: 100.05)
        XCTAssertTrue(detector.comboUsed)
        
        // Right Option up
        let upTrigger = detector.handleModifierChange(keyCode: 61, flagsRaw: 0x0002, timestamp: 100.1)
        XCTAssertFalse(upTrigger, "Another modifier pressed during hold must prevent trigger")
    }
    
    func testDisabledTargetDoesNotTrigger() {
        let detector = SingleKeyDetector()
        detector.targetKey = .disabled
        
        let down = detector.handleModifierChange(keyCode: 61, flagsRaw: 0x0040, timestamp: 100.0)
        let up = detector.handleModifierChange(keyCode: 61, flagsRaw: 0, timestamp: 100.05)
        
        XCTAssertFalse(down)
        XCTAssertFalse(up)
    }
    
    func testCapsLockTriggerAndDebounce() {
        let detector = SingleKeyDetector()
        detector.targetKey = .capsLock
        
        // First Caps Lock press (keyCode 57)
        let trigger1 = detector.handleModifierChange(keyCode: 57, flagsRaw: 0, timestamp: 100.0)
        XCTAssertTrue(trigger1, "Caps lock press should trigger")
        
        // Rapid bounce (50ms later)
        let trigger2 = detector.handleModifierChange(keyCode: 57, flagsRaw: 0, timestamp: 100.05)
        XCTAssertFalse(trigger2, "Debounce should suppress rapid bounce")
        
        // Subsequent press after debounce period (300ms later)
        let trigger3 = detector.handleModifierChange(keyCode: 57, flagsRaw: 0, timestamp: 100.35)
        XCTAssertTrue(trigger3, "Subsequent Caps Lock after debounce must trigger")
    }
    
    func testRightCommandTap() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightCommand
        
        // Right Command down (mask 0x0010, keyCode 54)
        _ = detector.handleModifierChange(keyCode: 54, flagsRaw: 0x0010, timestamp: 200.0)
        // Right Command up
        let trigger = detector.handleModifierChange(keyCode: 54, flagsRaw: 0, timestamp: 200.08)
        XCTAssertTrue(trigger, "Right Command clean tap should trigger")
    }
    
    func testRightShiftTap() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightShift
        
        // Right Shift down (mask 0x0004, keyCode 60)
        _ = detector.handleModifierChange(keyCode: 60, flagsRaw: 0x0004, timestamp: 300.0)
        // Right Shift up
        let trigger = detector.handleModifierChange(keyCode: 60, flagsRaw: 0, timestamp: 300.09)
        XCTAssertTrue(trigger, "Right Shift clean tap should trigger")
    }
    
    func testFnKeyTap() {
        let detector = SingleKeyDetector()
        detector.targetKey = .fn
        
        // Fn down (NSEvent.ModifierFlags.function = 1 << 23 = 0x00800000, keyCode 63)
        let fnFlags: UInt = NSEvent.ModifierFlags.function.rawValue
        _ = detector.handleModifierChange(keyCode: 63, flagsRaw: fnFlags, timestamp: 400.0)
        XCTAssertTrue(detector.isKeyDown)
        
        // Fn up
        let trigger = detector.handleModifierChange(keyCode: 63, flagsRaw: 0, timestamp: 400.1)
        XCTAssertTrue(trigger, "Fn clean tap should trigger")
    }
    
    func testMouseClickCancelsModifierTap() {
        let detector = SingleKeyDetector()
        detector.targetKey = .rightOption
        
        // Right Option down
        _ = detector.handleModifierChange(keyCode: 61, flagsRaw: 0x0040, timestamp: 500.0)
        // Mouse click occurs during hold
        detector.notifyOtherEventOccurred()
        XCTAssertTrue(detector.comboUsed)
        
        // Right Option up
        let trigger = detector.handleModifierChange(keyCode: 61, flagsRaw: 0, timestamp: 500.1)
        XCTAssertFalse(trigger, "Mouse click during modifier hold must cancel single-key trigger")
    }
    
    // MARK: - LayoutSwitchKey Enum Tests
    
    func testLayoutSwitchKeyCodable() throws {
        for key in LayoutSwitchKey.allCases {
            let data = try JSONEncoder().encode(key)
            let decoded = try JSONDecoder().decode(LayoutSwitchKey.self, from: data)
            XCTAssertEqual(key, decoded)
        }
    }
    
    func testLayoutSwitchKeyKeyCodes() {
        XCTAssertNil(LayoutSwitchKey.disabled.keyCode)
        XCTAssertEqual(LayoutSwitchKey.rightOption.keyCode, 61)
        XCTAssertEqual(LayoutSwitchKey.rightCommand.keyCode, 54)
        XCTAssertEqual(LayoutSwitchKey.rightShift.keyCode, 60)
        XCTAssertEqual(LayoutSwitchKey.rightControl.keyCode, 62)
        XCTAssertEqual(LayoutSwitchKey.capsLock.keyCode, 57)
        XCTAssertEqual(LayoutSwitchKey.leftOption.keyCode, 58)
        XCTAssertEqual(LayoutSwitchKey.leftControl.keyCode, 59)
        XCTAssertEqual(LayoutSwitchKey.leftCommand.keyCode, 55)
        XCTAssertEqual(LayoutSwitchKey.leftShift.keyCode, 56)
        XCTAssertEqual(LayoutSwitchKey.fn.keyCode, 63)
    }
    
    @MainActor
    func testLayoutSwitchKeyDisplayNames() {
        for key in LayoutSwitchKey.allCases {
            XCTAssertFalse(key.displayName.isEmpty)
        }
    }
}
