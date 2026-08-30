import FloaterCore
import AppKit
import Combine

/// The menu bar item is the only chrome an accessory app gets: it is how you
/// hide the pill, flip the two settings, and quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let panel: FloatingPanelController

    init(model: AppModel, panel: FloatingPanelController) {
        self.model = model
        self.panel = panel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "timer", accessibilityDescription: "Floater"
            )
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(item(
            panel.isVisible ? "Hide Floater" : "Show Floater",
            #selector(toggleVisibility)
        ))
        menu.addItem(item("Open Task List", #selector(openList)))
        menu.addItem(.separator())

        let sound = item("Sound", #selector(toggleSound))
        sound.state = model.soundEnabled ? .on : .off
        menu.addItem(sound)

        let takeover = item("Full-screen alert when time is up", #selector(toggleTakeover))
        takeover.state = model.takeoverEnabled ? .on : .off
        menu.addItem(takeover)

        menu.addItem(.separator())
        menu.addItem(item("Quit Floater", #selector(quit), key: "q"))
    }

    private var statusLine: String {
        switch model.phase {
        case .running: return "\(model.remainingText) left — \(model.activeTitle)"
        case .paused: return "Paused — \(model.activeTitle)"
        case .elapsed: return "Time's up — \(model.activeTitle)"
        case .idle:
            let open = model.openTasks.count
            return open == 0 ? "No tasks" : "\(open) task\(open == 1 ? "" : "s") waiting"
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    @objc private func toggleVisibility() { panel.toggleVisibility() }

    @objc private func openList() {
        if !panel.isVisible { panel.show() }
        model.mode = .expanded
    }

    @objc private func toggleSound() { model.soundEnabled.toggle() }
    @objc private func toggleTakeover() { model.takeoverEnabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
