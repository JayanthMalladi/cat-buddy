import AppKit

/// A small rounded speech bubble shown in its own window above the cat.
///
/// A pinned bubble (a nudge from Jayanth) is tinted, signed, and stays up until she clicks it or
/// the cat. While it's up, ordinary lines and hides are ignored so nothing covers it.
@MainActor
final class SpeechBubble: NSObject {
    private let panel: NSPanel
    private let bubbleView = BubbleView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let signature = NSTextField(labelWithString: "")
    private weak var parent: NSWindow?

    /// Whether a pinned bubble is showing.
    private(set) var isPinned = false
    /// Called when she clicks a pinned bubble.
    var onPinnedClick: (() -> Void)?

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

        signature.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        signature.textColor = NSColor(calibratedRed: 0.62, green: 0.25, blue: 0.40, alpha: 1)
        signature.alignment = .right
        signature.isSelectable = false
        bubbleView.addSubview(signature)
        bubbleView.onClick = { [weak self] in
            guard let self, self.isPinned else { return }
            self.onPinnedClick?()
        }
        panel.contentView = bubbleView
    }

    /// Shows `text` above the cat window, anchored near `anchorX` (0...1 across it). Ignored while
    /// a pinned bubble is up.
    func show(_ text: String, above catWindow: NSWindow, anchorX: CGFloat = 0.6) {
        guard !isPinned else { return }
        present(text, signedBy: nil, above: catWindow, anchorX: anchorX)
    }

    /// Shows a tinted, signed bubble that stays up until `unpin()` (a new pinned one replaces it).
    func showPinned(_ text: String, signedBy name: String, above catWindow: NSWindow, anchorX: CGFloat = 0.6) {
        present(text, signedBy: name, above: catWindow, anchorX: anchorX)
    }

    /// Takes down a pinned bubble.
    func unpin() {
        guard isPinned else { return }
        isPinned = false
        hide()
    }

    private func present(_ text: String, signedBy name: String?, above catWindow: NSWindow, anchorX: CGFloat) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        isPinned = name != nil
        bubbleView.tinted = isPinned
        panel.ignoresMouseEvents = !isPinned
        label.stringValue = text
        signature.stringValue = name ?? ""
        signature.isHidden = name == nil
        let textSize = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: maxTextWidth, height: 1000))
        let signatureSize = name == nil ? .zero : signature.cell!.cellSize
        let signatureGap: CGFloat = name == nil ? 0 : 4
        let contentWidth = ceil(max(textSize.width, signatureSize.width))
        let size = NSSize(width: contentWidth + padding * 2,
                          height: ceil(textSize.height) + ceil(signatureSize.height) + signatureGap
                              + padding * 2 + BubbleView.tailHeight)
        signature.frame = NSRect(x: padding, y: BubbleView.tailHeight + padding,
                                 width: contentWidth, height: ceil(signatureSize.height))
        label.frame = NSRect(x: padding + (contentWidth - ceil(textSize.width)) / 2,
                             y: BubbleView.tailHeight + padding + ceil(signatureSize.height) + signatureGap,
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

        // Longer lines stay up a little longer; a pinned one stays until she clicks.
        if !isPinned {
            perform(#selector(hide), with: nil, afterDelay: 5 + Double(text.count) / 20)
        }
    }

    /// Fades the bubble out, unless it's pinned.
    @objc func hide() {
        guard !isPinned else { return }
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

/// Draws the bubble: a white (or, for a nudge, soft pink) rounded rectangle with a small tail at
/// the bottom.
final class BubbleView: NSView {
    static let tailHeight: CGFloat = 10

    var tinted = false {
        didSet { needsDisplay = true }
    }
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 1, y: Self.tailHeight, width: bounds.width - 2,
                          height: bounds.height - Self.tailHeight - 1)
        let path = NSBezierPath(roundedRect: body, xRadius: 12, yRadius: 12)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: body.midX - 8, y: body.minY + 1))
        tail.line(to: NSPoint(x: body.midX - 2, y: 1))
        tail.line(to: NSPoint(x: body.midX + 6, y: body.minY + 1))
        tail.close()
        let fill = tinted ? NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.95, alpha: 1) : NSColor.white
        fill.setFill()
        (tinted ? NSColor(calibratedRed: 0.80, green: 0.40, blue: 0.55, alpha: 1)
                : NSColor(calibratedWhite: 0.25, alpha: 1)).setStroke()
        for shape in [tail, path] {
            shape.lineWidth = 1.5
            shape.fill()
            shape.stroke()
        }
        // Paint over the border where the tail joins the body.
        fill.setFill()
        NSRect(x: body.midX - 6, y: body.minY - 1.5, width: 10, height: 3).fill()
    }
}
