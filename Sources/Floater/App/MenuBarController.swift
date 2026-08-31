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
    private var targetCache: [FollowUpDestination: [FollowUpTarget]] = [:]

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
        refreshTargets()
    }

    /// Repopulates the calendar / list cache without ever prompting, so a
    /// Google account connected in System Settings shows up on its own.
    private func refreshTargets() {
        Task { @MainActor in
            for destination in FollowUpDestination.allCases {
                let found = await model.knownTargets(for: destination)
                if !found.isEmpty { targetCache[destination] = found }
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshTargets()
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
        menu.addItem(item("Open Chat", #selector(openChat)))
        menu.addItem(.separator())

        let sound = item("Sound", #selector(toggleSound))
        sound.state = model.soundEnabled ? .on : .off
        menu.addItem(sound)

        let takeover = item("Full-screen alert when time is up", #selector(toggleTakeover))
        takeover.state = model.takeoverEnabled ? .on : .off
        menu.addItem(takeover)

        menu.addItem(.separator())
        for destination in FollowUpDestination.allCases {
            menu.addItem(targetMenu(for: destination))
        }

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

    @objc private func openChat() {
        if !panel.isVisible { panel.show() }
        model.tab = .chat
        model.mode = .expanded
    }

    /// A submenu per destination listing the calendars / lists that can receive
    /// follow-ups. Rendered from a cache so opening the menu never blocks on
    /// EventKit; the first "Load" fills it in.
    private func targetMenu(for destination: FollowUpDestination) -> NSMenuItem {
        let parent = NSMenuItem(
            title: destination == .calendar ? "Follow-up calendar" : "Follow-up list",
            action: nil, keyEquivalent: ""
        )
        let submenu = NSMenu()
        let selected = model.selectedTargetID(for: destination)

        let systemDefault = NSMenuItem(
            title: "System default", action: #selector(chooseTarget(_:)), keyEquivalent: ""
        )
        systemDefault.target = self
        systemDefault.representedObject = TargetChoice(destination: destination, id: nil)
        systemDefault.state = selected == nil ? .on : .off
        submenu.addItem(systemDefault)
        submenu.addItem(.separator())

        let cached = targetCache[destination] ?? []
        if cached.isEmpty {
            let placeholder = NSMenuItem(
                title: "Grant access\u{2026}", action: #selector(loadTargets(_:)), keyEquivalent: ""
            )
            placeholder.target = self
            placeholder.representedObject = destination.rawValue
            submenu.addItem(placeholder)
        } else {
            for target in cached {
                let entry = NSMenuItem(
                    title: target.isSystemDefault ? "\(target.label)  (default)" : target.label,
                    action: #selector(chooseTarget(_:)), keyEquivalent: ""
                )
                entry.target = self
                entry.representedObject = TargetChoice(destination: destination, id: target.id)
                entry.state = selected == target.id ? .on : .off
                submenu.addItem(entry)
            }
        }
        parent.submenu = submenu
        return parent
    }

    private final class TargetChoice: NSObject {
        let destination: FollowUpDestination
        let id: String?
        init(destination: FollowUpDestination, id: String?) {
            self.destination = destination
            self.id = id
        }
    }

    @objc private func chooseTarget(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? TargetChoice else { return }
        model.selectTarget(choice.id, for: choice.destination)
    }

    /// Asks for access if needed, then caches the list for the next menu open.
    @objc private func loadTargets(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let destination = FollowUpDestination(rawValue: raw) else { return }
        Task { @MainActor in
            self.targetCache[destination] = await self.model.availableTargets(for: destination)
        }
    }

    @objc private func toggleSound() { model.soundEnabled.toggle() }
    @objc private func toggleTakeover() { model.takeoverEnabled.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
