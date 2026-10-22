import Foundation
import AppKit

// MARK: - Ghost Text Overlay Controller
// Manages the floating transparent panel that renders inline ghost text at the caret.

@MainActor
final class GhostTextOverlayController: NSObject {

    private var presentationRevision = 0
    private var panel: NSPanel?
    private var textView: GhostTextView?
    private(set) var currentSuffix: String = ""
    private(set) var currentCandidate: AutocompletionCandidate?
    private(set) var lastCaretRect: CGRect?
    private(set) var pendingCaretAnchor: CGRect?
    private var pendingCaretPollTask: Task<Void, Never>?
    private var pendingCaretPollDeadline: Date?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var panelFrame: NSRect? {
        panel?.frame
    }

    override init() {
        super.init()
    }

    func show(
        candidate: AutocompletionCandidate,
        suffix: String,
        caretRect: CGRect?,
        caretProvider: (() -> CGRect?)? = nil
    ) {
        guard !suffix.isEmpty else {
            hide()
            return
        }

        self.currentCandidate = candidate
        self.currentSuffix = suffix

        let previousAnchor = pendingCaretAnchor
        let initialCaret = Self.isValidCaretRect(caretRect) ? caretRect : (Self.isValidCaretRect(lastCaretRect) ? lastCaretRect : nil)

        if let initialCaret = initialCaret {
            let isStaleAnchor = previousAnchor != nil && Self.isCaretEqual(initialCaret, previousAnchor)

            if isStaleAnchor, let provider = caretProvider {
                // The caret bounds haven't moved yet after keystroke (typical in Electron apps like VS Code, Slack).
                // If the panel is already visible, update the text view content immediately so the newly typed char
                // disappears from the ghost text, but hold panel position until the updated caret arrives from AX.
                if panel?.isVisible == true, let tv = textView {
                    tv.text = suffix
                }
                startPendingCaretPoll(anchor: initialCaret, provider: provider)
            } else {
                cancelPendingCaretPoll()
                pendingCaretAnchor = initialCaret
                lastCaretRect = initialCaret
                positionAndDisplay(caret: initialCaret, suffix: suffix)
            }
        } else if let provider = caretProvider {
            // Initial caret rect not available yet (e.g. during fast typing in webviews).
            startPendingCaretPoll(anchor: nil, provider: provider)
        } else {
            hide()
        }
    }

    private func positionAndDisplay(caret: CGRect, suffix: String) {
        let p = getOrCreatePanel()

        if textView == nil {
            let v = GhostTextView()
            p.contentView = v
            textView = v
        }

        guard let tv = textView else { return }

        if caret.height > 10, caret.height < 40 {
            tv.fontSize = max(12.0, min(16.0, caret.height - 3))
        } else {
            tv.fontSize = 13.5
        }
        tv.text = suffix
        let fittingSize = tv.idealSize()

        // Position directly at the right edge of caret with zero margin
        var origin = CGPoint(x: caret.maxX, y: caret.minY + (caret.height - fittingSize.height) / 2)

        // Ensure within screen visible frame
        let screen = NSScreen.screens.first { s in
            s.frame.intersects(caret)
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()

        let vf = screen.visibleFrame
        // Anchor origin.x strictly to caret.maxX. Never shift leftwards over typed text.
        var panelSize = fittingSize
        if origin.x + panelSize.width > vf.maxX {
            let availableWidth = max(0, vf.maxX - origin.x - 2)
            panelSize.width = min(fittingSize.width, availableWidth)
        }
        if origin.y < vf.minY {
            origin.y = vf.minY + 2
        }
        if origin.y + panelSize.height > vf.maxY {
            origin.y = vf.maxY - panelSize.height - 2
        }

        let newFrame = NSRect(origin: origin, size: panelSize)
        if p.frame != newFrame {
            p.setFrame(newFrame, display: true)
        }
        if !p.isVisible {
            p.orderFrontRegardless()
        }
    }

    func hide() {
        cancelPendingCaretPoll()
        presentationRevision &+= 1
        panel?.orderOut(nil)
        currentSuffix = ""
        currentCandidate = nil
        lastCaretRect = nil
        pendingCaretAnchor = nil
    }

    // MARK: - Caret Stabilization Polling Implementation

    func cancelPendingCaretPoll() {
        pendingCaretPollTask?.cancel()
        pendingCaretPollTask = nil
        pendingCaretPollDeadline = nil
    }

    func startPendingCaretPoll(anchor: CGRect?, provider: @escaping () -> CGRect?) {
        cancelPendingCaretPoll()

        let deadline = Date().addingTimeInterval(0.12) // 120ms hard timeout
        self.pendingCaretPollDeadline = deadline

        pendingCaretPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000) // 12ms poll interval
                guard !Task.isCancelled, let self = self else { return }

                if let currentDeadline = self.pendingCaretPollDeadline, Date() >= currentDeadline {
                    if self.panel?.isVisible != true {
                        self.hide()
                    } else {
                        self.cancelPendingCaretPoll()
                    }
                    return
                }

                if let newRect = provider(), Self.isValidCaretRect(newRect) {
                    let hasResolved: Bool
                    if let anchor = anchor {
                        hasResolved = !Self.isCaretEqual(newRect, anchor)
                    } else {
                        hasResolved = true
                    }

                    if hasResolved {
                        self.pendingCaretAnchor = newRect
                        self.lastCaretRect = newRect
                        if !self.currentSuffix.isEmpty {
                            self.positionAndDisplay(caret: newRect, suffix: self.currentSuffix)
                        }
                        self.cancelPendingCaretPoll()
                        return
                    }
                }
            }
        }
    }

    static func isValidCaretRect(_ rect: CGRect?) -> Bool {
        guard let rect = rect, !rect.isEmpty, !rect.isNull else { return false }
        guard rect.width > 0 && rect.height > 0 else { return false }
        guard rect.origin.x.isFinite && rect.origin.y.isFinite else { return false }
        if rect.origin == .zero && rect.size.width <= 1.0 && rect.size.height <= 1.0 {
            return false
        }
        return true
    }

    static func isCaretEqual(_ a: CGRect?, _ b: CGRect?) -> Bool {
        guard let a = a, let b = b else { return a == nil && b == nil }
        return abs(a.origin.x - b.origin.x) < 0.5 &&
               abs(a.origin.y - b.origin.y) < 0.5 &&
               abs(a.size.width - b.size.width) < 0.5 &&
               abs(a.size.height - b.size.height) < 0.5
    }

    /// Retain a known continuation while AX catches up with the insertion.
    /// Keep the panel hidden until real caret coordinates are available.
    func showContinuation(candidate: AutocompletionCandidate, suffix: String,
                          caretProvider: @escaping () -> CGRect?, isCurrent: @escaping () -> Bool) {
        hide()
        guard !suffix.isEmpty else { return }
        currentCandidate = candidate
        currentSuffix = suffix
        retryContinuation(candidate: candidate, suffix: suffix, caretProvider: caretProvider,
                          isCurrent: isCurrent, revision: presentationRevision, attemptsLeft: 3)
    }

    private func retryContinuation(candidate: AutocompletionCandidate, suffix: String,
                                   caretProvider: @escaping () -> CGRect?, isCurrent: @escaping () -> Bool,
                                   revision: Int, attemptsLeft: Int) {
        guard revision == presentationRevision else { return }
        guard isCurrent() else { hide(); return }
        if let caret = caretProvider() {
            show(candidate: candidate, suffix: suffix, caretRect: caret)
        } else if attemptsLeft > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) { [weak self] in
                self?.retryContinuation(candidate: candidate, suffix: suffix, caretProvider: caretProvider,
                    isCurrent: isCurrent, revision: revision, attemptsLeft: attemptsLeft - 1)
            }
        } else {
            hide()
        }
    }

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 24),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true // Allow clicks to pass straight into the text editor

        self.panel = p
        return p
    }
}

// MARK: - Native AppKit Ghost Text View
// Ultra-lightweight native view: 0 SwiftUI constraints, 0 recursion, zero overhead.
// Renders delicate inline completion ghost text matching native editor styling.
private final class GhostTextView: NSView {
    var text: String = "" {
        didSet {
            needsDisplay = true
        }
    }

    var fontSize: CGFloat = 13.5 {
        didSet {
            font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
            needsDisplay = true
        }
    }

    private var font = NSFont.systemFont(ofSize: 13.5, weight: .regular)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !text.isEmpty else { return }

        // Delicate native ghost styling: zero background rectangle, matching ambient editor text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.50)
        ]

        let textSize = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: 0,
            y: (bounds.height - textSize.height) / 2,
            width: bounds.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    func idealSize() -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(textSize.width) + 2, height: max(16, ceil(textSize.height)))
    }
}
