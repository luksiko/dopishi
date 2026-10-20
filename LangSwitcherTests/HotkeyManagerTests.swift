import XCTest
import Cocoa
@testable import LangSwitcher

final class HotkeyManagerTests: XCTestCase {
    
    // MARK: - DoubleTapDetector
    //
    // Pure state machine extracted from HotkeyManager so the double-tap
    // rules (interval, modifier isolation, Option+key cancellation) are
    // testable without NSEvent monitors.
    
    private var detector = DoubleTapDetector()
    
    override func setUp() {
        super.setUp()
        detector = DoubleTapDetector()
    }
    
    private func tap(_ modifier: DoubleTapModifier, at time: TimeInterval) -> Bool {
        detector.handleModifierDown(modifier, at: time)
    }
    
    func testDoubleShiftWithinIntervalTriggers() {
        XCTAssertFalse(tap(.shift, at: 10.0))
        XCTAssertTrue(tap(.shift, at: 10.2))
    }
    
    func testDoubleOptionWithinIntervalTriggers() {
        XCTAssertFalse(tap(.option, at: 5.0))
        XCTAssertTrue(tap(.option, at: 5.3))
    }
    
    func testSecondTapBeyondIntervalDoesNotTrigger() {
        _ = tap(.shift, at: 10.0)
        XCTAssertFalse(tap(.shift, at: 10.5))
    }
    
    func testSecondTapJustUnderIntervalTriggers() {
        _ = tap(.shift, at: 10.0)
        XCTAssertTrue(tap(.shift, at: 10.399))
    }
    
    func testMixedModifiersSwitchArmsNewModifier() {
        // Shift ... Option is not a double-tap of either key, but the
        // Option tap re-arms the window: the next Option tap completes
        // an Option pair (Shift ... Option ... Option).
        _ = tap(.shift, at: 10.0)
        XCTAssertFalse(tap(.option, at: 10.1))
        XCTAssertTrue(tap(.option, at: 10.2))
    }
    
    func testInterleavedShiftOptionShiftDoesNotTrigger() {
        // Alternating modifiers must never fire
        _ = tap(.shift, at: 10.0)
        XCTAssertFalse(tap(.option, at: 10.1))
        XCTAssertFalse(tap(.shift, at: 10.2))
    }
    
    func testThirdConsecutiveTapDoesNotRetrigger() {
        // ⇧⇧⇧ held/rattled must fire once, not twice
        _ = tap(.shift, at: 10.0)
        XCTAssertTrue(tap(.shift, at: 10.2))
        XCTAssertFalse(tap(.shift, at: 10.4))
    }
    
    func testResetCancelsPendingTap() {
        _ = tap(.shift, at: 10.0)
        detector.reset()
        XCTAssertFalse(tap(.shift, at: 10.1))
    }
    
    func testKeydownCancelsPendingTap() {
        // Shift, then a letter key, then Shift again: not a double-tap
        _ = tap(.shift, at: 10.0)
        detector.handleOtherKeyDown(at: 10.05)
        XCTAssertFalse(tap(.shift, at: 10.1))
    }
    
    func testKeydownBetweenTapsThenFreshPairTriggers() {
        _ = tap(.shift, at: 10.0)
        detector.handleOtherKeyDown(at: 10.05)
        XCTAssertFalse(tap(.shift, at: 10.1))
        // A clean pair afterwards still works
        _ = tap(.shift, at: 11.0)
        XCTAssertTrue(tap(.shift, at: 11.2))
    }
    
    func testFirstTapEverDoesNotTrigger() {
        XCTAssertFalse(tap(.shift, at: 0.05))
    }
    
    func testFirstTapAtTimeZeroDoesNotTrigger() {
        // The armed flag is the modifier, not a time sentinel —
        // taps at systemUptime ≈ 0 must behave like any other time
        XCTAssertFalse(tap(.option, at: 0.0))
        XCTAssertTrue(tap(.option, at: 0.1))
    }
    
    func testOptionTapDoesNotLeakIntoShiftPair() {
        _ = tap(.option, at: 10.0)
        XCTAssertFalse(tap(.shift, at: 10.1))
    }
    
    func testCustomIntervalRespected() {
        var slow = DoubleTapDetector(doubleTapInterval: 0.6)
        _ = slow.handleModifierDown(.option, at: 10.0)
        XCTAssertTrue(slow.handleModifierDown(.option, at: 10.5))
        
        var fast = DoubleTapDetector(doubleTapInterval: 0.2)
        _ = fast.handleModifierDown(.option, at: 10.0)
        XCTAssertFalse(fast.handleModifierDown(.option, at: 10.3))
    }
    
    func testNonMonotonicTimeDoesNotTrigger() {
        // Defensive: systemUptime should never go backwards
        _ = tap(.shift, at: 10.5)
        XCTAssertFalse(tap(.shift, at: 10.3))
    }
    
    // MARK: - DoubleTapModifier helpers
    
    func testDoubleTapModifierEventFlags() {
        XCTAssertEqual(DoubleTapModifier.shift.eventFlag, .shift)
        XCTAssertEqual(DoubleTapModifier.option.eventFlag, .option)
    }
    
    func testDoubleTapModifierDisplayStrings() {
        XCTAssertEqual(DoubleTapModifier.shift.displayString, "⇧⇧ (Double Shift)")
        XCTAssertEqual(DoubleTapModifier.option.displayString, "⌥⌥ (Double Option)")
    }
    
    // MARK: - isPlainSpaceEvent
    
    func testPlainSpaceTriggers() {
        XCTAssertTrue(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x31, modifierFlags: [], isRepeat: false))
    }
    
    func testSpaceWithShiftStillTriggers() {
        // Shift+Space still inserts a word separator in most apps
        XCTAssertTrue(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x31, modifierFlags: .shift, isRepeat: false))
    }
    
    func testSpaceWithCommandIgnored() {
        XCTAssertFalse(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x31, modifierFlags: .command, isRepeat: false))
    }
    
    func testSpaceWithOptionIgnored() {
        // Option+Space types a non-breaking space — not a word boundary
        XCTAssertFalse(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x31, modifierFlags: .option, isRepeat: false))
    }
    
    func testSpaceWithControlIgnored() {
        XCTAssertFalse(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x31, modifierFlags: .control, isRepeat: false))
    }
    
    func testSpaceRepeatIgnored() {
        XCTAssertFalse(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x31, modifierFlags: [], isRepeat: true))
    }
    
    func testReturnIsNotSpace() {
        XCTAssertFalse(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x24, modifierFlags: [], isRepeat: false))
    }
    
    func testOtherKeyIsNotSpace() {
        XCTAssertFalse(HotkeyManager.isPlainSpaceEvent(
            keyCode: 0x00, modifierFlags: [], isRepeat: false))
    }
}
