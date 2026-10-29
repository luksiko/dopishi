import Foundation

// MARK: - App Completion Mode
// Controls how AI autocompletion and suggestions behave for a specific application.

enum AppCompletionMode: String, Codable, CaseIterable, Identifiable {
    case automatic = "automatic"     // Default: suggestions appear automatically as you type
    case manualOnly = "manualOnly"   // Shortcut only: suggestions do not appear automatically; invoked explicitly
    case disabled = "disabled"       // Completely disabled: no suggestions, no background AI inference

    var id: String { rawValue }
}

// MARK: - App AI Settings
// Stores per-application custom instructions, vocabulary keywords, and AI completion mode.

struct AppAISettings: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var appName: String
    var customInstructions: String
    var customVocabulary: [String]
    var completionMode: AppCompletionMode

    /// Backward compatibility accessor for legacy callers
    var isAIEnabled: Bool {
        get { completionMode != .disabled }
        set { completionMode = newValue ? .automatic : .disabled }
    }

    enum CodingKeys: String, CodingKey {
        case bundleID
        case appName
        case customInstructions
        case customVocabulary
        case completionMode
        case isAIEnabled
    }

    init(
        bundleID: String,
        appName: String,
        customInstructions: String = "",
        customVocabulary: [String] = [],
        completionMode: AppCompletionMode = .automatic
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.customInstructions = customInstructions
        self.customVocabulary = customVocabulary
        self.completionMode = completionMode
    }

    init(
        bundleID: String,
        appName: String,
        customInstructions: String = "",
        customVocabulary: [String] = [],
        isAIEnabled: Bool
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.customInstructions = customInstructions
        self.customVocabulary = customVocabulary
        self.completionMode = isAIEnabled ? .automatic : .disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bundleID = try container.decode(String.self, forKey: .bundleID)
        self.appName = try container.decode(String.self, forKey: .appName)
        self.customInstructions = try container.decodeIfPresent(String.self, forKey: .customInstructions) ?? ""
        self.customVocabulary = try container.decodeIfPresent([String].self, forKey: .customVocabulary) ?? []

        if let mode = try container.decodeIfPresent(AppCompletionMode.self, forKey: .completionMode) {
            self.completionMode = mode
        } else if let legacyEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAIEnabled) {
            self.completionMode = legacyEnabled ? .automatic : .disabled
        } else {
            self.completionMode = .automatic
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(appName, forKey: .appName)
        try container.encode(customInstructions, forKey: .customInstructions)
        try container.encode(customVocabulary, forKey: .customVocabulary)
        try container.encode(completionMode, forKey: .completionMode)
        try container.encode(isAIEnabled, forKey: .isAIEnabled)
    }
}
