import FloaterCore
import AppKit
import SwiftUI

/// A small interactive panel parked next to the pill. Used for the follow-up
/// prompt. Transparent regions stay click-through because SwiftUI returns no
/// hit target for them, so it never blocks the app underneath.
@MainActor
final class AnchoredPanelController {
    private var panel: FloatingPanel?
    private var dismissWork: DispatchWorkItem?

    var isShowing: Bool { panel != nil }

    func show<Content: View>(
        size: CGSize,
        anchoredTo anchor: NSRect,
        autoDismissAfter delay: TimeInterval? = nil,
        onAutoDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        dismiss()
        let overlay = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
        overlay.isMovableByWindowBackground = false
        let hosting = NSHostingView(rootView: content())
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        overlay.contentView = hosting
        overlay.setFrame(Self.place(size: size, near: anchor), display: true)
        // Deliberately not key: the prompt appears unannounced, and stealing the
        // caret from whatever the user is typing in would be hostile. Clicks
        // still land on a non-key non-activating panel.
        overlay.orderFrontRegardless()
        panel = overlay

        if let delay {
            let work = DispatchWorkItem { onAutoDismiss?() }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// Called once the user actually engages — only then is taking the caret
    /// justified, and the date picker needs it.
    func takeFocus() {
        panel?.makeKeyAndOrderFront(nil)
    }

    /// Stops the panel disappearing while the user is still deciding.
    func cancelAutoDismiss() {
        dismissWork?.cancel()
        dismissWork = nil
    }

    func dismiss() {
        cancelAutoDismiss()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Sits just under the pill, flipping above it when there is no room below.
    private static func place(size: CGSize, near anchor: NSRect) -> NSRect {
        let gap: CGFloat = 2
        var frame = NSRect(
            x: anchor.minX,
            y: anchor.minY - size.height + gap,
            width: size.width,
            height: size.height
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        if frame.minY < visible.minY {
            frame.origin.y = anchor.maxY - gap
        }
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }
}
