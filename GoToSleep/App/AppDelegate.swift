import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    private let showOverlayNotificationName = Notification.Name("com.gotosleep.showOverlayNow")
    private let overlayController = OverlayWindowController()
    private let focusEnforcer = FocusEnforcer()
    private let audioMuter = AudioMuter()
    private let questionStore = QuestionStore()
    private var isShowingOverlay = false
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem!
    private var setupWindowController: NSWindowController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("\(debugMarker) applicationDidFinishLaunching args=\(CommandLine.arguments)")

        setupStatusItem()
        audioMuter.restoreIfNeeded()
        registerOverlayNotificationObserver()

        if CommandLine.arguments.contains("--bedtime") {
            print("\(debugMarker) Detected --bedtime launch, showing overlay")
            showOverlay()
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Go To Sleep")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let settings = AppSettings.shared

        let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        let statusItem = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Test Overlay", action: #selector(testOverlayClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(settingsClicked), keyEquivalent: ","))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func testOverlayClicked() {
        print("\(debugMarker) Test Overlay clicked")
        showOverlay()
    }

    @objc private func settingsClicked() {
        print("\(debugMarker) Settings menu item clicked")
        showSettingsWindow()
    }

    private func statusText() -> String {
        let settings = AppSettings.shared
        if !settings.isEnabled {
            return "Disabled"
        }

        let start = formatHour(settings.bedtimeStartHour)
        let end = formatHour(settings.bedtimeEndHour)

        if TimeCheck.isWithinBedtimeWindow(startHour: settings.bedtimeStartHour,
                                            endHour: settings.bedtimeEndHour) {
            return "Bedtime active (\(start)–\(end))"
        } else {
            return "Next bedtime: \(start)–\(end)"
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }

    // MARK: - Overlay

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

    // MARK: - Settings Window

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

    // MARK: - Session

    private func completeSession() {
        print("\(debugMarker) completeSession called")
        Paths.writeTimestamp(to: Paths.sessionCompletedPath)
        dismissOverlay()
    }

    private func registerOverlayNotificationObserver() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOverlayNotification),
            name: showOverlayNotificationName,
            object: "com.gotosleep.app",
            suspensionBehavior: .deliverImmediately

        )
        print("\(debugMarker) Registered distributed overlay observer")
    }

    @objc func handleOverlayNotification() {
        // Needed to make sure the message is relayed correctly
        print("\(self.debugMarker ?? "[GTS_DEBUG_REMOVE_ME]") Received distributed overlay request")
        self.showOverlay()
    }

    // MARK: - Daemon Registration

    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.gotosleep.daemon.plist")
    }

    private func daemonBinaryPath() -> String {
        let bundle = Bundle.main
        return bundle.bundlePath + "/Contents/MacOS/GoToSleepDaemon"
    }

    func registerDaemon() {
        print("\(debugMarker) registerDaemon called")

        let plistURL = launchAgentPlistURL
        let binaryPath = daemonBinaryPath()

        let plistContent: [String: Any] = [
            "Label": "com.gotosleep.daemon",
            "ProgramArguments": [binaryPath],
            "KeepAlive": true,
            "RunAtLoad": true,
            "StandardOutPath": "/tmp/go-to-sleep-daemon.stdout.log",
            "StandardErrorPath": "/tmp/go-to-sleep-daemon.stderr.log",
        ]

        // Ensure ~/Library/LaunchAgents exists
        let launchAgentsDir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        // Write the plist
        let data = try? PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        guard let data = data else {
            print("\(debugMarker) registerDaemon failed: could not serialize plist")
            return
        }

        do {
            try data.write(to: plistURL)
            print("\(debugMarker) Wrote launch agent plist to \(plistURL.path)")
        } catch {
            print("\(debugMarker) registerDaemon failed to write plist: \(error)")
            return
        }

        // Load via launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            print("\(debugMarker) registerDaemon launchctl load exit code: \(process.terminationStatus)")
        } catch {
            print("\(debugMarker) registerDaemon launchctl load failed: \(error)")
        }
    }

    func unregisterDaemon() {
        print("\(debugMarker) unregisterDaemon called")

        let plistURL = launchAgentPlistURL

        // Unload via launchctl
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        do {
            try process.run()
            process.waitUntilExit()
            print("\(debugMarker) unregisterDaemon launchctl unload exit code: \(process.terminationStatus)")
        } catch {
            print("\(debugMarker) unregisterDaemon launchctl unload failed: \(error)")
        }

        // Remove the plist file
        try? FileManager.default.removeItem(at: plistURL)
        print("\(debugMarker) unregisterDaemon removed plist at \(plistURL.path)")
    }
}
