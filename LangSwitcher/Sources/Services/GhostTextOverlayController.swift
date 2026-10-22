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
    
    var isVisible: Bool {
        panel?.isVisible == true
    }
    
    override init() {
        super.init()
    }
    
    func show(candidate: AutocompletionCandidate, suffix: String, caretRect: CGRect?) {
        let caret = caretRect ?? lastCaretRect
        guard !suffix.isEmpty, let caret else {
            hide()
            return
        }
        
        self.lastCaretRect = caret
        self.currentCandidate = candidate
        self.currentSuffix = suffix
        let p = getOrCreatePanel()
        
        if textView == nil {
            let v = GhostTextView()
            p.contentView = v
            textView = v
        }
        
        guard let tv = textView else { return }
        
        if let caretHeight = caretRect?.height, caretHeight > 10, caretHeight < 40 {
            tv.fontSize = max(12.0, min(16.0, caretHeight - 3))
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
        if origin.x + fittingSize.width > vf.maxX {
            origin.x = vf.maxX - fittingSize.width - 2
        }
        if origin.y < vf.minY {
            origin.y = vf.minY + 2
        }
        if origin.y + fittingSize.height > vf.maxY {
            origin.y = vf.maxY - fittingSize.height - 2
        }
        
        let newFrame = NSRect(origin: origin, size: fittingSize)
        if p.frame != newFrame {
            p.setFrame(newFrame, display: true)
        }
        if !p.isVisible {
            p.orderFrontRegardless()
        }
    }
    
    func hide() {
        presentationRevision &+= 1
        panel?.orderOut(nil)
        currentSuffix = ""
        currentCandidate = nil
        lastCaretRect = nil
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
