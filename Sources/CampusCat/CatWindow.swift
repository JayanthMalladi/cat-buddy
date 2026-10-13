import AppKit

/// Borderless, transparent, always-on-top panel that never takes focus.
final class CatPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        isMovable = false   // CatView moves the window itself
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the sprite, moves the window when dragged and reports clicks.
final class CatView: NSView {
    let sprite = CALayer()
    var onClick: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private(set) var isTracking = false

    private var mouseDownScreen = NSPoint.zero
    private var windowOriginAtDown = NSPoint.zero
    private var dragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        sprite.contentsGravity = .resize
        sprite.frame = bounds
        sprite.actions = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "contents": NSNull()]
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sprite.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Moves the sprite up or down inside the window (points).
    func setOffsetY(_ offset: CGFloat) {
        sprite.bounds = CGRect(origin: .zero, size: bounds.size)
        sprite.position = CGPoint(x: bounds.midX, y: bounds.midY + offset)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isTracking = true
        dragged = false
        mouseDownScreen = NSEvent.mouseLocation
        windowOriginAtDown = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - mouseDownScreen.x
        let dy = now.y - mouseDownScreen.y
        if !dragged && hypot(dx, dy) < 3 { return }
        dragged = true
        window.setFrameOrigin(NSPoint(x: windowOriginAtDown.x + dx, y: windowOriginAtDown.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        isTracking = false
        if dragged {
            onDragEnd?()
        } else {
            onClick?()
        }
    }

    /// True when the given screen point lands on a visible pixel of the cat.
    func hitsCat(atScreenPoint screenPoint: NSPoint, image: CGImage?) -> Bool {
        guard let window = window, let image = image, let rootLayer = layer else { return false }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(windowPoint, from: nil)
        let p = sprite.convert(viewPoint, from: rootLayer)
        let size = sprite.bounds.size
        guard size.width > 0, size.height > 0,
              p.x >= 0, p.y >= 0, p.x < size.width, p.y < size.height else { return false }
        let x = Int(p.x / size.width * CGFloat(image.width))
        let yFromTop = Int((1 - p.y / size.height) * CGFloat(image.height))
        return alpha(of: image, x: x, y: min(max(yFromTop, 0), image.height - 1)) > 0
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // Shift the image so pixel (x, y from the top) covers the 1x1 context.
            context.draw(image, in: CGRect(x: -x, y: y + 1 - image.height,
                                           width: image.width, height: image.height))
        }
        return pixel[3]
    }
}
