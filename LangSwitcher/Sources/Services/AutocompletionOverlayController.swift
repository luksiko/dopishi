import Foundation
import AppKit
import SwiftUI

// MARK: - Autocompletion Overlay Controller
// Manages the non-activating floating NSPanel displaying AutocompletionPopupView.

@MainActor
final class AutocompletionOverlayController: NSObject {
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    
    private(set) var candidates: [AutocompletionCandidate] = []
    private(set) var selectedIndex: Int = 0
    private var onSelectCallback: ((AutocompletionCandidate) -> Void)?
    private var currentAcceptKeyHint: String = "⇥"
    
    var isVisible: Bool {
        panel?.isVisible == true
    }
    
    func containsPoint(_ point: NSPoint) -> Bool {
        guard let p = panel, p.isVisible else { return false }
        return p.frame.contains(point)
    }
    
    var selectedCandidate: AutocompletionCandidate? {
        guard !candidates.isEmpty, selectedIndex >= 0, selectedIndex < candidates.count else {
            return nil
        }
        return candidates[selectedIndex]
    }
    
    override init() {
        super.init()
    }
    
    func show(
        candidates: [AutocompletionCandidate],
        caretRect: CGRect?,
        acceptKeyHint: String,
        onSelect: @escaping (AutocompletionCandidate) -> Void
    ) {
        guard !candidates.isEmpty, caretRect != nil else {
            hide()
            return
        }
        
        self.candidates = candidates
        self.selectedIndex = 0
        self.currentAcceptKeyHint = acceptKeyHint
        self.onSelectCallback = onSelect
        
        let p = getOrCreatePanel()
        updateContent()
        
        // Position panel
        positionPanel(caretRect: caretRect)
        
        p.orderFrontRegardless()
    }
    
    func hide() {
        panel?.orderOut(nil)
        candidates.removeAll()
        selectedIndex = 0
        onSelectCallback = nil
    }
    
    func selectNext() {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % candidates.count
        updateContent()
    }
    
    func selectPrevious() {
        guard !candidates.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + candidates.count) % candidates.count
        updateContent()
    }
    
    func selectIndex(_ index: Int) {
        guard index >= 0 && index < candidates.count else { return }
        selectedIndex = index
        acceptCurrent()
    }
    
    func acceptCurrent() {
        guard let candidate = selectedCandidate else { return }
        let callback = onSelectCallback
        hide()
        callback?(candidate)
    }
    
    private func updateContent() {
        let view = AutocompletionPopupView(
            candidates: candidates,
            selectedIndex: selectedIndex,
            acceptKeyHint: currentAcceptKeyHint,
            onSelect: { [weak self] candidate in
                self?.hide()
                self?.onSelectCallback?(candidate)
            }
        )
        
        if let hosting = hostingView {
            hosting.rootView = AnyView(view)
        } else {
            let hosting = NSHostingView(rootView: AnyView(view))
            // Preserve fittingSize measurement without automatic min/max window
            // constraints, which otherwise feed back into manual panel resizing.
            hosting.sizingOptions = [.intrinsicContentSize]
            panel?.contentView = hosting
            hostingView = hosting
        }
        
        // Resize panel to fit content
        if let p = panel, let hosting = hostingView {
            let fittingSize = hosting.fittingSize
            if p.frame.size != fittingSize {
                var frame = p.frame
                frame.size = fittingSize
                p.setFrame(frame, display: true)
            }
        }
    }
    
    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }
        
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = false
        
        self.panel = p
        return p
    }
    
    private func positionPanel(caretRect: CGRect?) {
        guard let p = panel else { return }
        let size = p.frame.size
        
        // Choose screen containing caret or mouse
        let screen = NSScreen.screens.first { s in
            if let c = caretRect {
                return s.frame.intersects(c)
            }
            return false
        } ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        
        let visibleFrame = screen.visibleFrame
        var origin = CGPoint.zero
        
        if let caret = caretRect {
            origin.x = caret.origin.x
            // Default: position below caret
            origin.y = caret.origin.y - size.height - 4
            // If going below screen, position above caret
            if origin.y < visibleFrame.minY {
                origin.y = caret.origin.y + caret.height + 4
            }
        } else {
            let mouse = NSEvent.mouseLocation
            origin.x = mouse.x + 10
            origin.y = mouse.y - size.height - 10
        }
        
        // Constrain within visible frame
        if origin.x + size.width > visibleFrame.maxX {
            origin.x = visibleFrame.maxX - size.width - 4
        }
        if origin.x < visibleFrame.minX {
            origin.x = visibleFrame.minX + 4
        }
        if origin.y < visibleFrame.minY {
            origin.y = visibleFrame.minY + 4
        }
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = visibleFrame.maxY - size.height - 4
        }
        
        p.setFrameOrigin(origin)
    }
}
