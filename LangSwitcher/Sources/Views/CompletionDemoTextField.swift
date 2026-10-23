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
    @State private var isFieldFocused: Bool = false
    @State private var lastAcceptedGhost: String = ""
    @State private var pendingAIQueryTask: Task<Void, Never>?

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
                        pendingAIQueryTask?.cancel()
                        inputText = ""
                        ghostSuffix = ""
                        lastAcceptedGhost = ""
                        showSuccessBanner = false
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            Text(l10n.t("ai.sandbox.desc"))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Interactive Text Input Box with Live Native Ghost Text
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isFieldFocused ? Color.accentColor : Color.secondary.opacity(0.25),
                                lineWidth: isFieldFocused ? 1.5 : 1
                            )
                    )

                DemoKeyCapturingField(
                    text: $inputText,
                    ghostText: ghostSuffix,
                    placeholder: l10n.t("ai.sandbox.placeholder"),
                    isFocused: $isFieldFocused,
                    onTextChange: { newText in
                        updateGhostText(for: newText)
                    },
                    onTabPressed: {
                        acceptCurrentGhost()
                    },
                    onEscapePressed: {
                        ghostSuffix = ""
                    }
                )
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
        pendingAIQueryTask?.cancel()
        lastAcceptedGhost = ""
        inputText = text
        updateGhostText(for: text)
    }

    private func updateGhostText(for text: String) {
        showSuccessBanner = false
        pendingAIQueryTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            ghostSuffix = ""
            return
        }

        // 1. If real AI inference engine is running, request real contextual continuation
        if inferenceEngine.isRunning {
            pendingAIQueryTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms typing debounce
                guard !Task.isCancelled else { return }

                if let suffix = await inferenceEngine.predictContinuation(
                    context: text,
                    maxWords: 4
                ) {
                    guard !Task.isCancelled else { return }
                    let cleaned = suffix.trimmingCharacters(in: .newlines)
                    if !cleaned.isEmpty, cleaned != lastAcceptedGhost {
                        let lowerTrimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        let lowerCleaned = cleaned.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !lowerTrimmed.hasSuffix(lowerCleaned) {
                            self.ghostSuffix = cleaned
                            return
                        }
                    }
                }
                self.ghostSuffix = ""
            }
            return
        }

        // 2. Offline / Mock Templates mode (when no local LLM is loaded)
        let lower = trimmed.lowercased()
        for template in demoTemplates {
            if lower.hasSuffix(template.prefix) || template.prefix.hasPrefix(lower) {
                if template.prefix.count >= lower.count {
                    let remPrefix = String(template.prefix.dropFirst(lower.count))
                    let candidate = remPrefix + template.completion
                    if candidate != lastAcceptedGhost && !lower.hasSuffix(candidate.lowercased()) {
                        ghostSuffix = candidate
                        return
                    }
                } else if lower.hasSuffix(template.prefix) {
                    let candidate = template.completion
                    if candidate != lastAcceptedGhost && !lower.hasSuffix(candidate.lowercased()) {
                        ghostSuffix = candidate
                        return
                    }
                }
            }
        }

        // Clean finish without repetitive fallback spam
        ghostSuffix = ""
    }

    private static func splitFirstWord(from text: String) -> (word: String, remainder: String) {
        guard !text.isEmpty else { return ("", "") }
        var index = text.startIndex
        while index < text.endIndex && (text[index].isWhitespace || text[index].isPunctuation) {
            index = text.index(after: index)
        }
        while index < text.endIndex && !text[index].isWhitespace && !text[index].isPunctuation {
            index = text.index(after: index)
        }
        let word = String(text[..<index])
        let remainder = String(text[index...])
        return (word, remainder)
    }

    private func acceptCurrentGhost() {
        guard !ghostSuffix.isEmpty else { return }
        let shouldAcceptEntirePhrase = settingsManager.autoCompletionAcceptEntirePhrase
        let (acceptedChunk, remainingChunk) = shouldAcceptEntirePhrase
            ? (ghostSuffix, "")
            : Self.splitFirstWord(from: ghostSuffix)

        guard !acceptedChunk.isEmpty else { return }
        lastAcceptedGhost = acceptedChunk
        let full = inputText + acceptedChunk
        inputText = full
        ghostSuffix = remainingChunk
        savedCharNotice = acceptedChunk.count
        withAnimation {
            showSuccessBanner = true
        }

        statsTracker.recordAcceptedCompletion(insertedText: full, typedPrefix: inputText)
    }
}

// MARK: - AppKit Key Capture & Native Ghost Text Renderer
// Renders native editable text view with inline ghost completion, caret management,
// and Tab/Escape key command handling without losing focus.

struct DemoKeyCapturingField: NSViewRepresentable {
    @Binding var text: String
    var ghostText: String
    var placeholder: String
    @Binding var isFocused: Bool
    var onTextChange: (String) -> Void
    var onTabPressed: () -> Void
    var onEscapePressed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CustomDemoNSTextView {
        let textView = CustomDemoNSTextView()
        textView.delegate = context.coordinator
        textView.placeholderText = placeholder
        textView.ghostText = ghostText
        textView.onTab = onTabPressed
        textView.onEscape = onEscapePressed
        textView.onFocusChange = { [weak coordinator = context.coordinator] focused in
            DispatchQueue.main.async {
                coordinator?.parent.isFocused = focused
            }
        }
        textView.onTextChange = { newText in
            context.coordinator.parent.text = newText
            context.coordinator.parent.onTextChange(newText)
        }
        return textView
    }

    func updateNSView(_ nsView: CustomDemoNSTextView, context: Context) {
        context.coordinator.parent = self

        if nsView.string != text {
            nsView.string = text
            let len = (text as NSString).length
            nsView.setSelectedRange(NSRange(location: len, length: 0))
        }

        if nsView.ghostText != ghostText {
            nsView.ghostText = ghostText
        }

        if nsView.placeholderText != placeholder {
            nsView.placeholderText = placeholder
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DemoKeyCapturingField

        init(parent: DemoKeyCapturingField) {
            self.parent = parent
        }
    }
}

final class CustomDemoNSTextView: NSTextView {
    var ghostText: String = "" {
        didSet {
            if ghostText != oldValue {
                needsDisplay = true
            }
        }
    }
    var placeholderText: String = "" {
        didSet {
            if placeholderText != oldValue {
                needsDisplay = true
            }
        }
    }
    var onTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onTextChange: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        drawsBackground = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isVerticallyResizable = false
        isHorizontallyResizable = false
        isEditable = true
        isSelectable = true

        font = NSFont.systemFont(ofSize: 14)
        textColor = NSColor.labelColor
        insertionPointColor = NSColor.controlAccentColor

        textContainer?.maximumNumberOfLines = 1
        textContainer?.lineBreakMode = .byClipping
        textContainer?.widthTracksTextView = true
        textContainerInset = NSSize(width: 10, height: 8)
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            onFocusChange?(true)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onFocusChange?(false)
        }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertTab(_:)) {
            if !ghostText.isEmpty {
                onTab?()
                return
            }
            super.doCommand(by: selector)
            return
        }
        if selector == #selector(cancelOperation(_:)) {
            onEscape?()
            return
        }
        if selector == #selector(insertNewline(_:)) ||
            selector == #selector(insertParagraphSeparator(_:)) ||
            selector == #selector(insertLineBreak(_:)) {
            if !ghostText.isEmpty {
                onTab?()
            }
            return
        }
        super.doCommand(by: selector)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let textLen = (string as NSString).length
        let fontToUse = font ?? NSFont.systemFont(ofSize: 14)

        if textLen == 0 {
            if !placeholderText.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: fontToUse,
                    .foregroundColor: NSColor.placeholderTextColor
                ]
                let pt = NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y)
                (placeholderText as NSString).draw(at: pt, withAttributes: attrs)
            }
        } else if !ghostText.isEmpty {
            guard let lm = layoutManager, let tc = textContainer else { return }
            let glyphIndex = lm.glyphIndexForCharacter(at: textLen - 1)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: tc)
            let ghostPoint = NSPoint(x: textContainerOrigin.x + rect.maxX, y: textContainerOrigin.y + rect.origin.y)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: fontToUse,
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.65)
            ]
            (ghostText as NSString).draw(at: ghostPoint, withAttributes: attrs)
        }
    }
}
