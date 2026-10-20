import Foundation
import AppKit
import SwiftUI

// MARK: - Ghost Text Overlay Controller
// Manages the floating transparent panel that renders inline ghost text at the caret.

@MainActor
final class GhostTextOverlayController: NSObject {
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
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
        
        let view = GhostTextPreviewView(text: suffix)
        if let hosting = hostingView {
            hosting.rootView = AnyView(view)
        } else {
            let hosting = NSHostingView(rootView: AnyView(view))
            p.contentView = hosting
            hostingView = hosting
        }
        
        // Resize panel
        let fittingSize = hostingView?.fittingSize ?? CGSize(width: 80, height: 20)
        var frame = p.frame
        frame.size = fittingSize
        p.setFrame(frame, display: true)
        
        // Position directly at the right edge of caret
        var origin = CGPoint(x: caret.maxX + 1, y: caret.minY)
        
        // Ensure within screen visible frame
        let screen = NSScreen.screens.first { s in
            s.frame.intersects(caret)
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        
        let vf = screen.visibleFrame
        if origin.x + frame.width > vf.maxX {
            origin.x = vf.maxX - frame.width - 2
        }
        if origin.y < vf.minY {
            origin.y = vf.minY + 2
        }
        if origin.y + frame.height > vf.maxY {
            origin.y = vf.maxY - frame.height - 2
        }
        
        p.setFrameOrigin(origin)
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
