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

    func applicationDidFinishLaunching(_ notification: Notification) {
        cat = CatController()
        cat.start()
        setUpMenuBar()
        updater.start()
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

    @objc private func checkForUpdates() {
        Task {
            switch await updater.check() {
            case .upToDate: cat.show("I'm already up to date!")
            case .updating: cat.show("Updating… back in a second!")
            case .unavailable(let reason): cat.show(reason)
            }
        }
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
