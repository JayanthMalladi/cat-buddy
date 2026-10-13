import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cat: CatController!
    private var statusItem: NSStatusItem!
    private let quietItem = NSMenuItem(title: "Quiet Mode (no messages)", action: #selector(AppDelegate.toggleQuiet), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        cat = CatController()
        cat.start()
        setUpMenuBar()
    }

    private func setUpMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Campus Cat") {
                paw.isTemplate = true
                button.image = paw
            } else {
                button.title = "🐱"
            }
        }

        let menu = NSMenu()
        let sayItem = NSMenuItem(title: "Say Something", action: #selector(saySomething), keyEquivalent: "")
        quietItem.state = cat.isQuiet ? .on : .off
        let resetItem = NSMenuItem(title: "Bring Cat Back", action: #selector(resetPosition), keyEquivalent: "")
        for item in [sayItem, quietItem, resetItem] {
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Campus Cat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func saySomething() {
        cat.say(force: true)
    }

    @objc private func toggleQuiet() {
        cat.isQuiet.toggle()
        quietItem.state = cat.isQuiet ? .on : .off
    }

    @objc private func resetPosition() {
        cat.resetPosition()
    }
}
