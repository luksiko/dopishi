import Foundation
import AppKit

// MARK: - Inline Prediction Manager
// Detects and resolves conflicts with macOS 14+ Sonoma/Sequoia built-in inline predictive text.
// When Apple's inline text prediction is enabled, it renders conflicting gray ghost text
// at the caret in WebKit, Safari, Mail, and Notes, intercepting Space and Tab keys.

public enum InlinePredictionManager {

    /// Detects whether macOS built-in inline prediction is currently enabled.
    public static var isAutomaticInlinePredictionEnabled: Bool {
        if #available(macOS 14.0, *) {
            var exists: DarwinBoolean = false
            let val = CFPreferencesGetAppBooleanValue(
                "NSAutomaticInlinePredictionEnabled" as CFString,
                kCFPreferencesAnyApplication,
                &exists
            )
            if exists.boolValue {
                return val
            }
            // By default on macOS 14+ on supported devices, it is enabled unless explicitly turned off
            return true
        }
        return false
    }

    /// Disables macOS built-in inline text prediction globally.
    /// Equivalent to toggling off "Show inline predictive text" in System Settings -> Keyboard.
    @discardableResult
    public static func disableAutomaticInlinePrediction() -> Bool {
        CFPreferencesSetAppValue(
            "NSAutomaticInlinePredictionEnabled" as CFString,
            kCFBooleanFalse,
            kCFPreferencesAnyApplication
        )
        let synced = CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)

        // Also run `defaults write -g NSAutomaticInlinePredictionEnabled -bool false`
        // to propagate to cfprefsd daemon across all running applications.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "NSAutomaticInlinePredictionEnabled", "-bool", "false"]
        try? process.run()
        process.waitUntilExit()

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleKeyboardsSettingsChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return synced
    }

    /// Re-enables macOS built-in inline text prediction globally.
    @discardableResult
    public static func enableAutomaticInlinePrediction() -> Bool {
        CFPreferencesSetAppValue(
            "NSAutomaticInlinePredictionEnabled" as CFString,
            kCFBooleanTrue,
            kCFPreferencesAnyApplication
        )
        let synced = CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", "-g", "NSAutomaticInlinePredictionEnabled", "-bool", "true"]
        try? process.run()
        process.waitUntilExit()

        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("AppleKeyboardsSettingsChangedNotification"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return synced
    }
}
