import AppKit

/// The to-do list as a little yellow sticky note that sits beside the cat and follows her around.
///
/// She can add a task at any time (type in the box at the bottom and press Return), tick one off
/// by clicking it, delete one with a right-click, and tuck the note away with the – button
/// (the paw menu brings it back).
@MainActor
final class TodoNote: NSObject, NSTextFieldDelegate {
    static let openKey = "todoNoteOpen"

    private let list: TodoList
    private let panel = NotePanel()
    private let noteView = NoteView()
    private let field = NSTextField()
    private weak var cat: NSWindow?

    /// A task was ticked (true) or unticked (false).
    var onToggle: ((TodoItem, Bool) -> Void)?
    var onAdd: ((TodoItem) -> Void)?
    /// The note was tucked away or brought back (to update the menu).
    var onOpenChange: (() -> Void)?

    private let width: CGFloat = 240
    private let pad: CGFloat = 16
    /// How far the note tucks behind the cat's (mostly transparent) window.
    private let overlap: CGFloat = 12

    var isOpen: Bool {
        UserDefaults.standard.object(forKey: Self.openKey) as? Bool ?? true
    }

    init(list: TodoList) {
        self.list = list
        super.init()
        panel.contentView = noteView

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NoteStyle.font(13, .semibold)
        field.textColor = NoteStyle.ink
        field.placeholderAttributedString = NSAttributedString(string: "+ Add a task", attributes: [
            .font: NoteStyle.font(13, .semibold), .foregroundColor: NoteStyle.muted,
        ])
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.target = self
        field.action = #selector(addFromField)
        field.delegate = self
        noteView.addSubview(field)

        list.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    /// Puts the note beside the cat window (if it's open).
    func attach(to cat: NSWindow) {
        self.cat = cat
        if isOpen { show() }
    }

    func setOpen(_ open: Bool) {
        UserDefaults.standard.set(open, forKey: Self.openKey)
        open ? show() : hide()
        onOpenChange?()
    }

    private func show() {
        guard let cat else { return }
        if panel.parent !== cat {
            cat.addChildWindow(panel, ordered: .below)
        }
        place()
        panel.orderFront(nil)
    }

    private func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Keeps the note beside the cat: on her left if there's room, otherwise on her right.
    /// Called after she walks a step, is dragged or changes size.
    func place() {
        guard let cat, panel.parent === cat else { return }
        let size = panel.frame.size
        let catFrame = cat.frame
        var origin = NSPoint(x: catFrame.minX - size.width + overlap, y: catFrame.minY)
        if let screen = (cat.screen ?? NSScreen.main)?.visibleFrame {
            if origin.x < screen.minX {
                origin.x = catFrame.maxX - overlap
            }
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
            origin.y = min(max(origin.y, screen.minY), screen.maxY - size.height)
        }
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - Editing

    @objc private func addFromField() {
        let text = field.stringValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if list.add(text), let item = list.items.last {
            field.stringValue = ""
            onAdd?(item)
        } else {
            NSSound.beep()   // the note is full
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // Escape stops typing without adding anything.
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        field.stringValue = ""
        panel.makeFirstResponder(nil)
        return true
    }

    private func toggle(_ item: TodoItem) {
        guard let done = list.toggle(item.id) else { return }
        onToggle?(item, done)
    }

    // MARK: - Layout

    /// Lays the note out again from the list, top to bottom (the view is flipped).
    private func rebuild() {
        for view in noteView.subviews where view !== field {
            view.removeFromSuperview()
        }
        let inner = width - NoteStyle.shadow - pad * 2
        var y = NoteStyle.tapeOverhang + 14

        let title = label("Today", NoteStyle.font(18, .bold))
        title.frame = NSRect(x: pad, y: y, width: 120, height: 24)
        noteView.addSubview(title)

        let tuck = NSButton(title: "–", target: self, action: #selector(tuckAway))
        tuck.isBordered = false
        tuck.attributedTitle = NSAttributedString(string: "–", attributes: [
            .font: NoteStyle.font(18, .bold), .foregroundColor: NoteStyle.ink,
        ])
        tuck.setAccessibilityLabel("Tuck the note away")
        tuck.toolTip = "Tuck the note away (bring it back from the paw menu)"
        tuck.frame = NSRect(x: pad + inner - 24, y: y, width: 24, height: 24)
        noteView.addSubview(tuck)

        if !list.items.isEmpty {
            let count = label("\(list.doneCount) / \(list.items.count)", NoteStyle.font(14, .semibold))
            count.alignment = .right
            count.frame = NSRect(x: pad + inner - 24 - 64, y: y + 3, width: 58, height: 20)
            noteView.addSubview(count)
        }
        y += 24 + 8

        if list.items.isEmpty {
            let hint = label("Nothing yet. What's on today?", NoteStyle.font(13, .medium))
            hint.textColor = NoteStyle.muted
            hint.frame = NSRect(x: pad, y: y, width: inner, height: 20)
            noteView.addSubview(hint)
            y += 24
        }
        for item in list.items {
            let row = TaskRowView(item: item, frame: NSRect(x: pad, y: y, width: inner, height: 28))
            row.onToggle = { [weak self] in self?.toggle(item) }
            row.onDelete = { [weak self] in self?.list.remove(item.id) }
            noteView.addSubview(row)
            y += 28
        }
        y += 8

        noteView.separatorY = y
        y += 10
        if !list.items.isEmpty {
            let paws = PawsView(done: list.doneCount, total: list.items.count)
            paws.frame = NSRect(x: pad, y: y, width: inner, height: 20)
            paws.setAccessibilityLabel("\(list.doneCount) of \(list.items.count) tasks done")
            noteView.addSubview(paws)
            y += 20 + 10
        }

        noteView.fieldBox = NSRect(x: pad, y: y, width: inner, height: 30)
        field.frame = NSRect(x: pad + 8, y: y + 6, width: inner - 16, height: 18)
        y += 30 + pad

        let height = y + NoteStyle.shadow
        // Grow or shrink from the bottom edge, which lines up with the cat's feet.
        let old = panel.frame
        panel.setFrame(NSRect(x: old.minX, y: old.minY, width: width, height: height), display: true)
        noteView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        noteView.needsDisplay = true
        place()
    }

    @objc private func tuckAway() {
        setOpen(false)
    }

    private func label(_ text: String, _ font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = NoteStyle.ink
        return label
    }
}

/// Colours and fonts shared with the cat's pixel look.
@MainActor
enum NoteStyle {
    static let ink = NSColor(srgbRed: 0x2A / 255, green: 0x27 / 255, blue: 0x2E / 255, alpha: 1)
    static let paper = NSColor(srgbRed: 0xFF / 255, green: 0xF1 / 255, blue: 0xC9 / 255, alpha: 1)
    static let ginger = NSColor(srgbRed: 0xD3 / 255, green: 0x8B / 255, blue: 0x5A / 255, alpha: 1)
    static let brown = NSColor(srgbRed: 0x8C / 255, green: 0x4B / 255, blue: 0x2E / 255, alpha: 1)
    static let pawEmpty = NSColor(srgbRed: 0xE2 / 255, green: 0xD3 / 255, blue: 0xAC / 255, alpha: 1)
    static let muted = NSColor(srgbRed: 0x6B / 255, green: 0x66 / 255, blue: 0x70 / 255, alpha: 1)

    /// Width of the hard offset shadow under the card.
    static let shadow: CGFloat = 5
    /// How far the strip of tape sticks out above the card.
    static let tapeOverhang: CGFloat = 7
    static let border: CGFloat = 2.5

    static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let rounded = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: rounded, size: size) {
            return font
        }
        return base
    }

    /// Fills 1×1 cells of a pixel pattern (x, y, width, height, top-left origin) in a flipped view.
    static func fillPixels(_ cells: [(CGFloat, CGFloat, CGFloat, CGFloat)], in rect: NSRect, grid: CGFloat) {
        let unit = rect.width / grid
        for (x, y, w, h) in cells {
            NSRect(x: rect.minX + x * unit, y: rect.minY + y * unit, width: w * unit, height: h * unit).fill()
        }
    }

    static let paw: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (1, 1, 1, 2), (3, 0, 1, 2), (4, 0, 1, 2), (6, 1, 1, 2), (2, 4, 4, 3), (1, 5, 6, 1),
    ]
    static let tick: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (0, 3, 1, 2), (1, 4, 1, 2), (2, 5, 1, 2), (3, 4, 1, 2), (4, 3, 1, 2), (5, 2, 1, 2), (6, 1, 1, 2), (7, 0, 1, 2),
    ]
}

/// Borderless panel that can take typing without bringing the app forward.
final class NotePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true   // only the text box takes the keyboard
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The card itself: yellow paper, a dark pixel border, a hard shadow and a strip of tape.
final class NoteView: NSView {
    var separatorY: CGFloat = 0
    var fieldBox: NSRect = .zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let s = NoteStyle.shadow
        let card = NSRect(x: 0, y: NoteStyle.tapeOverhang, width: bounds.width - s,
                          height: bounds.height - NoteStyle.tapeOverhang - s)
        NoteStyle.ink.setFill()
        card.offsetBy(dx: s, dy: s).fill()
        NoteStyle.paper.setFill()
        card.fill()
        NoteStyle.ink.setStroke()
        let border = NSBezierPath(rect: card.insetBy(dx: NoteStyle.border / 2, dy: NoteStyle.border / 2))
        border.lineWidth = NoteStyle.border
        border.stroke()

        // Tape across the top.
        let tape = NSRect(x: card.midX - 30, y: 0, width: 60, height: 14)
        NoteStyle.ginger.setFill()
        tape.fill()
        let tapeEdge = NSBezierPath(rect: tape.insetBy(dx: 1, dy: 1))
        tapeEdge.lineWidth = 2
        tapeEdge.stroke()

        // Dashed line above the progress row.
        let dash = NSBezierPath()
        dash.move(to: NSPoint(x: 16, y: separatorY))
        dash.line(to: NSPoint(x: card.maxX - 16, y: separatorY))
        dash.lineWidth = 2
        dash.setLineDash([5, 4], count: 2, phase: 0)
        dash.stroke()

        // The add-a-task box.
        NSColor.white.setFill()
        fieldBox.fill()
        let box = NSBezierPath(rect: fieldBox.insetBy(dx: 1, dy: 1))
        box.lineWidth = 2
        box.stroke()
    }
}

/// One task: a pixel checkbox and its text. Click to tick, right-click to delete.
final class TaskRowView: NSView {
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?
    private let item: TodoItem
    private let label = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(item: TodoItem, frame: NSRect) {
        self.item = item
        super.init(frame: frame)
        label.frame = NSRect(x: 28, y: 5, width: frame.width - 28, height: 19)
        label.lineBreakMode = .byTruncatingTail
        label.attributedStringValue = NSAttributedString(string: item.text, attributes: [
            .font: NoteStyle.font(14, .semibold),
            .foregroundColor: item.done ? NoteStyle.muted : NoteStyle.ink,
            .strikethroughStyle: item.done ? NSUnderlineStyle.single.rawValue : 0,
        ])
        label.toolTip = item.text
        addSubview(label)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(item.text)
        setAccessibilityValue(item.done ? 1 : 0)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0, y: 5, width: 18, height: 18)
        (item.done ? NoteStyle.ginger : NSColor.white).setFill()
        box.fill()
        NoteStyle.ink.setStroke()
        let edge = NSBezierPath(rect: box.insetBy(dx: 1, dy: 1))
        edge.lineWidth = 2
        edge.stroke()
        if item.done {
            NoteStyle.ink.setFill()
            NoteStyle.fillPixels(NoteStyle.tick, in: box.insetBy(dx: 4, dy: 4), grid: 8)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onToggle?() }
    }

    override func mouseDown(with event: NSEvent) {}

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let delete = NSMenuItem(title: "Delete \"\(item.text)\"", action: #selector(deleteItem), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    @objc private func deleteItem() {
        onDelete?()
    }
}

/// A row of pixel paw prints, one per task, filled in as tasks get done.
final class PawsView: NSView {
    private let done: Int
    private let total: Int

    override var isFlipped: Bool { true }

    init(done: Int, total: Int) {
        self.done = done
        self.total = total
        super.init(frame: .zero)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let size: CGFloat = total > 7 ? 16 : 20
        for i in 0..<total {
            (i < done ? NoteStyle.brown : NoteStyle.pawEmpty).setFill()
            NoteStyle.fillPixels(NoteStyle.paw, in: NSRect(x: CGFloat(i) * (size + 4), y: (20 - size) / 2,
                                                          width: size, height: size), grid: 8)
        }
    }
}
