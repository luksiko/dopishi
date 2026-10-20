import SwiftUI

// MARK: - Ghost Text Preview View
// Renders the inline completion tail (ghost text) directly adjacent to the text caret.

struct GhostTextPreviewView: View {
    let text: String
    
    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.65))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.04))
                )
        }
    }
}
