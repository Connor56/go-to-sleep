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
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private var window: KioskWindow?

    func show(questions: [Question], onComplete: @escaping () -> Void) {
        print("\(debugMarker) OverlayWindowController.show called questionCount=\(questions.count)")
        guard let screen = NSScreen.main else {
            print("\(debugMarker) OverlayWindowController.show no NSScreen.main available")
            return
        }

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
        print("\(debugMarker) Overlay window shown at level=\(window.level.rawValue), frame=\(window.frame)")

        // Kiosk presentation options — blocks Cmd+Tab, force quit, hides dock/menu
        // CRITICAL: .disableProcessSwitching MUST include .hideDock or it crashes
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
        ]
        print("\(debugMarker) NSApp.presentationOptions set for kiosk mode")

        self.window = window
    }

    func dismiss() {
        print("\(debugMarker) OverlayWindowController.dismiss called")
        NSApp.presentationOptions = []
        window?.orderOut(nil)
        // Use the NSWindow direct close (bypass our KioskWindow override)
        window?.setValue(nil, forKey: "contentView")
        window = nil
        print("\(debugMarker) Overlay window dismissed and released")
    }
}
