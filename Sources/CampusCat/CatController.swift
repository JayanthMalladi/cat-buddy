import AppKit

/// Owns the cat window and runs the state machine.
///
/// curledSleeping --hover (+ a message)--> stretching -> yawning
///     -> one of curious | happy | awake | yawning -> resting -> curledSleeping
/// Clicking shows a message (with a cooldown shared with hover messages).
/// Timed messages (Messages menu) and reminders (reminders.json) play a short pose and speak,
/// then she goes back to sleep.
@MainActor
final class CatController: NSObject {
    private let manifest: Manifest
    private let frameStore: FrameStore
    private let messages = Messages()
    private let reminders = Reminders()
    private let bubble = SpeechBubble()
    private let panel: CatPanel
    private let view: CatView
    private let player: SpritePlayer

    private(set) var state: CatState = .curledSleeping
    private var stateEnteredAt = Date()
    /// Animations still to play in the current sequence; when it runs out she sleeps again.
    private var queue: [CatState] = []

    // Hover: the pointer has to rest on the cat briefly, and leave again before the next action.
    private var hoverStartedAt: Date?
    private var hoverArmed = true
    private let hoverDwell: TimeInterval = 0.4

    private var nextMessageAt = Date()
    private var lastInteractiveMessageAt = Date.distantPast

    private var tickTimer: Timer?
    private var hoverTimer: Timer?

    // Timing knobs, in seconds.
    /// Minimum gap between messages from hovering or clicking.
    private let interactiveMessageCooldown: TimeInterval = 20
    /// How long the resting pose lasts before she curls back up.
    private let restingLingers: TimeInterval = 6

    /// Message interval choices offered in the menu bar, in minutes.
    static let messageIntervals: [Int] = [5, 15, 30, 60]

    /// Minutes between timed messages.
    var messageMinutes: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: "messageMinutes")
            return saved > 0 ? saved : 15
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "messageMinutes")
            scheduleNextMessage()
        }
    }

    var remindersOn: Bool {
        get { UserDefaults.standard.object(forKey: "remindersOn") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "remindersOn")
            if newValue { reminders.restart() }
        }
    }

    private func scheduleNextMessage() {
        nextMessageAt = Date().addingTimeInterval(TimeInterval(messageMinutes * 60))
    }

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
        scheduleNextMessage()
        reminders.restart()
        enter(.curledSleeping)

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
        view.setOffsetY((spec.offsetY ?? 0) * scale)
        player.play(frameStore.frames(for: spec), fps: spec.fps, loop: spec.loop) { [weak self] in
            self?.finished(newState)
        }
    }

    /// A one-shot animation reached its last frame.
    private func finished(_ finishedState: CatState) {
        guard finishedState == state else { return }
        advance()
    }

    /// Plays the next animation in the sequence, or goes back to sleep when it's done.
    private func advance() {
        enter(queue.isEmpty ? .curledSleeping : queue.removeFirst())
    }

    /// Starts a sequence, but only while she's asleep, so a sequence always plays to the end.
    private func act(_ sequence: [CatState]) -> Bool {
        guard state == .curledSleeping, let first = sequence.first else { return false }
        queue = Array(sequence.dropFirst())
        enter(first)
        return true
    }

    /// The pointer has rested on the sleeping cat: she says something and runs through her routine.
    private func hovered() {
        let middleOptions: [CatState] = [.curious, .happy, .awake, .yawning]
        let middle = middleOptions.randomElement()!
        if act([.stretching, .yawning, middle, .resting]) {
            sayInteractive(force: false)
        }
    }

    /// A click shows a message (even in Quiet Mode, since she was asked), subject to the cooldown.
    private func clicked() {
        sayInteractive(force: true)
    }

    @objc private func tick() {
        let now = Date()
        // Resting loops, so it ends on a timer.
        if state == .resting && now.timeIntervalSince(stateEnteredAt) > restingLingers {
            advance()
        }

        if now > nextMessageAt {
            scheduleNextMessage()
            if !isQuiet, let text = messages.next() {
                _ = act([.resting])
                bubble.show(text, above: panel)
            }
        }

        if remindersOn, let reminder = reminders.due(at: now), !isQuiet {
            _ = act([reminder.animation.flatMap(CatState.init(rawValue:)) ?? .resting])
            bubble.show(reminder.text, above: panel)
        }
    }

    // MARK: - Messages

    /// Shows a random preset line (from the menu: always).
    func say() {
        guard let text = messages.next() else { return }
        bubble.show(text, above: panel)
    }

    /// Hover and click messages share one cooldown so they can't pile up.
    private func sayInteractive(force: Bool) {
        if isQuiet && !force { return }
        guard Date().timeIntervalSince(lastInteractiveMessageAt) >= interactiveMessageCooldown else { return }
        lastInteractiveMessageAt = Date()
        say()
    }

    // MARK: - Mouse pass-through

    @objc private func updateClickThrough() {
        if view.isTracking {
            panel.ignoresMouseEvents = false
            hoverArmed = false   // a drag shouldn't also trigger an action
            return
        }
        let mouse = NSEvent.mouseLocation
        let overCat = panel.frame.contains(mouse) && view.hitsCat(atScreenPoint: mouse, image: player.currentImage)
        if panel.ignoresMouseEvents == overCat {
            panel.ignoresMouseEvents = !overCat
        }
        updateHover(overCat: overCat)
    }

    private func updateHover(overCat: Bool) {
        guard overCat else {
            hoverStartedAt = nil
            hoverArmed = true
            return
        }
        // Pressing the button (to drag) uses up this hover.
        if NSEvent.pressedMouseButtons != 0 { hoverArmed = false }
        guard hoverArmed else { return }
        let started = hoverStartedAt ?? Date()
        hoverStartedAt = started
        if Date().timeIntervalSince(started) >= hoverDwell {
            hoverArmed = false
            hovered()
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
}
