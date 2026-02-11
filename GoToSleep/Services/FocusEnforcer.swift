import AppKit

/// Monitors app activation events and reclaims focus if another app activates during an overlay session.
/// This is a backup mechanism — kiosk mode's disableProcessSwitching should prevent app switching,
/// but edge cases exist (e.g., system dialogs, Accessibility-related focus changes).
class FocusEnforcer {
    private var observer: Any?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleActivation(notification)
        }
    }

    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func handleActivation(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        // Another app stole focus — reclaim it
        NSApp.activate(ignoringOtherApps: true)
    }
}
