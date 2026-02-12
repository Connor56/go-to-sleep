import AppKit

/// Monitors app activation events and reclaims focus if another app activates during an overlay session.
/// This is a backup mechanism — kiosk mode's disableProcessSwitching should prevent app switching,
/// but edge cases exist (e.g., system dialogs, Accessibility-related focus changes).
class FocusEnforcer {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private var observer: Any?

    func start() {
        print("\(debugMarker) FocusEnforcer.start called")
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }
    }

    func stop() {
        print("\(debugMarker) FocusEnforcer.stop called")
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
            print("\(debugMarker) FocusEnforcer observer removed")
        }
    }

    private func handleActivation(_ notification: Notification) {
        print("\(debugMarker) FocusEnforcer.handleActivation notification received")
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        // Another app stole focus — reclaim it
        print("\(debugMarker) Focus stolen by \(app.bundleIdentifier ?? "unknown"), re-activating app")
        NSApp.activate(ignoringOtherApps: true)
    }
}
