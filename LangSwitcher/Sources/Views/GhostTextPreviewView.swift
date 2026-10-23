import SwiftUI

// MARK: - Ghost Text Preview View
// Renders the inline completion tail (ghost text) directly adjacent to the text caret.

struct GhostTextPreviewView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.55))
    }
}
