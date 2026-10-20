import Foundation
import AppKit

// MARK: - Ghost Text Overlay Controller
// Manages the floating transparent panel that renders inline ghost text at the caret.

@MainActor
final class GhostTextOverlayController: NSObject {
    
    private var panel: NSPanel?
    private var textView: GhostTextView?
    private(set) var currentSuffix: String = ""
    private(set) var currentCandidate: AutocompletionCandidate?
    
    var isVisible: Bool {
        panel?.isVisible == true
    }
    
    override init() {
        super.init()
    }
    
    func show(candidate: AutocompletionCandidate, suffix: String, caretRect: CGRect?) {
        guard !suffix.isEmpty, let caret = caretRect else {
            hide()
            return
        }
        
        self.currentCandidate = candidate
        self.currentSuffix = suffix
        let p = getOrCreatePanel()
        
        if textView == nil {
            let v = GhostTextView()
            p.contentView = v
            textView = v
        }
        
        guard let tv = textView else { return }
        tv.text = suffix
        let fittingSize = tv.idealSize()
        
        // Position directly at the right edge of caret
        var origin = CGPoint(x: caret.maxX + 1, y: caret.minY)
        
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
        p.setFrame(newFrame, display: true)
        p.orderFrontRegardless()
    }
    
    func hide() {
        panel?.orderOut(nil)
        currentSuffix = ""
        currentCandidate = nil
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
private final class GhostTextView: NSView {
    var text: String = "" {
        didSet {
            needsDisplay = true
        }
    }
    
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !text.isEmpty else { return }
        
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        bgPath.fill()
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.65)
        ]
        
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textRect = NSRect(
            x: 4,
            y: (bounds.height - textSize.height) / 2,
            width: bounds.width - 8,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }
    
    func idealSize() -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        return CGSize(width: ceil(textSize.width) + 8, height: max(18, ceil(textSize.height) + 2))
    }
}
