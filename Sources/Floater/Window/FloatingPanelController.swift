import FloaterCore
import AppKit
import SwiftUI
import Combine

/// Owns the pill panel: how big it is in each mode, where it lives, and keeping
/// it inside a display that actually exists.
@MainActor
final class FloatingPanelController {
    static let defaultCollapsed = CGSize(width: 300, height: 56)
    static let defaultExpanded = CGSize(width: 380, height: 560)

    /// The pill keeps a fixed height; only the expanded panel resizes freely.
    static let collapsedBounds = (min: CGSize(width: 240, height: 56),
                                  max: CGSize(width: 640, height: 56))
    static let expandedBounds = (min: CGSize(width: 320, height: 380),
                                 max: CGSize(width: 900, height: 1100))

    let panel: FloatingPanel
    private let model: AppModel
    private let prefs: Preferences
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, prefs: Preferences) {
        self.model = model
        self.prefs = prefs
        let size = Self.clampSize(prefs.collapsedSize ?? Self.defaultCollapsed, to: Self.collapsedBounds)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))

        panel.onCancel = { [weak model] in model?.mode = .collapsed }
        panel.onCopy = { [weak model] in
            guard let text = model?.clipboardTextForSelection() else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return true
        }

        // The corner grip drives `resizeBy` directly, so dragging the corner
        // works regardless of how the borderless window handles resize edges.
        // The box defers capturing `self`, which does not exist yet.
        let resizer = ResizeBox()
        let hosting = NSHostingView(
            rootView: RootView()
                .environmentObject(model)
                .environment(\.resizeWindow, { delta in resizer.handler?(delta) })
        )
        // Without this the hosting view pushes SwiftUI's intrinsic size onto the
        // window as Auto Layout constraints, which override minSize/maxSize and
        // stop the panel collapsing back to pill height.
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        defer { resizer.handler = { [weak self] delta in self?.resizeBy(delta) } }

        placeAtSavedOrDefaultOrigin(size: size)

        model.$mode
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] mode in self?.apply(mode: mode) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .sink { [weak self] _ in
                guard let self else { return }
                self.prefs.panelOrigin = self.panel.frame.origin
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.clampToScreen(animate: false) }
            .store(in: &cancellables)
    }

    func show() { panel.orderFrontRegardless() }

    /// Forgets a saved size and position and puts the pill back somewhere
    /// obviously reachable.
    func resetGeometry() {
        prefs.collapsedSize = nil
        prefs.expandedSize = nil
        prefs.panelOrigin = nil
        placeAtSavedOrDefaultOrigin(size: Self.defaultCollapsed)
        panel.invalidateShadow()
    }

    func toggleVisibility() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
    }

    var isVisible: Bool { panel.isVisible }

    /// Screen-space centre of the pill, used as the confetti launch point.
    var anchorPoint: CGPoint { CGPoint(x: panel.frame.midX, y: panel.frame.midY) }

    // MARK: - Sizing

    private func size(for mode: AppModel.Mode) -> CGSize {
        switch mode {
        case .collapsed:
            return Self.clampSize(prefs.collapsedSize ?? Self.defaultCollapsed, to: Self.collapsedBounds)
        case .expanded:
            return Self.clampSize(prefs.expandedSize ?? Self.defaultExpanded, to: Self.expandedBounds)
        }
    }

    private var currentBounds: (min: CGSize, max: CGSize) {
        model.mode == .collapsed ? Self.collapsedBounds : Self.expandedBounds
    }

    private func rememberSize() {
        switch model.mode {
        case .collapsed: prefs.collapsedSize = panel.frame.size
        case .expanded: prefs.expandedSize = panel.frame.size
        }
    }

    /// Corner-grip resize. Grows right and down, keeping the top-left corner put.
    private func resizeBy(_ delta: CGSize) {
        let bounds = currentBounds
        let current = panel.frame
        let target = Self.clampSize(
            CGSize(width: current.width + delta.width, height: current.height + delta.height),
            to: bounds
        )
        guard target != current.size else { return }
        let frame = NSRect(
            x: current.minX,
            y: current.maxY - target.height,
            width: target.width,
            height: target.height
        )
        panel.setFrame(clamped(frame), display: true)
        panel.invalidateShadow()
        rememberSize()
    }

    private static func clampSize(_ size: CGSize, to bounds: (min: CGSize, max: CGSize)) -> CGSize {
        CGSize(
            width: min(max(size.width, bounds.min.width), bounds.max.width),
            height: min(max(size.height, bounds.min.height), bounds.max.height)
        )
    }

    // MARK: - Layout

    private func apply(mode: AppModel.Mode) {
        let target = size(for: mode)
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
        // The native shadow is derived from the content's alpha; without this it
        // keeps the shape it had before the resize.
        panel.invalidateShadow()

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

    private func placeAtSavedOrDefaultOrigin(size: CGSize) {
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
        let visible = host.visibleFrame
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// Holds the resize callback so the hosting view can be built before the
/// controller finishes initialising.
@MainActor
private final class ResizeBox {
    var handler: ((CGSize) -> Void)?
}

/// Lets a SwiftUI view ask the window to resize itself.
private struct ResizeWindowKey: EnvironmentKey {
    static let defaultValue: ((CGSize) -> Void)? = nil
}

extension EnvironmentValues {
    var resizeWindow: ((CGSize) -> Void)? {
        get { self[ResizeWindowKey.self] }
        set { self[ResizeWindowKey.self] = newValue }
    }
}
