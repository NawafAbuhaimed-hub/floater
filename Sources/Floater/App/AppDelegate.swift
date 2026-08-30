import AppKit
import SwiftUI
import Combine
import FloaterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panelController: FloatingPanelController!
    private var menuBar: MenuBarController!
    private let celebration = OverlayWindowController(interactive: false)
    private let takeover = OverlayWindowController(interactive: true)
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let store: Store
        do {
            store = try Store()
        } catch {
            presentFatal("Floater could not open its task database.\n\n\(error.localizedDescription)")
            return
        }

        let prefs = Preferences()
        model = AppModel(store: store, prefs: prefs)
        panelController = FloatingPanelController(model: model, prefs: prefs)
        menuBar = MenuBarController(model: model, panel: panelController)

        model.onCelebrate = { [weak self] title in self?.celebrate(title) }
        model.onTimeUp = { [weak self] run in self?.showTimeUp(run) }
        model.onDismissTimeUp = { [weak self] in self?.takeover.dismiss() }

        // A run that ended while the machine was asleep should surface on wake.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.model.tick() }
            .store(in: &cancellables)

        Notifier.requestAuthorization()
        panelController.show()

        // A run whose deadline passed while the app was quit surfaces on launch,
        // without the chime and banner that would be stale by now.
        if model.phase == .elapsed {
            showTimeUp(
                taskTitle: model.activeTitle,
                minutes: model.activePlannedMinutes,
                silent: true
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.refresh() // flushes the in-flight run to disk
    }

    // MARK: - Celebration

    private func celebrate(_ title: String) {
        if model.soundEnabled { Sounds.celebrate() }
        let anchor = panelController.anchorPoint
        let screen = screenContaining(anchor)
        celebration.show(on: screen) { [weak self] in
            CelebrationOverlay(
                origin: self?.localPoint(anchor, on: screen) ?? .zero,
                taskTitle: title
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.celebration.dismiss()
        }
    }

    // MARK: - Time up

    private func showTimeUp(_ run: FocusRun) {
        showTimeUp(taskTitle: run.taskTitle, minutes: Int(run.plannedSeconds / 60), silent: false)
    }

    private func showTimeUp(taskTitle: String, minutes: Int, silent: Bool) {
        if !silent {
            if model.soundEnabled { Sounds.timeUp() }
            Notifier.timeUp(taskTitle: taskTitle, minutes: minutes)
        }
        guard model.takeoverEnabled else { return }
        let screen = screenContaining(panelController.anchorPoint)
        takeover.show(on: screen) { [weak self] in
            TimeUpView(
                taskTitle: taskTitle,
                minutes: minutes,
                onDone: { self?.model.completeActiveTask() },
                onExtend: { self?.model.extend(minutes: 10) },
                onStop: { self?.model.stopTimer() }
            )
        }
    }

    // MARK: - Geometry

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// AppKit screen coordinates (y up) to SwiftUI view coordinates (y down).
    private func localPoint(_ screenPoint: CGPoint, on screen: NSScreen?) -> CGPoint {
        guard let frame = screen?.frame else { return screenPoint }
        return CGPoint(x: screenPoint.x - frame.minX, y: frame.maxY - screenPoint.y)
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Floater can't start"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
