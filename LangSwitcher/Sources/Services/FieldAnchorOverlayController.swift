import Foundation
import AppKit

// MARK: - Field Anchor Overlay Controller
// Displays an unobtrusive floating badge anchored to the top-left corner
// of the active text field to indicate that LangSwitcher AI is active.

@MainActor
final class FieldAnchorOverlayController: NSObject {
    
    private var panel: NSPanel?
    private var badgeView: FieldAnchorBadgeView?
    private(set) var lastFieldRect: CGRect?
    
    var isVisible: Bool {
        panel?.isVisible == true
    }
    
    override init() {
        super.init()
    }
    
    func show(fieldRect: CGRect) {
        guard fieldRect.width > 30, fieldRect.height > 15 else {
            hide()
            return
        }
        
        self.lastFieldRect = fieldRect
        let p = getOrCreatePanel()
        
        let center = CGPoint(x: fieldRect.midX, y: fieldRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(fieldRect) }
        let frame = Self.badgeFrame(fieldRect: fieldRect, visibleFrame: screen?.visibleFrame ?? fieldRect)
        p.setFrame(frame, display: true)
        p.alphaValue = 1
        if !p.isVisible { p.orderFrontRegardless() }
    }

    static func badgeFrame(fieldRect: CGRect, visibleFrame: CGRect) -> CGRect {
        let size: CGFloat = 22
        let margin: CGFloat = 6
        let desiredX = fieldRect.minX - size - margin
        let x = min(max(desiredX, visibleFrame.minX), visibleFrame.maxX - size)
        let desiredY = fieldRect.height > 36 ? fieldRect.maxY - size - 4 : fieldRect.midY - size / 2
        let y = min(max(desiredY, visibleFrame.minY), visibleFrame.maxY - size)
        return CGRect(x: x, y: y, width: size, height: size)
    }

    func hide() {
        // Immediate dismissal cannot later hide a panel reused by a new field.
        panel?.orderOut(nil)
        lastFieldRect = nil
    }

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel { return existing }
        
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 22, height: 22),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true // Pass all clicks straight to the underlying text view
        
        let v = FieldAnchorBadgeView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        p.contentView = v
        self.badgeView = v
        self.panel = p
        return p
    }
}

// MARK: - Native Field Anchor Badge View
private final class FieldAnchorBadgeView: NSView {
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let bounds = self.bounds
        let circlePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        
        // Translucent background
        NSColor.windowBackgroundColor.withAlphaComponent(0.90).setFill()
        circlePath.fill()
        
        // Subtle border
        circlePath.lineWidth = 0.75
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        circlePath.stroke()
        
        // SF Symbol "sparkles" tinted with accent color
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: NSColor.controlAccentColor))
        if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Active")?.withSymbolConfiguration(config) {
            let iconRect = NSRect(
                x: (bounds.width - 12) / 2,
                y: (bounds.height - 12) / 2,
                width: 12,
                height: 12
            )
            symbol.draw(in: iconRect)
        }
    }
}
