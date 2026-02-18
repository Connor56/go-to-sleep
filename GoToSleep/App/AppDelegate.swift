import AppKit
import ServiceManagement
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private let showOverlayNotificationName = Notification.Name("com.gotosleep.showOverlayNow")
    private let overlayController = OverlayWindowController()
    private let focusEnforcer = FocusEnforcer()
    private let audioMuter = AudioMuter()
    private let questionStore = QuestionStore()
    private var isShowingOverlay = false
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("\(debugMarker) applicationDidFinishLaunching args=\(CommandLine.arguments)")
        audioMuter.restoreIfNeeded()
        registerOverlayNotificationObserver()

        // Check if launched with --bedtime flag (by the daemon)
        if CommandLine.arguments.contains("--bedtime") {
            print("\(debugMarker) Detected --bedtime launch, showing overlay")
            showOverlay()
        }
    }

    func showOverlay() {
        print("\(debugMarker) showOverlay called. isShowingOverlay=\(isShowingOverlay)")
        guard !isShowingOverlay else { return }
        isShowingOverlay = true

        Paths.ensureDirectoryExists()
        Paths.removeFile(at: Paths.sessionCompletedPath)

        let count = AppSettings.shared.questionsPerSession
        let questions = questionStore.selectQuestions(count: count)
        print("\(debugMarker) selectedQuestionsCount=\(questions.count), requestedCount=\(count)")

        guard !questions.isEmpty else {
            print("\(debugMarker) No questions available, aborting overlay")
            isShowingOverlay = false
            return
        }

        audioMuter.mute()
        focusEnforcer.start()
        NSApp.activate(ignoringOtherApps: true)

        overlayController.show(questions: questions) { [weak self] in
            self?.completeSession()
        }
    }

    func dismissOverlay() {
        print("\(debugMarker) dismissOverlay called")
        overlayController.dismiss()
        audioMuter.unmute()
        focusEnforcer.stop()
        isShowingOverlay = false
    }

    func showSettingsWindow() {
        print("\(debugMarker) AppDelegate.showSettingsWindow() called")
        NSApp.activate(ignoringOtherApps: true)
        print("\(debugMarker) Existing settingsWindowController? \(settingsWindowController != nil)")

        if settingsWindowController == nil {
            print("\(debugMarker) Creating settings window controller")
            let settingsHostingController = NSHostingController(rootView: SettingsView())
            let settingsWindow = NSWindow(contentViewController: settingsHostingController)
            settingsWindow.title = "Go To Sleep Settings"
            settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow.setContentSize(NSSize(width: 400, height: 320))
            settingsWindow.center()
            settingsWindow.isReleasedWhenClosed = false

            settingsWindowController = NSWindowController(window: settingsWindow)
        }

        print("\(debugMarker) Presenting settings window")
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func completeSession() {
        print("\(debugMarker) completeSession called")
        // Write completion marker so the daemon knows we finished legitimately
        Paths.writeTimestamp(to: Paths.sessionCompletedPath)
        dismissOverlay()
    }

    private func registerOverlayNotificationObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: showOverlayNotificationName,
            object: "com.gotosleep.app",
            queue: .main
        ) { [weak self] _ in
            print("\(self?.debugMarker ?? "[GTS_DEBUG_REMOVE_ME]") Received distributed overlay request")
            self?.showOverlay()
        }
        print("\(debugMarker) Registered distributed overlay observer")
    }

    // MARK: - Daemon Registration

    func registerDaemon() {
        print("\(debugMarker) registerDaemon called")
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
            do {
                try service.register()
                print("\(debugMarker) registerDaemon succeeded")
            } catch {
                print("Failed to register daemon: \(error)")
                print("\(debugMarker) registerDaemon failed: \(error)")
            }
        }
    }

    func unregisterDaemon() {
        print("\(debugMarker) unregisterDaemon called")
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
            do {
                try service.unregister()
                print("\(debugMarker) unregisterDaemon succeeded")
            } catch {
                print("Failed to unregister daemon: \(error)")
                print("\(debugMarker) unregisterDaemon failed: \(error)")
            }
        }
    }
}
