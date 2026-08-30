import FloaterCore
import AppKit

// AppKit's entry point must run on the main actor; MainActor.assumeIsolated is
// accurate here because this is literally the main thread at startup.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // Keep the delegate alive for the process lifetime.
    withExtendedLifetime(delegate) {
        app.run()
    }
}
