import AppKit

// Nook — a notch productivity hub.
// Runs as an accessory (no Dock icon); windows are created by NotchController.

autoreleasepool {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
