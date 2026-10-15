import AppKit

/// Owns the cat window and runs the state machine.
///
/// curledSleeping --hover--> one random action (+ a message, if the cooldown allows) -> curledSleeping
/// Clicking shows a message (with the same cooldown).
/// Every 5 minutes she wakes up and walks to the other side of the screen (no message), then
/// sleeps there. Hovering does nothing while she walks.
/// Timed messages (Messages menu) and reminders (reminders.json) play a short pose and speak,
/// then she goes back to sleep.
/// Her to-do note sits beside her. At the check-in times she asks about an unfinished task by
/// name, she celebrates each one that gets ticked off, and she passes on nudges from the sheet.
@MainActor
final class CatController: NSObject {
    private let manifest: Manifest
    private let frameStore: FrameStore
    private let messages = Messages()
    private var remoteMessages: RemoteMessages?
    private let reminders = Reminders()
    private let todos: TodoList
    private let note: TodoNote
    private let remoteControl = RemoteControl()
    /// A nudge from the sheet waiting for her to finish a walk.
    private var pendingNudge: String?
    /// Timed messages and reminders hold off until then, so they don't cover a check-in or nudge.
    private var holdChatterUntil = Date.distantPast
    private let bubble = SpeechBubble()
    private let panel: CatPanel
    private let view: CatView
    private let player: SpritePlayer

    private(set) var state: CatState = .curledSleeping
    private var stateEnteredAt = Date()
    /// Animations still to play in the current sequence; when it runs out she sleeps again.
    private var queue: [CatState] = []

    // Hover: the pointer has to rest on the cat briefly, and leave her window entirely before the
    // next action (her outline changes as she moves, so just slipping off her fur doesn't count).
    private var hoverStartedAt: Date?
    private var hoverArmed = true
    private let hoverDwell: TimeInterval = 0.4

    private var nextMessageAt = Date()
    private var lastInteractiveMessageAt = Date.distantPast

    private var nextWalkAt = Date()
    private var walkingRight = true

    private var tickTimer: Timer?
    private var hoverTimer: Timer?
    private var walkTimer: Timer?

    // Timing knobs, in seconds.
    /// Minimum gap between messages from hovering or clicking.
    private let interactiveMessageCooldown: TimeInterval = 2 * 60
    /// How long the resting pose lasts before she curls back up.
    private let restingLingers: TimeInterval = 6
    /// Gap between walks. The hidden `walkEverySeconds` default overrides it (used by CI).
    private var walkInterval: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "walkEverySeconds")
        return saved > 0 ? saved : 5 * 60
    }
    private let walkSpeed: CGFloat = 60   // points per second
    /// How far from the screen edge she stops.
    private let walkMargin: CGFloat = 40

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
        let todos = TodoList()
        self.todos = todos
        note = TodoNote(list: todos)
        super.init()

        panel.contentView = view
        view.onClick = { [weak self] in self?.clicked() }
        view.onDragEnd = { [weak self] in
            self?.savePosition()
            self?.note.place()
        }
        note.onToggle = { [weak self] item, done in self?.taskToggled(item, done: done) }
        note.onAdd = { [weak self] _ in self?.taskAdded() }
        remoteControl.onNudge = { [weak self] text in self?.pendingNudge = text }
    }

    func start() {
        panel.setFrameOrigin(savedOrDefaultOrigin())
        panel.orderFrontRegardless()
        scheduleNextMessage()
        reminders.restart()
        let remote = RemoteMessages(messages: messages)
        remote.start()
        remoteMessages = remote
        remoteControl.start()
        note.attach(to: panel)
        nextWalkAt = Date().addingTimeInterval(walkInterval)
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
        if newState != .walking { stopWalking() }
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
    /// If a walk came due during an action, she sets off as soon as the action ends.
    private func advance() {
        if !queue.isEmpty {
            enter(queue.removeFirst())
        } else if Date() >= nextWalkAt {
            startWalking()
        } else {
            enter(.curledSleeping)
        }
    }

    /// Starts a sequence, but only while she's asleep, so a sequence always plays to the end.
    private func act(_ sequence: [CatState]) -> Bool {
        guard state == .curledSleeping, let first = sequence.first else { return false }
        queue = Array(sequence.dropFirst())
        enter(first)
        return true
    }

    /// The pointer has rested on the sleeping cat: she wakes for one random action, says something
    /// if the message cooldown has passed, and goes back to sleep when the action ends.
    private func hovered() {
        let actions: [CatState] = [.stretching, .yawning, .curious, .happy, .awake, .resting]
        if act([actions.randomElement()!]) {
            sayInteractive(force: false)
        }
    }

    /// A click shows a message (even in Quiet Mode, since she was asked), subject to the cooldown.
    private func clicked() {
        guard state != .walking else { return }   // walks are silent
        sayInteractive(force: true)
    }

    @objc private func tick() {
        let now = Date()
        // Resting loops, so it ends on a timer.
        if state == .resting && now.timeIntervalSince(stateEnteredAt) > restingLingers {
            advance()
        }

        if state == .curledSleeping && now >= nextWalkAt {
            startWalking()
        }
        // Nothing else starts while she walks; it waits until she's asleep on the other side.
        guard state != .walking else { return }

        todos.rollOverIfNewDay()
        if let nudge = pendingNudge, now >= holdChatterUntil {
            pendingNudge = nil
            deliverNudge(nudge)
            return
        }
        if now >= holdChatterUntil, let isLast = CheckIns.due(at: now) {
            checkIn(isLast: isLast)
        }
        guard now >= holdChatterUntil else { return }

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

    // MARK: - Walking

    /// Walks to the far side of the screen (the side with more room), then sleeps there.
    private func startWalking() {
        queue = []
        bubble.hide()
        if let screen = (panel.screen ?? NSScreen.main)?.visibleFrame {
            walkingRight = screen.maxX - panel.frame.maxX >= panel.frame.minX - screen.minX
        }
        enter(.walking)
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(stepWalk),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        walkTimer = timer
    }

    @objc private func stepWalk(_ timer: Timer) {
        guard !view.isTracking else { return }   // being dragged: carry on from wherever she's dropped
        guard let screen = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            enter(.curledSleeping)
            return
        }
        // Worked out every step, so resizing or dragging her mid-walk still ends on screen.
        let targetX = walkingRight ? screen.maxX - panel.frame.width - walkMargin : screen.minX + walkMargin
        var origin = panel.frame.origin
        let remaining = targetX - origin.x
        let step = walkSpeed * CGFloat(timer.timeInterval)
        view.setFacingLeft(remaining < 0)   // the walking art faces right
        if abs(remaining) <= step {
            origin.x = targetX
            panel.setFrameOrigin(origin)
            enter(.curledSleeping)
        } else {
            origin.x += remaining < 0 ? -step : step
            panel.setFrameOrigin(origin)
        }
        note.place()
    }

    // MARK: - To-do list

    var isNoteOpen: Bool {
        get { note.isOpen }
        set { note.setOpen(newValue) }
    }

    /// Lets the menu keep its tick in step when the note's own – button tucks it away.
    func onNoteOpenChange(_ handler: @escaping () -> Void) {
        note.onOpenChange = handler
    }

    private func taskToggled(_ item: TodoItem, done: Bool) {
        guard done else { return }
        let left = todos.open.count
        _ = act([.happy])
        switch left {
        case 0: bubble.show("All done! I'm so proud of you.", above: panel)
        case 1: bubble.show("You did it! Just one to go.", above: panel)
        default: bubble.show("You did it! \(left) to go.", above: panel)
        }
    }

    /// The first task of an empty list gets a little hello; after that she stays quiet while typing.
    private func taskAdded() {
        guard todos.items.count == 1 else { return }
        bubble.show("Got it. I'll keep an eye on it for you.", above: panel)
    }

    /// At each check-in time she asks about the oldest unfinished task by name.
    private func checkIn(isLast: Bool) {
        let open = todos.open
        let text: String
        if todos.items.isEmpty {
            guard !isLast else { return }   // too late in the day to start a list
            text = "What are we doing today? Add a task to my note."
        } else if let first = open.first {
            if isLast {
                text = open.count == 1 ? "Last call! Did \"\(first.text)\" happen?"
                                       : "Last call! \(open.count) left, starting with \"\(first.text)\"."
            } else {
                text = "Psst. Did \"\(first.text)\" happen yet?"
            }
        } else {
            return   // everything's done; let her be
        }
        if !note.isOpen { note.setOpen(true) }
        guard !isQuiet else { return }
        _ = act([.curious])
        bubble.show(text, above: panel)
        holdChatterUntil = Date().addingTimeInterval(20)
    }

    /// A nudge typed into the sheet's Control tab. She says it even in Quiet Mode, since it's from him.
    private func deliverNudge(_ text: String) {
        _ = act([.happy])
        bubble.show(text, above: panel)
        if !todos.open.isEmpty && !note.isOpen { note.setOpen(true) }
        holdChatterUntil = Date().addingTimeInterval(20)
    }

    private func stopWalking() {
        guard let timer = walkTimer else { return }
        timer.invalidate()
        walkTimer = nil
        view.setFacingLeft(false)
        nextWalkAt = Date().addingTimeInterval(walkInterval)
        savePosition()
    }

    // MARK: - Messages

    /// Shows a random preset line (from the menu: always).
    func say() {
        guard let text = messages.next() else { return }
        bubble.show(text, above: panel)
    }

    /// Shows a line that isn't one of the preset messages (e.g. about updates).
    /// Points the messages at a new share link (see RemoteMessages).
    func setMessagesLink(_ text: String) -> Bool {
        remoteMessages?.setLink(text) ?? false
    }

    func show(_ text: String) {
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
        let inWindow = panel.frame.contains(mouse)
        let overCat = inWindow && view.hitsCat(atScreenPoint: mouse, image: player.currentImage)
        if panel.ignoresMouseEvents == overCat {
            panel.ignoresMouseEvents = !overCat
        }
        updateHover(overCat: overCat, inWindow: inWindow)
    }

    private func updateHover(overCat: Bool, inWindow: Bool) {
        guard overCat else {
            hoverStartedAt = nil
            if !inWindow { hoverArmed = true }
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
        note.place()
    }

    func resetPosition() {
        panel.setFrameOrigin(defaultOrigin())
        savePosition()
        note.place()
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
