import AppKit
import SwiftUI

/// NSWindow subclass that refuses to close and always stays key.
class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func close() { /* no-op — cannot be closed by the system */ }
}

/// Manages the full-screen kiosk overlay: questions on the primary screen,
/// dark blocker windows on every secondary screen. Handles monitor hotplug.
class OverlayWindowController {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private var primaryWindow: KioskWindow?
    private var blockerWindows: [CGDirectDisplayID: KioskWindow] = [:]
    private var screenObserver: Any?

    func show(questionStore: QuestionStore, onComplete: @escaping () -> Void) {
        print("\(debugMarker) OverlayWindowController.show called")
        guard let mainScreen = NSScreen.main else {
            print("\(debugMarker) OverlayWindowController.show no NSScreen.main available")
            return
        }

        // Primary window — questions overlay on the main screen
        let primary = makeKioskWindow(for: mainScreen)
        let overlayView = OverlayView(questionStore: questionStore, onComplete: onComplete)
            .colorScheme(.dark)  // ensure SwiftUI renders text fields with light text
        primary.contentView = NSHostingView(rootView: overlayView)
        primaryWindow = primary

        // Blocker windows on all other screens
        for screen in NSScreen.screens where screen != mainScreen {
            addBlockerWindow(for: screen)
        }

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

        // Make key AFTER setting presentation options to avoid focus being stolen
        primary.makeKeyAndOrderFront(nil)
        print("\(debugMarker) Primary overlay shown on main screen, frame=\(primary.frame)")

        // Ensure content view can accept first responder for text fields
        if let contentView = primary.contentView {
            primary.makeFirstResponder(contentView)
            print("\(debugMarker) Set firstResponder to contentView")
        }

        // Watch for screen hotplug (monitors connected/disconnected during overlay)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenChange()
        }
    }

    func dismiss() {
        print("\(debugMarker) OverlayWindowController.dismiss called")

        // Remove screen observer
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }

        NSApp.presentationOptions = []

        // Dismiss primary window
        primaryWindow?.orderOut(nil)
        primaryWindow?.setValue(nil, forKey: "contentView")
        primaryWindow = nil

        // Dismiss all blocker windows
        for (displayID, window) in blockerWindows {
            window.orderOut(nil)
            window.setValue(nil, forKey: "contentView")
            print("\(debugMarker) Blocker window dismissed for display \(displayID)")
        }
        blockerWindows.removeAll()

        print("\(debugMarker) All overlay windows dismissed and released")
    }

    // MARK: - Window factory

    private func makeKioskWindow(for screen: NSScreen) -> KioskWindow {
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
        return window
    }

    // MARK: - Blocker windows

    private func addBlockerWindow(for screen: NSScreen) {
        let displayID = displayID(for: screen)
        guard blockerWindows[displayID] == nil else { return }

        let window = makeKioskWindow(for: screen)
        window.ignoresMouseEvents = true // no interaction needed on blockers
        let blockerView = BlockerView()
        window.contentView = NSHostingView(rootView: blockerView)
        window.orderFront(nil)
        blockerWindows[displayID] = window
        print("\(debugMarker) Blocker window added for display \(displayID), frame=\(screen.frame)")
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    // MARK: - Screen hotplug

    private func handleScreenChange() {
        print("\(debugMarker) Screen parameters changed, updating blocker windows")
        guard primaryWindow != nil else { return } // only if overlay is active

        let mainScreen = NSScreen.main
        let currentDisplayIDs = Set(NSScreen.screens.compactMap { screen -> CGDirectDisplayID? in
            guard screen != mainScreen else { return nil }
            return displayID(for: screen)
        })

        // Add blockers for newly connected screens
        for screen in NSScreen.screens where screen != mainScreen {
            let id = displayID(for: screen)
            if blockerWindows[id] == nil {
                addBlockerWindow(for: screen)
            }
        }

        // Remove blockers for disconnected screens
        for (id, window) in blockerWindows where !currentDisplayIDs.contains(id) {
            window.orderOut(nil)
            window.setValue(nil, forKey: "contentView")
            blockerWindows.removeValue(forKey: id)
            print("\(debugMarker) Removed blocker for disconnected display \(id)")
        }
    }
}

// MARK: - BlockerView

/// Dark gradient view displayed on secondary screens during bedtime overlay.
/// Matches the OverlayView background but has no interactive content.
private struct BlockerView: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.05, blue: 0.15),
                     Color(red: 0.1, green: 0.08, blue: 0.2)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
