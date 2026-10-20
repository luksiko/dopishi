import Foundation
import Cocoa

// MARK: - Double-Tap Modifier Detection
//
// Pure state machine for detecting double-taps of a modifier key
// (double Shift ⇧⇧ or double Option ⌥⌥) — extracted from HotkeyManager
// so the timing and cancellation rules are unit-testable without
// NSEvent monitors.

/// Which modifier key double-tap detection is configured for.
enum DoubleTapModifier: Int, CaseIterable, Codable {
    case shift = 0
    case option = 1

    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .option: return .option
        }
    }

    var displayString: String {
        switch self {
        case .shift: return "⇧⇧ (Double Shift)"
        case .option: return "⌥⌥ (Double Option)"
        }
    }
}

/// Detects double-taps of a single modifier key (Shift or Option).
///
/// Rules:
/// - Two presses of the same modifier within `doubleTapInterval` trigger.
/// - Pressing any other key in between cancels the pending pair.
/// - Pressing a *different* modifier does not trigger; it re-arms the
///   pair window from that press (Shift … Option … Option is a valid
///   Option pair, Shift … Option … Shift never fires).
/// - A pending pair is one-shot: after firing, a fresh pair is required.
struct DoubleTapDetector {
    let doubleTapInterval: TimeInterval

    // `lastTapModifier != nil` means a first tap is pending.
    // The modifier is the armed flag, so time zero works like any other.
    private var lastTapTime: TimeInterval = 0
    private var lastTapModifier: DoubleTapModifier?

    init(doubleTapInterval: TimeInterval = 0.4) {
        self.doubleTapInterval = doubleTapInterval
    }

    /// Record a modifier press. Returns true when a double-tap is detected.
    mutating func handleModifierDown(
        _ modifier: DoubleTapModifier,
        at time: TimeInterval
    ) -> Bool {
        if lastTapModifier == modifier,
           time >= lastTapTime,
           time - lastTapTime < doubleTapInterval {
            // Second press of the pair — fire once and disarm.
            lastTapModifier = nil
            return true
        }
        // First press (or a different modifier / expired window): re-arm.
        lastTapTime = time
        lastTapModifier = modifier
        return false
    }

    /// Any other key press cancels a pending pair.
    mutating func handleOtherKeyDown(at time: TimeInterval) {
        lastTapModifier = nil
    }

    /// Cancel any pending pair (e.g. another modifier got involved).
    mutating func reset() {
        lastTapModifier = nil
    }
}
