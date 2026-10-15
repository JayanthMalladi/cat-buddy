import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cat: CatController!
    private let updater = Updater()
    private var statusItem: NSStatusItem!
    private var sizeItems: [NSMenuItem] = []
    private var intervalItems: [NSMenuItem] = []
    private let quietItem = NSMenuItem(title: "Quiet Mode (only speaks when clicked)", action: #selector(AppDelegate.toggleQuiet), keyEquivalent: "")
    private let remindersItem = NSMenuItem(title: "Water & Stretch Reminders", action: #selector(AppDelegate.toggleReminders), keyEquivalent: "")
    private let noteItem = NSMenuItem(title: "To-Do Note", action: #selector(AppDelegate.toggleNote), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        cat = CatController()
        cat.start()
        setUpMenuBar()
        setUpEditShortcuts()
        updater.start()
    }

    /// The app has no menu bar of its own, so without this ⌘V wouldn't paste into the link box.
    private func setUpEditShortcuts() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Vrinda's Cat") {
                paw.isTemplate = true
                button.image = paw
            } else {
                button.title = "🐱"
            }
        }

        let menu = NSMenu()
        noteItem.state = cat.isNoteOpen ? .on : .off
        noteItem.target = self
        menu.addItem(noteItem)
        cat.onNoteOpenChange { [weak self] in
            guard let self else { return }
            self.noteItem.state = self.cat.isNoteOpen ? .on : .off
        }
        menu.addItem(.separator())
        let sayItem = NSMenuItem(title: "Say Something", action: #selector(saySomething), keyEquivalent: "")
        quietItem.state = cat.isQuiet ? .on : .off
        remindersItem.state = cat.remindersOn ? .on : .off
        let resetItem = NSMenuItem(title: "Bring Cat Back", action: #selector(resetPosition), keyEquivalent: "")
        for item in [sayItem, quietItem, remindersItem, resetItem] {
            item.target = self
            menu.addItem(item)
        }

        let sizeMenu = NSMenu()
        for (index, option) in CatController.sizes.enumerated() {
            let item = NSMenuItem(title: option.name, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            sizeMenu.addItem(item)
            sizeItems.append(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        updateSizeChecks()

        let intervalMenu = NSMenu()
        for minutes in CatController.messageIntervals {
            let title = minutes < 60 ? "Every \(minutes) Minutes" : "Every Hour"
            let item = NSMenuItem(title: title, action: #selector(chooseInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            intervalMenu.addItem(item)
            intervalItems.append(item)
        }
        let intervalItem = NSMenuItem(title: "Messages", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)
        updateIntervalChecks()
        menu.addItem(.separator())
        let linkItem = NSMenuItem(title: "Set Messages Link…", action: #selector(setMessagesLink), keyEquivalent: "")
        linkItem.target = self
        menu.addItem(linkItem)
        let updateItem = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        let versionItem = NSMenuItem(title: "Vrinda's Cat, \(updater.versionLabel)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem(title: "Quit Vrinda's Cat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func saySomething() {
        cat.say()
    }

    /// Asks for the Google Sheet link Jayanth sends; it's kept only in this Mac's settings.
    @objc private func setMessagesLink() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Messages Link"
        alert.informativeText = "Paste the link to the messages sheet. Leave it empty to use the built-in messages."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = RemoteMessages.link
        field.placeholderString = "https://docs.google.com/spreadsheets/d/…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if cat.setMessagesLink(field.stringValue) {
            cat.show(field.stringValue.isEmpty ? "Okay, back to my usual messages." : "Got it! New messages coming up.")
        } else {
            cat.show("That doesn't look like a link. It should start with https://")
        }
    }

    @objc private func checkForUpdates() {
        Task {
            switch await updater.check() {
            case .upToDate: cat.show("I'm already up to date!")
            case .updating: cat.show("Updating… back in a second!")
            case .unavailable(let reason): cat.show(reason)
            }
        }
    }

    @objc private func toggleNote() {
        cat.isNoteOpen.toggle()
    }

    @objc private func toggleReminders() {
        cat.remindersOn.toggle()
        remindersItem.state = cat.remindersOn ? .on : .off
    }

    @objc private func toggleQuiet() {
        cat.isQuiet.toggle()
        quietItem.state = cat.isQuiet ? .on : .off
        remindersItem.state = cat.remindersOn ? .on : .off
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        cat.scale = CatController.sizes[sender.tag].scale
        updateSizeChecks()
    }

    @objc private func chooseInterval(_ sender: NSMenuItem) {
        cat.messageMinutes = sender.tag
        updateIntervalChecks()
    }

    private func updateIntervalChecks() {
        for item in intervalItems {
            item.state = item.tag == cat.messageMinutes ? .on : .off
        }
    }

    private func updateSizeChecks() {
        for item in sizeItems {
            item.state = abs(CatController.sizes[item.tag].scale - cat.scale) < 0.01 ? .on : .off
        }
    }

    @objc private func resetPosition() {
        cat.resetPosition()
    }
}
