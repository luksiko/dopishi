import Foundation
import AppKit
import SwiftUI

// MARK: - Thesaurus Controller
// Manages the non-activating floating HUD for contextual synonyms and handles text replacement.

@MainActor
final class ThesaurusController: NSObject {
    static let shared = ThesaurusController()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let accessibilityService: AccessibilityService

    private(set) var activeCandidates: [ThesaurusEngine.Candidate] = []
    private(set) var activeWord: String?
    private(set) var isActualSelection: Bool = false
    private(set) var trailingSuffixToPreserve: String = ""

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(accessibilityService: AccessibilityService = AccessibilityService()) {
        self.accessibilityService = accessibilityService
        super.init()
    }

    func show(
        word: String,
        candidates: [ThesaurusEngine.Candidate],
        anchor: CGRect,
        isActualSelection: Bool = true,
        trailingSuffix: String = ""
    ) {
        guard !candidates.isEmpty else { return }

        self.activeWord = word
        self.activeCandidates = candidates
        self.isActualSelection = isActualSelection
        self.trailingSuffixToPreserve = isActualSelection ? "" : trailingSuffix

        let hudView = ThesaurusHUDView(
            word: word,
            candidates: candidates,
            onSelect: { [weak self] chosen in
                self?.applyReplacement(chosen)
            },
            onDismiss: { [weak self] in
                self?.hide()
            }
        )

        let wrapped = AnyView(hudView)

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 44),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .floating
            p.hasShadow = false
            p.ignoresMouseEvents = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = p
        }

        if let existingHosting = hostingView {
            existingHosting.rootView = wrapped
        } else {
            let host = NSHostingView(rootView: wrapped)
            hostingView = host
            panel?.contentView = host
        }

        hostingView?.layoutSubtreeIfNeeded()
        let fittingSize = hostingView?.fittingSize ?? CGSize(width: 320, height: 44)

        // Position panel directly below anchor rect
        var panelX = anchor.origin.x
        var panelY = anchor.origin.y - fittingSize.height - 6

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            if panelX + fittingSize.width > screen.visibleFrame.maxX {
                panelX = screen.visibleFrame.maxX - fittingSize.width - 8
            }
            if panelX < screen.visibleFrame.minX {
                panelX = screen.visibleFrame.minX + 8
            }
            if panelY < screen.visibleFrame.minY {
                // Flip above anchor if bottom of screen reached
                panelY = anchor.origin.y + anchor.size.height + 6
            }
        }

        panel?.setFrame(NSRect(x: panelX, y: panelY, width: fittingSize.width, height: fittingSize.height), display: true)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        activeCandidates = []
        activeWord = nil
        trailingSuffixToPreserve = ""
    }

    func handleNumericInput(_ digit: Int) -> Bool {
        guard isVisible, digit >= 1, digit <= activeCandidates.count else { return false }
        let chosen = activeCandidates[digit - 1].synonym
        applyReplacement(chosen)
        return true
    }

    func confirmFirstCandidate() -> Bool {
        guard isVisible, let first = activeCandidates.first else { return false }
        applyReplacement(first.synonym)
        return true
    }

    func applyReplacement(_ replacement: String) {
        guard let word = activeWord else {
            hide()
            return
        }

        if isActualSelection {
            // If text was highlighted, paste over selection
            accessibilityService.pasteReplacingSelection(replacement)
        } else {
            // If no text was highlighted, delete the preceding word (plus any trailing punctuation/space) and re-insert
            let deleteCount = word.count + trailingSuffixToPreserve.count
            accessibilityService.replaceWithBackspaces(
                count: deleteCount,
                replacement: replacement + trailingSuffixToPreserve
            )
        }
        hide()
    }

    nonisolated static func extractTrailingWord(from textBeforeCaret: String) -> (word: String, trailingSuffix: String)? {
        guard !textBeforeCaret.isEmpty else { return nil }
        let chars = Array(textBeforeCaret)
        var idx = chars.count - 1
        var trailingCount = 0

        while idx >= 0 && !chars[idx].isLetter {
            if chars[idx].isNewline || trailingCount >= 4 {
                return nil
            }
            trailingCount += 1
            idx -= 1
        }
        guard idx >= 0 else { return nil }

        let wordEnd = idx
        while idx >= 0 && (chars[idx].isLetter || (chars[idx] == "-" && idx > 0 && chars[idx - 1].isLetter)) {
            idx -= 1
        }
        let wordStart = idx + 1
        let word = String(chars[wordStart...wordEnd])
        guard !word.isEmpty else { return nil }
        let trailingSuffix = (wordEnd + 1 < chars.count) ? String(chars[(wordEnd + 1)...]) : ""
        return (word: word, trailingSuffix: trailingSuffix)
    }

    func triggerForCurrentSelection() {
        // Try getting selection from AX
        var selectedText: String?
        var isActualSelection = false
        var trailingSuffix = ""
        if let focused = accessibilityService.focusedTextElement() {
            var value: AnyObject?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &value) == .success,
               let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                isActualSelection = true
            }
        }

        // If no AX selection, check caret context
        if selectedText == nil {
            if let context = accessibilityService.captureCaretContext(),
               let extracted = Self.extractTrailingWord(from: context.textBeforeCaret) {
                selectedText = extracted.word
                trailingSuffix = extracted.trailingSuffix
                isActualSelection = false
            }
        }

        guard let word = selectedText, !word.isEmpty else { return }

        let candidates = ThesaurusEngine.candidates(for: word)
        guard !candidates.isEmpty else { return }

        let caret = accessibilityService.caretScreenRect() ?? CGRect(x: 200, y: 500, width: 2, height: 16)
        show(
            word: word,
            candidates: candidates,
            anchor: caret,
            isActualSelection: isActualSelection,
            trailingSuffix: trailingSuffix
        )
    }
}
