import AppKit

/// A small rounded speech bubble shown in its own window above the cat.
@MainActor
final class SpeechBubble: NSObject {
    private let panel: NSPanel
    private let bubbleView = BubbleView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private weak var parent: NSWindow?

    private let padding: CGFloat = 12
    private let maxTextWidth: CGFloat = 200

    override init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        label.alignment = .center
        label.isSelectable = false
        bubbleView.addSubview(label)
        panel.contentView = bubbleView
    }

    /// Shows `text` above the cat window, anchored near `anchorX` (0...1 across it).
    func show(_ text: String, above catWindow: NSWindow, anchorX: CGFloat = 0.6) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        label.stringValue = text
        let textSize = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxTextWidth, height: 1000))
        let size = NSSize(width: ceil(textSize.width) + padding * 2,
                          height: ceil(textSize.height) + padding * 2 + BubbleView.tailHeight)
        label.frame = NSRect(x: padding, y: BubbleView.tailHeight + padding,
                             width: ceil(textSize.width), height: ceil(textSize.height))

        let cat = catWindow.frame
        var origin = NSPoint(x: cat.minX + cat.width * anchorX - size.width / 2,
                             y: cat.maxY - 24)
        if let screen = (catWindow.screen ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
            origin.y = min(origin.y, screen.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        bubbleView.needsDisplay = true

        if parent !== catWindow {
            parent?.removeChildWindow(panel)
            catWindow.addChildWindow(panel, ordered: .above)
            parent = catWindow
        }
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }

        // Longer lines stay up a little longer.
        perform(#selector(hide), with: nil, afterDelay: 5 + Double(text.count) / 20)
    }

    @objc func hide() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 }
        perform(#selector(removeFromScreen), with: nil, afterDelay: 0.35)
    }

    @objc private func removeFromScreen() {
        parent?.removeChildWindow(panel)
        parent = nil
        panel.orderOut(nil)
    }
}

/// Draws the bubble: a white rounded rectangle with a small tail at the bottom.
final class BubbleView: NSView {
    static let tailHeight: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 1, y: Self.tailHeight, width: bounds.width - 2,
                          height: bounds.height - Self.tailHeight - 1)
        let path = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: body.midX - 8, y: body.minY + 1))
        tail.line(to: NSPoint(x: body.midX - 2, y: 1))
        tail.line(to: NSPoint(x: body.midX + 6, y: body.minY + 1))
        tail.close()
        NSColor.white.setFill()
        NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
        for shape in [tail, path] {
            shape.lineWidth = 1.5
            shape.fill()
            shape.stroke()
        }
        // Paint over the border where the tail joins the body.
        NSColor.white.setFill()
        NSRect(x: body.midX - 6, y: body.minY - 1.5, width: 10, height: 3).fill()
    }
}
