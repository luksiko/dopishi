import SwiftUI

// MARK: - Smart Replies HUD View
// Floating non-activating panel presenting 3 quick reply pills (Affirmative, Deferral, Decline).

struct SmartRepliesHUDView: View {
    let replies: [SmartRepliesEngine.ReplyCandidate]
    let selectedIndex: Int
    let onSelect: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Replies")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 2)

            Divider()
                .frame(height: 16)

            HStack(spacing: 6) {
                ForEach(Array(replies.enumerated()), id: \.element.id) { idx, item in
                    let isHighlighted = idx == selectedIndex

                    Button(action: {
                        onSelect(item.text)
                    }) {
                        HStack(spacing: 5) {
                            Text(item.shortcut)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isHighlighted ? Color.white.opacity(0.3) : Color.accentColor.opacity(0.18))
                                .clipShape(RoundedRectangle(cornerRadius: 3))

                            Image(systemName: item.category.iconName)
                                .font(.system(size: 10))

                            Text(item.text)
                                .font(.system(size: 12, weight: isHighlighted ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isHighlighted ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .foregroundStyle(isHighlighted ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
