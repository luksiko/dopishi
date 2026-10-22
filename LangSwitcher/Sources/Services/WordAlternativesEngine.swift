import Foundation

// MARK: - Word Alternatives Engine
// Generates diverse branch alternatives when inline ghost text is visible,
// allowing the user to press ⌥↓ to choose alternative completions.

public struct WordAlternativesEngine {

    public struct Alternative: Identifiable, Equatable, Sendable {
        public let id: Int
        public let text: String
        public let shortcut: String

        public init(id: Int, text: String) {
            self.id = id
            self.text = text
            self.shortcut = "\(id)"
        }
    }

    /// Derives alternative completion branches filtering out the currently presented suggestion.
    public static func alternatives(
        currentSuggestion: String,
        candidates: [String],
        limit: Int = 4
    ) -> [Alternative] {
        var results: [String] = []
        let currentNormalized = currentSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for cand in candidates {
            let trimmed = cand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.lowercased() != currentNormalized else { continue }

            if !results.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
                results.append(trimmed)
            }
            if results.count >= limit { break }
        }

        return results.enumerated().map { index, text in
            Alternative(id: index + 1, text: text)
        }
    }
}
