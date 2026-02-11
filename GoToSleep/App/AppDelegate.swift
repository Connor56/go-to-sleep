import AppKit
import ServiceManagement
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayController = OverlayWindowController()
    private let focusEnforcer = FocusEnforcer()
    private let questionStore = QuestionStore()
    private var isShowingOverlay = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if launched with --bedtime flag (by the daemon)
        if CommandLine.arguments.contains("--bedtime") {
            showOverlay()
        }
    }

    func showOverlay() {
        guard !isShowingOverlay else { return }
        isShowingOverlay = true

        Paths.ensureDirectoryExists()
        Paths.removeFile(at: Paths.sessionCompletedPath)

        let count = AppSettings.shared.questionsPerSession
        let questions = questionStore.selectQuestions(count: count)

        guard !questions.isEmpty else {
            isShowingOverlay = false
            return
        }

        focusEnforcer.start()
        NSApp.activate(ignoringOtherApps: true)

        overlayController.show(questions: questions) { [weak self] in
            self?.completeSession()
        }
    }

    func dismissOverlay() {
        overlayController.dismiss()
        focusEnforcer.stop()
        isShowingOverlay = false
    }

    private func completeSession() {
        // Write completion marker so the daemon knows we finished legitimately
        Paths.writeTimestamp(to: Paths.sessionCompletedPath)
        dismissOverlay()
    }

    // MARK: - Daemon Registration

    func registerDaemon() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
            do {
                try service.register()
            } catch {
                print("Failed to register daemon: \(error)")
            }
        }
    }

    func unregisterDaemon() {
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
            do {
                try service.unregister()
            } catch {
                print("Failed to unregister daemon: \(error)")
            }
        }
    }
}
