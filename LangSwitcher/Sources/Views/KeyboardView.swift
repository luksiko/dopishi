import SwiftUI

// MARK: - Keyboard Key Cap View
// Renders an authentic macOS keyboard key cap with optional pulse animation
// and action callback to demonstrate shortcut acceptance in the sandbox.

struct KeyCapView: View {
    let keySymbol: String
    let label: String?
    var isHighlighted: Bool = false
    var action: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 6) {
                Text(keySymbol)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                if let label = label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isHighlighted ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isHighlighted ? 1.5 : 1.0
                    )
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.12 : 0.05), radius: 2, x: 0, y: 1)
            .scaleEffect(isHighlighted ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Keyboard View
// Container showing the prompt and the primary acceptance shortcut (Tab / Enter).

struct KeyboardView: View {
    let keySymbol: String
    let promptText: String
    var isHighlighted: Bool = false
    var onAccept: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            KeyCapView(
                keySymbol: keySymbol,
                label: nil,
                isHighlighted: isHighlighted,
                action: onAccept
            )

            Text(promptText)
                .font(.caption)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
        }
    }
}
