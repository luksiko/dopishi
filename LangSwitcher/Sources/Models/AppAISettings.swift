import Foundation

// MARK: - App AI Settings
// Stores per-application custom instructions, vocabulary keywords, and AI autocompletion toggles.

struct AppAISettings: Codable, Identifiable, Equatable {
    var id: String { bundleID }
    var bundleID: String
    var appName: String
    var customInstructions: String
    var customVocabulary: [String]
    var isAIEnabled: Bool
    
    init(
        bundleID: String,
        appName: String,
        customInstructions: String = "",
        customVocabulary: [String] = [],
        isAIEnabled: Bool = true
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.customInstructions = customInstructions
        self.customVocabulary = customVocabulary
        self.isAIEnabled = isAIEnabled
    }
}
