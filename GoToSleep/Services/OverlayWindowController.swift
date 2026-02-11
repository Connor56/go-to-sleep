import AppKit
import SwiftUI

/// NSWindow subclass that refuses to close and always stays key.
class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func close() { /* no-op — cannot be closed by the system */ }
}

/// Manages the full-screen kiosk overlay window.
class OverlayWindowController {
    private var window: KioskWindow?

    func show(questions: [Question], onComplete: @escaping () -> Void) {
        guard let screen = NSScreen.main else { return }

        let window = KioskWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = true
        window.backgroundColor = .black
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let overlayView = OverlayView(questions: questions, onComplete: onComplete)
        window.contentView = NSHostingView(rootView: overlayView)

        window.makeKeyAndOrderFront(nil)

        // Kiosk presentation options — blocks Cmd+Tab, force quit, hides dock/menu
        // CRITICAL: .disableProcessSwitching MUST include .hideDock or it crashes
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
        ]

        self.window = window
    }

    func dismiss() {
        NSApp.presentationOptions = []
        window?.orderOut(nil)
        // Use the NSWindow direct close (bypass our KioskWindow override)
        window?.setValue(nil, forKey: "contentView")
        window = nil
    }
}
