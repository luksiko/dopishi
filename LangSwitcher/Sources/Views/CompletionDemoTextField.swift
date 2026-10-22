import SwiftUI
import AppKit

// MARK: - Completion Demo View
// An interactive sandbox inside settings that allows the user to test inline autocompletion
// and shortcut acceptance (Tab) in real time without leaving the app.

struct CompletionDemoTextField: View {
    @EnvironmentObject var l10n: LocalizationManager
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var statsTracker = CompletionStatsTracker.shared
    @ObservedObject private var inferenceEngine = AIInferenceEngine.shared

    @State private var inputText: String = ""
    @State private var ghostSuffix: String = ""
    @State private var showSuccessBanner: Bool = false
    @State private var savedCharNotice: Int = 0

    // Built-in offline demo suggestions for immediate tactile response
    private let demoTemplates: [(prefix: String, completion: String)] = [
        ("прив", "ет! Как твои дела?"),
        ("спаси", "бо большое за помощь!"),
        ("добр", "ое утро! Отличного дня."),
        ("пожалуй", "ста, проверь этот документ."),
        ("догов", "орились, жду вестей."),
        ("hel", "lo! How are you doing today?"),
        ("than", "k you very much for the update!"),
        ("let", "'s catch up later this afternoon."),
        ("plea", "se review the attached notes."),
        ("fix(", "core): resolve layout mapping boundary")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .font(.body)
                    .foregroundStyle(.tint)
                Text(l10n.t("ai.sandbox.title"))
                    .font(.subheadline)
                    .bold()
                Spacer()
                if !inputText.isEmpty {
                    Button(l10n.t("ai.sandbox.clear")) {
                        inputText = ""
                        ghostSuffix = ""
                        showSuccessBanner = false
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Text(l10n.t("ai.sandbox.desc"))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Interactive Text Input Box with Live Ghost Text
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                HStack(spacing: 0) {
                    Text(inputText.isEmpty ? l10n.t("ai.sandbox.placeholder") : inputText)
                        .font(.system(size: 14))
                        .foregroundStyle(inputText.isEmpty ? .secondary : .primary)

                    if !ghostSuffix.isEmpty {
                        Text(ghostSuffix)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .allowsHitTesting(false)

                // Invisible native textfield capturing keystrokes and Tab key
                DemoKeyCapturingField(
                    text: $inputText,
                    onTextChange: { newText in
                        updateGhostText(for: newText)
                    },
                    onTabPressed: {
                        acceptCurrentGhost()
                    }
                )
                .opacity(0.02)
                .frame(height: 34)
            }
            .frame(height: 36)

            // Animated Keyboard Prompt & Example Presets
            HStack {
                KeyboardView(
                    keySymbol: "⇥ Tab",
                    promptText: ghostSuffix.isEmpty ? l10n.t("ai.sandbox.typeToSee") : l10n.t("ai.sandbox.pressTab"),
                    isHighlighted: !ghostSuffix.isEmpty,
                    onAccept: {
                        acceptCurrentGhost()
                    }
                )

                Spacer()

                // Quick preset buttons
                Menu(l10n.t("ai.sandbox.examples")) {
                    Button("«Привет...»") { applyPreset("Прив") }
                    Button("«Спасибо...»") { applyPreset("Спаси") }
                    Button("«Hello...»") { applyPreset("Hel") }
                    Button("«Let's...»") { applyPreset("Let") }
                }
                .menuStyle(.borderlessButton)
                .font(.caption)
            }

            if showSuccessBanner {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(format: l10n.t("ai.sandbox.success"), savedCharNotice))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func applyPreset(_ text: String) {
        inputText = text
        updateGhostText(for: text)
    }

    private func updateGhostText(for text: String) {
        showSuccessBanner = false
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            ghostSuffix = ""
            return
        }

        let lower = trimmed.lowercased()
        for template in demoTemplates {
            if lower.hasSuffix(template.prefix) || template.prefix.hasPrefix(lower) {
                if template.prefix.count >= lower.count {
                    let remPrefix = String(template.prefix.dropFirst(lower.count))
                    ghostSuffix = remPrefix + template.completion
                    return
                } else if lower.hasSuffix(template.prefix) {
                    ghostSuffix = template.completion
                    return
                }
            }
        }

        // Fallback generic phrase
        if lower.count >= 2 {
            if AIInferenceEngine.containsCyrillic(lower) {
                ghostSuffix = ", рад вас слышать!"
            } else {
                ghostSuffix = " forward to hearing from you."
            }
        } else {
            ghostSuffix = ""
        }
    }

    private func acceptCurrentGhost() {
        guard !ghostSuffix.isEmpty else { return }
        let accepted = ghostSuffix
        let full = inputText + accepted
        inputText = full
        ghostSuffix = ""
        savedCharNotice = accepted.count
        withAnimation {
            showSuccessBanner = true
        }

        statsTracker.recordAcceptedCompletion(insertedText: full, typedPrefix: inputText)
    }
}

// MARK: - AppKit Key Capture Helper for Sandbox
// Intercepts Tab and Escape inside the SwiftUI form without focus cycling.

struct DemoKeyCapturingField: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void
    var onTabPressed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = CustomDemoNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 14)
        field.textColor = .clear
        field.onTab = onTabPressed
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DemoKeyCapturingField

        init(parent: DemoKeyCapturingField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onTextChange(field.stringValue)
        }
    }
}

final class CustomDemoNSTextField: NSTextField {
    var onTab: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 48 { // Tab
            onTab?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
