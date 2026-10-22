import SwiftUI

// MARK: - Word Alternatives HUD View
// Floating carousel presenting alternative completions triggered by Option+Down (⌥↓).

struct WordAlternativesHUDView: View {
    let alternatives: [WordAlternativesEngine.Alternative]
    let selectedIndex: Int
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("⌥↓")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 2)

            Divider()
                .frame(height: 16)

            HStack(spacing: 6) {
                ForEach(Array(alternatives.enumerated()), id: \.element.id) { idx, item in
                    let isHighlighted = idx == selectedIndex

                    Button(action: {
                        onSelect(item.text)
                    }) {
                        HStack(spacing: 4) {
                            Text(item.shortcut)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isHighlighted ? Color.accentColor : Color.accentColor.opacity(0.18))
                                .foregroundStyle(isHighlighted ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(item.text)
                                .font(.system(size: 12, weight: isHighlighted ? .semibold : .medium))
                                .foregroundStyle(isHighlighted ? .white : .primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(isHighlighted ? Color.accentColor.opacity(0.85) : Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}
