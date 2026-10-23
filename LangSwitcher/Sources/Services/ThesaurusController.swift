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

    var isVisible: Bool {
        panel?.isVisible == true
    }

    init(accessibilityService: AccessibilityService = AccessibilityService()) {
        self.accessibilityService = accessibilityService
        super.init()
    }

    func show(word: String, candidates: [ThesaurusEngine.Candidate], anchor: CGRect, isActualSelection: Bool = true) {
        guard !candidates.isEmpty else { return }

        self.activeWord = word
        self.activeCandidates = candidates
        self.isActualSelection = isActualSelection

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
        panel?.orderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        activeCandidates = []
        activeWord = nil
    }

    func handleNumericInput(_ digit: Int) -> Bool {
        guard isVisible, digit >= 1, digit <= activeCandidates.count else { return false }
        let chosen = activeCandidates[digit - 1].synonym
        applyReplacement(chosen)
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
            // If no text was highlighted, delete the preceding word and insert synonym
            accessibilityService.replaceWithBackspaces(count: word.count, replacement: replacement)
        }
        hide()
    }

    func triggerForCurrentSelection() {
        // Try getting selection from AX
        var selectedText: String?
        var isActualSelection = false
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
               let lastWord = context.textBeforeCaret.split(separator: " ").last {
                selectedText = String(lastWord)
                isActualSelection = false
            }
        }

        guard let word = selectedText, !word.isEmpty else { return }

        let candidates = ThesaurusEngine.candidates(for: word)
        guard !candidates.isEmpty else { return }

        let caret = accessibilityService.caretScreenRect() ?? CGRect(x: 200, y: 500, width: 2, height: 16)
        show(word: word, candidates: candidates, anchor: caret, isActualSelection: isActualSelection)
    }
}
