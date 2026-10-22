import Foundation
import AppKit

// MARK: - Attention Center
// Monitors system and application state for issues that interfere with autocompletion
// and typing (e.g. conflicting macOS predictions, missing permissions, missing models).

public enum AttentionIssueSeverity: Int, Comparable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: AttentionIssueSeverity, rhs: AttentionIssueSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AttentionIssueType: String, CaseIterable {
    case accessibilityPermission
    case inlinePredictionConflict
    case noModel
    case screenRecordingPermission
    case clipboardContextOff
}

public struct AttentionIssue: Identifiable, Equatable {
    public let id: AttentionIssueType
    public let severity: AttentionIssueSeverity
    public let titleKey: String
    public let descriptionKey: String
    public let actionTitleKey: String

    public init(
        id: AttentionIssueType,
        severity: AttentionIssueSeverity,
        titleKey: String,
        descriptionKey: String,
        actionTitleKey: String
    ) {
        self.id = id
        self.severity = severity
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.actionTitleKey = actionTitleKey
    }
}

@MainActor
public final class AttentionCenter: ObservableObject {
    public static let shared = AttentionCenter()

    @Published public private(set) var activeIssues: [AttentionIssue] = []

    public var hasActiveIssues: Bool {
        !activeIssues.isEmpty
    }

    public var hasWarningOrCriticalIssues: Bool {
        activeIssues.contains { $0.severity >= .warning }
    }

    public var maxSeverity: AttentionIssueSeverity? {
        activeIssues.map(\.severity).max()
    }

    public init() {
        refreshIssues()
    }

    public func refreshIssues(
        isAccessibilityTrusted: (() -> Bool)? = nil,
        isInlinePredictionEnabled: (() -> Bool)? = nil,
        hasInstalledModels: (() -> Bool)? = nil,
        hasScreenRecordingPermission: (() -> Bool)? = nil
    ) {
        var issues: [AttentionIssue] = []

        // 1. Accessibility Permission (Critical)
        let trusted = isAccessibilityTrusted?() ?? AXIsProcessTrusted()
        if !trusted {
            issues.append(AttentionIssue(
                id: .accessibilityPermission,
                severity: .critical,
                titleKey: "attention.accessibility.title",
                descriptionKey: "attention.accessibility.desc",
                actionTitleKey: "attention.accessibility.action"
            ))
        }

        // 2. macOS Inline Prediction Conflict (Warning)
        let inlineConflict = isInlinePredictionEnabled?() ?? InlinePredictionManager.isAutomaticInlinePredictionEnabled
        if inlineConflict {
            issues.append(AttentionIssue(
                id: .inlinePredictionConflict,
                severity: .warning,
                titleKey: "attention.inlinePredictionConflict.title",
                descriptionKey: "attention.inlinePredictionConflict.desc",
                actionTitleKey: "attention.inlinePredictionConflict.action"
            ))
        }

        // 3. Missing AI Model when AI is enabled (Warning)
        let aiEnabled = SettingsManager.shared.aiPredictiveEnabled
        let hasModels = hasInstalledModels?() ?? (
            AIModelManager.shared.activeModelPath != nil ||
            RecommendedAIModel.allModels.contains { AIModelManager.shared.isDownloaded(model: $0) }
        )
        if aiEnabled && !hasModels {
            issues.append(AttentionIssue(
                id: .noModel,
                severity: .warning,
                titleKey: "attention.noModel.title",
                descriptionKey: "attention.noModel.desc",
                actionTitleKey: "attention.noModel.action"
            ))
        }

        // 4. Screen Recording Permission (Info, if explicitly reported missing)
        if let hasScreen = hasScreenRecordingPermission?(), !hasScreen {
            issues.append(AttentionIssue(
                id: .screenRecordingPermission,
                severity: .info,
                titleKey: "attention.screenRecording.title",
                descriptionKey: "attention.screenRecording.desc",
                actionTitleKey: "attention.screenRecording.action"
            ))
        }

        self.activeIssues = issues
    }

    public func resolve(issue: AttentionIssueType) {
        switch issue {
        case .inlinePredictionConflict:
            InlinePredictionManager.disableAutomaticInlinePrediction()
            refreshIssues()
        case .accessibilityPermission:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case .noModel:
            if let controller = StatusBarController.shared {
                controller.openSettings()
            } else {
                NotificationCenter.default.post(name: StatusBarController.openSettingsNotification, object: nil)
            }
        case .screenRecordingPermission:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .clipboardContextOff:
            SettingsManager.shared.aiPredictiveEnabled = true
            refreshIssues()
        }
    }
}
