import FloaterCore
import AppKit
import SwiftUI

/// Full-screen transparent panels used for the confetti burst and the time-up
/// takeover. The confetti one is click-through; the takeover is not.
@MainActor
final class OverlayWindowController {
    private var panel: FloatingPanel?
    private let interactive: Bool

    init(interactive: Bool) {
        self.interactive = interactive
    }

    var isShowing: Bool { panel != nil }

    func show<Content: View>(on screen: NSScreen?, @ViewBuilder content: () -> Content) {
        dismiss()
        let target = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = target?.frame else { return }

        let overlay = FloatingPanel(contentRect: frame, interactive: interactive)
        overlay.level = .screenSaver
        overlay.hasShadow = false
        overlay.isMovableByWindowBackground = false
        let hosting = NSHostingView(rootView: content())
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        overlay.contentView = hosting
        overlay.setFrame(frame, display: true)
        overlay.orderFrontRegardless()
        if interactive { overlay.makeKeyAndOrderFront(nil) }
        panel = overlay
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Converts a screen point into the overlay's own coordinate space.
    func localPoint(from screenPoint: CGPoint) -> CGPoint {
        guard let frame = panel?.frame else { return screenPoint }
        return CGPoint(x: screenPoint.x - frame.minX, y: screenPoint.y - frame.minY)
    }
}
