import AppKit

/// macOS dispatches the standard editing shortcuts through the Edit menu, so an
/// app without a main menu gets no Cmd-C, Cmd-V, Cmd-X, Cmd-A or Cmd-Z at all —
/// in any text field. An accessory app never shows this menu; installing it is
/// purely what makes those keystrokes reach the first responder.
enum MainMenu {
    static func install() {
        let menu = NSMenu()
        menu.addItem(appMenuItem())
        menu.addItem(editMenuItem())
        NSApp.mainMenu = menu
    }

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let submenu = NSMenu()
        submenu.addItem(
            withTitle: "Quit Floater",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.submenu = submenu
        return item
    }

    private static func editMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Edit")

        func add(_ title: String, _ action: Selector, _ key: String, shift: Bool = false) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            if shift { entry.keyEquivalentModifierMask = [.command, .shift] }
            submenu.addItem(entry)
        }

        add("Undo", Selector(("undo:")), "z")
        add("Redo", Selector(("redo:")), "z", shift: true)
        submenu.addItem(.separator())
        add("Cut", #selector(NSText.cut(_:)), "x")
        add("Copy", #selector(NSText.copy(_:)), "c")
        add("Paste", #selector(NSText.paste(_:)), "v")
        add("Select All", #selector(NSText.selectAll(_:)), "a")

        item.submenu = submenu
        return item
    }
}
