import FloaterCore
import AppKit
import SwiftUI
import Combine

/// Owns the pill panel: its size for each mode, where it lives on screen, and
/// keeping it inside a visible display.
@MainActor
final class FloatingPanelController {
    static let collapsedSize = CGSize(width: 300, height: 56)
    static let expandedSize = CGSize(width: 360, height: 480)

    let panel: FloatingPanel
    private let model: AppModel
    private let prefs: Preferences
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, prefs: Preferences) {
        self.model = model
        self.prefs = prefs
        let size = Self.collapsedSize
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))

        let hosting = NSHostingView(rootView: RootView().environmentObject(model))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        panel.onCancel = { [weak model] in model?.mode = .collapsed }
        placeAtSavedOrDefaultOrigin()

        model.$mode
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] mode in self?.apply(mode: mode) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in
                guard let self else { return }
                prefs.panelOrigin = self.panel.frame.origin
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.clampToScreen(animate: false) }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    var isVisible: Bool { panel.isVisible }

    /// Screen-space centre of the pill, used as the confetti launch point.
    var anchorPoint: CGPoint {
        CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    }

    // MARK: - Layout

    private func apply(mode: AppModel.Mode) {
        let target = mode == .collapsed ? Self.collapsedSize : Self.expandedSize
        let current = panel.frame
        // Grow downward from the current top-left corner so the pill stays put.
        var frame = NSRect(
            x: current.minX,
            y: current.maxY - target.height,
            width: target.width,
            height: target.height
        )
        frame = clamped(frame)
        panel.setFrame(frame, display: true, animate: true)

        if mode == .expanded {
            // Becomes key without activating the app, so typing works but focus
            // stays with whatever the user was doing.
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isKeyWindow {
            // There is no direct "give key back" call; ordering out and straight
            // back in hands focus to whatever the user was actually using.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func placeAtSavedOrDefaultOrigin() {
        let size = Self.collapsedSize
        let origin: CGPoint
        if let saved = prefs.panelOrigin {
            origin = saved
        } else if let visible = NSScreen.main?.visibleFrame {
            origin = CGPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 24)
        } else {
            origin = CGPoint(x: 100, y: 100)
        }
        panel.setFrame(clamped(NSRect(origin: origin, size: size)), display: false)
    }

    private func clampToScreen(animate: Bool) {
        panel.setFrame(clamped(panel.frame), display: true, animate: animate)
    }

    /// Keeps the panel fully on a display that actually exists — covers unplugged
    /// monitors, resolution changes, and being dragged off an edge.
    private func clamped(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return frame }
        let host = screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? NSScreen.main ?? screens[0]
        let bounds = host.visibleFrame
        var result = frame
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
