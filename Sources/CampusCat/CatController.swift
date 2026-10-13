import AppKit

/// Owns the cat window and runs the state machine.
///
/// resting --click--> waking --> awake --click--> curious | happy | stretching | walking
/// awake --(idle)--> resting (sometimes via yawning)
/// resting --(now and then)--> yawning --> resting
/// resting --(long idle)--> yawning --> curledSleeping --click--> waking
@MainActor
final class CatController: NSObject {
    private let manifest: Manifest
    private let frameStore: FrameStore
    private let messages = Messages()
    private let bubble = SpeechBubble()
    private let panel: CatPanel
    private let view: CatView
    private let player: SpritePlayer

    private(set) var state: CatState = .resting
    private var stateEnteredAt = Date()
    private var lastInteraction = Date()
    private var goingToSleep = false
    private var sayAfterWaking = false

    private var lastMessageAt = Date.distantPast
    private var nextSpontaneousMessage = Date().addingTimeInterval(CatController.spontaneousGap())

    private var walkDirection: CGFloat = 1
    private var walkUntil = Date()
    private var walkTimer: Timer?

    private var tickTimer: Timer?
    private var hoverTimer: Timer?

    // Timing knobs, in seconds.
    private let awakeLingers: TimeInterval = 15
    private let fallAsleepAfter: TimeInterval = 10 * 60
    private let messageCooldown: TimeInterval = 60
    private let walkSpeed: CGFloat = 45   // points per second

    private static func spontaneousGap() -> TimeInterval { .random(in: 25 * 60...50 * 60) }

    var isQuiet: Bool {
        get { UserDefaults.standard.bool(forKey: "quiet") }
        set {
            UserDefaults.standard.set(newValue, forKey: "quiet")
            if newValue { bubble.hide() }
        }
    }

    /// Size choices offered in the menu bar, as a multiple of the art's natural size.
    static let sizes: [(name: String, scale: CGFloat)] = [
        ("Small", 0.7), ("Medium", 1.0), ("Large", 1.4), ("Extra Large", 1.8),
    ]

    private static func savedScale() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: "catScale")
        return saved > 0 ? CGFloat(saved) : 1
    }

    /// Current size multiplier. Changing it resizes the cat, keeping her feet in place.
    var scale: CGFloat {
        get { Self.savedScale() }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: "catScale")
            applyScale()
        }
    }

    private let baseSize: NSSize

    override init() {
        let manifest = Manifest.load()
        let frameStore = FrameStore()
        self.manifest = manifest
        self.frameStore = frameStore
        let first = frameStore.frames(for: manifest.spec(.resting)).first
        let pixelSize = first.map { NSSize(width: $0.width, height: $0.height) } ?? NSSize(width: 427, height: 367)
        baseSize = NSSize(width: pixelSize.width * manifest.pointsPerPixel,
                          height: pixelSize.height * manifest.pointsPerPixel)
        let scale = Self.savedScale()
        let size = NSSize(width: ceil(baseSize.width * scale), height: ceil(baseSize.height * scale))
        let view = CatView(frame: NSRect(origin: .zero, size: size))
        panel = CatPanel(size: size)
        self.view = view
        player = SpritePlayer(layer: view.sprite)
        super.init()

        panel.contentView = view
        view.onClick = { [weak self] in self?.clicked() }
        view.onDragEnd = { [weak self] in self?.savePosition() }
    }

    func start() {
        panel.setFrameOrigin(savedOrDefaultOrigin())
        panel.orderFrontRegardless()
        enter(.resting)

        let tick = Timer(timeInterval: 1, target: self, selector: #selector(tick),
                         userInfo: nil, repeats: true)
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        // Let clicks fall through to whatever is behind the transparent parts.
        let hover = Timer(timeInterval: 1.0 / 15, target: self, selector: #selector(updateClickThrough),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(hover, forMode: .common)
        hoverTimer = hover
    }

    // MARK: - State machine

    private func enter(_ newState: CatState) {
        state = newState
        stateEnteredAt = Date()
        let spec = manifest.spec(newState)

        if let walkTimer = walkTimer {
            walkTimer.invalidate()
            self.walkTimer = nil
            savePosition()
        }
        if newState == .walking {
            startWalking()
        } else {
            view.setFacingLeft(false)
        }
        view.setOffsetY((spec.offsetY ?? 0) * scale)

        player.play(frameStore.frames(for: spec), fps: spec.fps, loop: spec.loop) { [weak self] in
            self?.finished(newState)
        }
    }

    /// A one-shot animation reached its last frame.
    private func finished(_ finishedState: CatState) {
        guard finishedState == state else { return }
        switch finishedState {
        case .yawning where goingToSleep:
            goingToSleep = false
            enter(.curledSleeping)
        case .waking:
            enter(.awake)
            if sayAfterWaking { say() }
            sayAfterWaking = false
        default:
            let next = manifest.spec(finishedState).next.flatMap(CatState.init(rawValue:)) ?? .resting
            enter(next)
        }
    }

    private func clicked() {
        lastInteraction = Date()
        goingToSleep = false
        switch state {
        case .resting, .curledSleeping, .yawning:
            sayAfterWaking = Double.random(in: 0..<1) < 0.35
            enter(.waking)
        case .awake:
            let reaction = weightedPick([(.curious, 3), (.happy, 3), (.walking, 2), (.stretching, 1)])
            enter(reaction)
            if reaction == .happy { say() }
        case .walking:
            enter(.awake)
        case .waking, .curious, .happy, .stretching:
            break   // let the current animation finish
        }
    }

    @objc private func tick() {
        let now = Date()
        let inState = now.timeIntervalSince(stateEnteredAt)
        let idle = now.timeIntervalSince(lastInteraction)

        switch state {
        case .awake where inState > awakeLingers:
            enter(Double.random(in: 0..<1) < 0.3 ? .yawning : .resting)
        case .resting where idle > fallAsleepAfter:
            goingToSleep = true
            enter(.yawning)
        case .resting where inState > 60 && Double.random(in: 0..<1) < 1.0 / 240:
            enter(.yawning)   // about one yawn every four minutes
        case .walking where now > walkUntil:
            enter(.awake)
        default:
            break
        }

        if now > nextSpontaneousMessage {
            nextSpontaneousMessage = now.addingTimeInterval(Self.spontaneousGap())
            if state == .resting || state == .awake { say() }
        }
    }

    // MARK: - Walking

    private func startWalking() {
        walkUntil = Date().addingTimeInterval(.random(in: 4...7))
        if let screen = (panel.screen ?? NSScreen.main)?.visibleFrame {
            // Head toward the side with more room.
            let roomRight = screen.maxX - panel.frame.maxX
            let roomLeft = panel.frame.minX - screen.minX
            walkDirection = roomRight >= roomLeft ? 1 : -1
        }
        view.setFacingLeft(walkDirection < 0)   // the walking art faces right

        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(stepWalk),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        walkTimer = timer
    }

    @objc private func stepWalk(_ timer: Timer) {
        guard !view.isTracking else { return }
        var origin = panel.frame.origin
        origin.x += walkDirection * walkSpeed * CGFloat(timer.timeInterval)
        if let screen = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if origin.x < screen.minX || origin.x + panel.frame.width > screen.maxX {
                walkDirection *= -1
                view.setFacingLeft(walkDirection < 0)
                origin.x = min(max(origin.x, screen.minX), screen.maxX - panel.frame.width)
            }
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - Messages

    /// Shows a preset line unless quiet mode or the cooldown says not to.
    func say(force: Bool = false) {
        if !force {
            guard !isQuiet, Date().timeIntervalSince(lastMessageAt) > messageCooldown else { return }
        }
        guard let text = messages.next() else { return }
        lastMessageAt = Date()
        bubble.show(text, above: panel)
    }

    // MARK: - Mouse pass-through

    @objc private func updateClickThrough() {
        if view.isTracking {
            panel.ignoresMouseEvents = false
            return
        }
        let mouse = NSEvent.mouseLocation
        let overCat = panel.frame.contains(mouse) && view.hitsCat(atScreenPoint: mouse, image: player.currentImage)
        if panel.ignoresMouseEvents == overCat {
            panel.ignoresMouseEvents = !overCat
        }
    }

    // MARK: - Position

    private func applyScale() {
        let size = NSSize(width: ceil(baseSize.width * scale), height: ceil(baseSize.height * scale))
        let old = panel.frame
        var frame = NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height)
        if let screen = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
        view.frame = NSRect(origin: .zero, size: size)
        view.setOffsetY((manifest.spec(state).offsetY ?? 0) * scale)
        savePosition()
    }

    func resetPosition() {
        panel.setFrameOrigin(defaultOrigin())
        savePosition()
    }

    private func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "catOrigin")
    }

    private func savedOrDefaultOrigin() -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: "catOrigin") {
            let origin = NSPointFromString(saved)
            let frame = NSRect(origin: origin, size: panel.frame.size)
            // Only reuse it if the cat would still be on a connected screen.
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
                return origin
            }
        }
        return defaultOrigin()
    }

    private func defaultOrigin() -> NSPoint {
        guard let screen = NSScreen.main?.visibleFrame else { return NSPoint(x: 100, y: 100) }
        return NSPoint(x: screen.maxX - panel.frame.width - 40, y: screen.minY + 10)
    }

    private func weightedPick(_ options: [(CatState, Int)]) -> CatState {
        var roll = Int.random(in: 0..<options.reduce(0) { $0 + $1.1 })
        for (option, weight) in options {
            if roll < weight { return option }
            roll -= weight
        }
        return options[0].0
    }
}
