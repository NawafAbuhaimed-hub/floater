import FloaterCore
import AppKit

/// A borderless, non-activating panel that sits above every other window.
///
/// `.nonactivatingPanel` is what lets you click and type into Floater without
/// pulling focus away from whatever app you were working in, while still being
/// able to become key so the text field receives keystrokes.
final class FloatingPanel: NSPanel {
    init(contentRect: NSRect, interactive: Bool = true) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above normal windows and fullscreen app content, below system alerts.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = interactive
        if !interactive { ignoresMouseEvents = true }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape collapses instead of beeping.
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// Cmd-C reaches the window only when no text field consumed it first, so
    /// this copies the selected task without ever stealing copy from a field.
    var onCopy: (() -> Bool)?
    @objc func copy(_ sender: Any?) {
        _ = onCopy?()
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(copy(_:)) { return onCopy != nil }
        return super.responds(to: selector)
    }
}
