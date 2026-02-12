# GoToSleep Codebase Deep Dive

This document is a technical, bottom-up walkthrough of the entire repository, with concrete code references and runtime behavior details.

---

## 1) Repo Composition and Build Targets

This repo defines two Swift targets plus shared code:

- `GoToSleep` (menu bar app + overlay UI)
- `GoToSleepDaemon` (background process that enforces bedtime policy)
- `Shared` (logic and filesystem paths consumed by both targets)

Main source files:

- App target entry and orchestration: `GoToSleep/App/GoToSleepApp.swift`, `GoToSleep/App/AppDelegate.swift`
- UI: `GoToSleep/Views/*.swift`
- Domain models: `GoToSleep/Models/*.swift`
- Services: `GoToSleep/Services/*.swift`
- Daemon: `GoToSleepDaemon/main.swift`
- Shared utilities: `Shared/Paths.swift`, `Shared/TimeCheck.swift`

Configuration files:

- `GoToSleep/Info.plist` (sets agent app behavior)
- `GoToSleep/GoToSleep.entitlements` (sandbox disabled)
- `GoToSleepDaemon/Info.plist`
- `Resources/com.gotosleep.daemon.plist` (LaunchAgent definition)

---

## 2) App Entry Point, Scene Graph, and Delegate Bridging

### 2.1 `@main` app type

File: `GoToSleep/App/GoToSleepApp.swift`

```swift
// GoToSleep/App/GoToSleepApp.swift:3-7
@main
struct GoToSleepApp: App {
    private let debugMarker = "[GTS_DEBUG_REMOVE_ME]"
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settings = AppSettings.shared
```

Important runtime behavior:

- `@main` marks the process entry for Swift app lifecycle.
- `App` protocol defines scene declarations, not a classic `main()` function.
- `@NSApplicationDelegateAdaptor(AppDelegate.self)` instantiates and wires an `NSApplicationDelegate` into the SwiftUI lifecycle.
- `settings` is retained as an observed object, ensuring state-backed reactivity.

### 2.2 Scene declarations

```swift
// GoToSleep/App/GoToSleepApp.swift:13-27
var body: some Scene {
    MenuBarExtra("Go To Sleep", systemImage: "moon.fill") {
        MenuBarView(appDelegate: appDelegate)
    }

    Settings {
        SettingsView()
    }
}
```

Key Apple-specific concepts:

- `MenuBarExtra` creates an NSStatusItem-backed menu bar host scene.
- `Settings` creates macOS settings scene plumbing (not automatically shown unless triggered).
- `MenuBarView` receives `AppDelegate` by injection (critical: avoids `NSApp.delegate` cast ambiguity in SwiftUI lifecycle).

---

## 3) AppDelegate: Non-declarative Orchestration Layer

File: `GoToSleep/App/AppDelegate.swift`

This class coordinates:

- bedtime overlay lifecycle
- daemon registration with `SMAppService`
- settings window creation via AppKit
- distributed notification observer for daemon -> app signaling

### 3.1 Launch-time setup

```swift
// GoToSleep/App/AppDelegate.swift:14-23
func applicationDidFinishLaunching(_ notification: Notification) {
    print("\(debugMarker) applicationDidFinishLaunching args=\(CommandLine.arguments)")
    registerOverlayNotificationObserver()

    if CommandLine.arguments.contains("--bedtime") {
        print("\(debugMarker) Detected --bedtime launch, showing overlay")
        showOverlay()
    }
}
```

Machine-level implications:

- `CommandLine.arguments` comes from process argv.
- `--bedtime` boot path bypasses UI interaction and immediately enters enforcement overlay flow.
- `registerOverlayNotificationObserver()` sets up IPC (via distributed notifications) so daemon can ask already-running app to show overlay.

### 3.2 Overlay orchestration

```swift
// GoToSleep/App/AppDelegate.swift:25-49
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
```

Notable design points:

- Re-entrancy gate: `isShowingOverlay`.
- Session marker reset occurs before each overlay start.
- Overlay content is question-sampled per invocation.
- `focusEnforcer` + presentation options make escape harder.

### 3.3 Settings window creation (explicit AppKit)

```swift
// GoToSleep/App/AppDelegate.swift:58-79
func showSettingsWindow() {
    NSApp.activate(ignoringOtherApps: true)

    if settingsWindowController == nil {
        let settingsHostingController = NSHostingController(rootView: SettingsView())
        let settingsWindow = NSWindow(contentViewController: settingsHostingController)
        settingsWindow.title = "Go To Sleep Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.setContentSize(NSSize(width: 400, height: 320))
        settingsWindow.center()
        settingsWindow.isReleasedWhenClosed = false
        settingsWindowController = NSWindowController(window: settingsWindow)
    }

    settingsWindowController?.showWindow(nil)
    settingsWindowController?.window?.makeKeyAndOrderFront(nil)
}
```

Why this is stable:

- Avoids responder-chain selector routing (`showSettingsWindow:`) in menu bar scenes.
- Window controller retained strongly (`isReleasedWhenClosed = false` + property).

### 3.4 Daemon -> app overlay request channel

```swift
// GoToSleep/App/AppDelegate.swift:88-98
private func registerOverlayNotificationObserver() {
    DistributedNotificationCenter.default().addObserver(
        forName: showOverlayNotificationName,
        object: "com.gotosleep.app",
        queue: .main
    ) { [weak self] _ in
        self?.showOverlay()
    }
}
```

Terminology:

- `DistributedNotificationCenter`: cross-process notification bus on macOS.
- `object`: lightweight sender/channel scoping string.

### 3.5 LaunchAgent registration API

```swift
// GoToSleep/App/AppDelegate.swift:102-113
func registerDaemon() {
    if #available(macOS 13.0, *) {
        let service = SMAppService.agent(plistName: "com.gotosleep.daemon.plist")
        try service.register()
    }
}
```

- `ServiceManagement` framework
- `SMAppService.agent(plistName:)` expects bundled plist resource and registers with launchd.

---

## 4) Menu Bar UI and Control Surface

File: `GoToSleep/Views/MenuBarView.swift`

```swift
// GoToSleep/Views/MenuBarView.swift:3-6
struct MenuBarView: View {
    let appDelegate: AppDelegate
    @ObservedObject private var settings = AppSettings.shared
```

Main actions:

```swift
// GoToSleep/Views/MenuBarView.swift:20-39
Button("Test Overlay") {
    appDelegate.showOverlay()
}

Button("Settings...") {
    DispatchQueue.main.async {
        appDelegate.showSettingsWindow()
    }
}
.keyboardShortcut(",", modifiers: .command)

Button("Quit") {
    NSApp.terminate(nil)
}
```

Behavior notes:

- Uses direct delegate injection (robust).
- `DispatchQueue.main.async` defers settings action to next runloop turn.
- `Cmd+,` and `Cmd+Q` shortcuts scoped in menu context.

Status text path:

```swift
// GoToSleep/Views/MenuBarView.swift:47-60
if TimeCheck.isWithinBedtimeWindow(startHour: settings.bedtimeStartHour,
                                   endHour: settings.bedtimeEndHour) {
    return "Bedtime active (\(start)–\(end))"
}
```

---

## 5) Settings State Model and Persistence Semantics

File: `GoToSleep/Models/AppSettings.swift`

```swift
// GoToSleep/Models/AppSettings.swift:10-26
@AppStorage("questionsPerSession", store: UserDefaults(suiteName: suiteName))
var questionsPerSession: Int = 3
...
@AppStorage("isEnabled", store: UserDefaults(suiteName: suiteName))
var isEnabled: Bool = true
```

Persistence details:

- Writes to UserDefaults domain: `com.gotosleep.shared`.
- Backed by property wrappers; mutation in UI writes persisted value automatically.
- Shared suite enables daemon read-access to same values.

Memory/model behavior:

- Singleton (`static let shared`) centralizes settings state.
- `ObservableObject` + `@ObservedObject` in views means UI refreshes on setting changes.

---

## 6) Settings UI

File: `GoToSleep/Views/SettingsView.swift`

Core form construction:

```swift
// GoToSleep/Views/SettingsView.swift:15-43
Form {
    Section("Schedule") {
        Toggle("Enabled", isOn: $settings.isEnabled)
        Picker("Bedtime starts at", selection: $settings.bedtimeStartHour) { ... }
        Picker("Bedtime ends at", selection: $settings.bedtimeEndHour) { ... }
    }
    Section("Questions") {
        Stepper("Questions per session: \(settings.questionsPerSession)",
                value: $settings.questionsPerSession, in: 1...10)
    }
    Section("After Completion") {
        Picker("Grace period", selection: $settings.gracePeriodMinutes) { ... }
    }
}
```

Binding semantics:

- `$settings.foo` provides two-way binding to `@AppStorage`-backed properties.
- Changes commit immediately.

---

## 7) Overlay Runtime Pipeline

### 7.1 Window manager and kiosk enforcement

File: `GoToSleep/Services/OverlayWindowController.swift`

`KioskWindow`:

```swift
// GoToSleep/Services/OverlayWindowController.swift:5-8
class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func close() { /* no-op */ }
}
```

Overlay presentation:

```swift
// GoToSleep/Services/OverlayWindowController.swift:23-31
let window = KioskWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

OS-level restrictions:

```swift
// GoToSleep/Services/OverlayWindowController.swift:45-51
NSApp.presentationOptions = [
    .hideDock,
    .hideMenuBar,
    .disableProcessSwitching,
    .disableForceQuit,
    .disableSessionTermination,
]
```

These are AppKit presentation flags enforced by WindowServer/NSApplication integration.

### 7.2 Focus reclamation backup path

File: `GoToSleep/Services/FocusEnforcer.swift`

```swift
// GoToSleep/Services/FocusEnforcer.swift:12-18
observer = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification,
    object: nil,
    queue: .main
) { [weak self] notification in
    self?.handleActivation(notification)
}
```

If a different app activates, it calls:

```swift
// GoToSleep/Services/FocusEnforcer.swift:37-38
NSApp.activate(ignoringOtherApps: true)
```

---

## 8) Overlay UI State Machine

File: `GoToSleep/Views/OverlayView.swift`

State:

```swift
// GoToSleep/Views/OverlayView.swift:8-9
@State private var currentIndex = 0
@State private var answers: [String]
```

Validation:

```swift
// GoToSleep/Views/OverlayView.swift:21-22
private var isCurrentAnswered: Bool {
    !answers[currentIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
```

Transition action:

```swift
// GoToSleep/Views/OverlayView.swift:80-101
private func advance() {
    guard isCurrentAnswered else { return }
    let q = questions[currentIndex]
    AnswerLogger.log(questionId: q.id, questionText: q.text, answer: answers[currentIndex])

    if isLastQuestion {
        onComplete()
    } else {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentIndex += 1
        }
    }
}
```

This is a deterministic finite progression:

- state tuple roughly `(currentIndex, answers[])`
- transition guarded by non-empty current answer
- terminal state triggers callback to AppDelegate completion path

---

## 9) Question Rendering

File: `GoToSleep/Views/QuestionView.swift`

Type-based dispatch:

```swift
// GoToSleep/Views/QuestionView.swift:16-20
switch question.type {
case .freeText:
    freeTextInput
case .multipleChoice:
    multipleChoiceInput
}
```

Free text path uses `TextEditor`; MCQ path writes `answer = choice` on click.

Question data model:

```swift
// GoToSleep/Models/Question.swift:3-13
enum QuestionType: String, Codable { ... }
struct Question: Codable, Identifiable {
    let id: String
    let text: String
    let type: QuestionType
    let choices: [String]?
}
```

`Codable` mapping directly decodes `questions.json`.

---

## 10) Question Loading and Session Logging

### 10.1 QuestionStore

File: `GoToSleep/Models/QuestionStore.swift`

```swift
// GoToSleep/Models/QuestionStore.swift:9-11
guard let url = Bundle.main.url(forResource: "questions", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let decoded = try? JSONDecoder().decode([Question].self, from: data) else { ... }
```

- Pulls resource from main bundle at runtime.
- Failure degrades to empty set.
- Selection is random subset via `shuffled().prefix(count)`.

### 10.2 Answer logger

File: `GoToSleep/Services/AnswerLogger.swift`

```swift
// GoToSleep/Services/AnswerLogger.swift:23-27
guard let data = try? encoder.encode(entry),
      let line = String(data: data, encoding: .utf8) else { return }
```

Then append/create:

```swift
// GoToSleep/Services/AnswerLogger.swift:32-43
if FileManager.default.fileExists(atPath: Paths.answersPath.path) {
    let handle = try? FileHandle(forWritingTo: Paths.answersPath)
    handle?.seekToEndOfFile()
    handle?.write(...)
} else {
    try? lineWithNewline.write(to: Paths.answersPath, atomically: true, encoding: .utf8)
}
```

Storage format: JSONL (`answers.jsonl`).

SessionLog model:

```swift
// GoToSleep/Models/SessionLog.swift:3-8
struct SessionLog: Codable {
    let timestamp: Date
    let questionId: String
    let questionText: String
    let answer: String
}
```

---

## 11) Shared Utilities

### 11.1 `Paths`

File: `Shared/Paths.swift`

Key paths:

```swift
// Shared/Paths.swift:12-15
static let sessionActivePath = appSupportDir.appendingPathComponent("session-active")
static let sessionCompletedPath = appSupportDir.appendingPathComponent("session-completed")
static let answersPath = appSupportDir.appendingPathComponent("answers.jsonl")
static let killLogPath = appSupportDir.appendingPathComponent("kills.json")
```

Directory base:

```swift
// Shared/Paths.swift:5-9
let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let resolvedPath = base.appendingPathComponent("GoToSleep")
```

### 11.2 `TimeCheck`

File: `Shared/TimeCheck.swift`

```swift
// Shared/TimeCheck.swift:13-22
if startHour <= endHour {
    return hour >= startHour && hour < endHour
} else {
    return hour >= startHour || hour < endHour
}
```

This correctly handles both contiguous and midnight-wrapping windows.

---

## 12) Daemon Architecture (Enforcement Engine)

File: `GoToSleepDaemon/main.swift`

### 12.1 Process model

- Single-threaded infinite loop (`while true`).
- Polling cadence: 10 seconds (`sleep(10)`).
- Decision gates:
  1. enabled setting
  2. bedtime window
  3. grace period not active
  4. app running vs not running branch

### 12.2 Core loop

```swift
// GoToSleepDaemon/main.swift:14-23
while true {
    sleep(10)
    let settings = readSettings()
    guard settings.isEnabled else { continue }
    guard TimeCheck.isWithinBedtimeWindow(startHour: settings.bedtimeStartHour,
                                          endHour: settings.bedtimeEndHour) else { continue }
```

### 12.3 Grace period gate

```swift
// GoToSleepDaemon/main.swift:26-31
if let completedDate = Paths.readTimestamp(from: Paths.sessionCompletedPath) {
    let elapsed = Date().timeIntervalSince(completedDate)
    let gracePeriod = TimeInterval(settings.gracePeriodMinutes * 60)
    if elapsed < gracePeriod { continue }
}
```

### 12.4 Running-app signaling branch

```swift
// GoToSleepDaemon/main.swift:34-38
if isMainAppRunning() {
    requestOverlayFromRunningApp()
    continue
}
```

Notification post:

```swift
// GoToSleepDaemon/main.swift:120-124
DistributedNotificationCenter.default().post(
    name: showOverlayNotificationName,
    object: "com.gotosleep.app"
)
```

### 12.5 Fresh launch branch

```swift
// GoToSleepDaemon/main.swift:138-144
let process = Process()
process.executableURL = URL(fileURLWithPath: appPath)
process.arguments = ["--bedtime"]
try process.run()
```

Then:

```swift
// GoToSleepDaemon/main.swift:149-152
process.waitUntilExit()
return Paths.fileExists(at: Paths.sessionCompletedPath)
```

### 12.6 Kill tracking/safety valve

```swift
// GoToSleepDaemon/main.swift:56-60
if killTimestamps.count >= 5 {
    Paths.writeTimestamp(to: Paths.sessionCompletedPath)
    killTimestamps.removeAll()
}
```

Purpose: avoid pathological relaunch loop if user repeatedly kills app.

### 12.7 Settings source in daemon

```swift
// GoToSleepDaemon/main.swift:77-84
let defaults = UserDefaults(suiteName: "com.gotosleep.shared")
```

This suite must match app suite (`AppSettings.suiteName`).

---

## 13) macOS Configuration Files

### 13.1 Menu bar app mode

File: `GoToSleep/Info.plist`

```xml
<!-- GoToSleep/Info.plist:5-6 -->
<key>LSUIElement</key>
<true/>
```

Meaning:

- App runs as agent app (no Dock icon / no app menu in normal way), menu bar centric UX.

### 13.2 Entitlements

File: `GoToSleep/GoToSleep.entitlements`

```xml
<!-- GoToSleep/GoToSleep.entitlements:5-6 -->
<key>com.apple.security.app-sandbox</key>
<false/>
```

- Sandbox disabled; relevant for broader system API interactions.

### 13.3 LaunchAgent descriptor

File: `Resources/com.gotosleep.daemon.plist`

```xml
<!-- Resources/com.gotosleep.daemon.plist:5-16 -->
<key>Label</key><string>com.gotosleep.daemon</string>
<key>BundleProgram</key><string>Contents/MacOS/GoToSleepDaemon</string>
<key>KeepAlive</key><true/>
<key>RunAtLoad</key><true/>
<key>StandardOutPath</key><string>/tmp/go-to-sleep-daemon.stdout.log</string>
<key>StandardErrorPath</key><string>/tmp/go-to-sleep-daemon.stderr.log</string>
```

`BundleProgram` is resolved relative to app bundle root by ServiceManagement registration path.

---

## 14) Data Files

### 14.1 Questions bank

File: `GoToSleep/Resources/questions.json`

- Array of `Question` DTOs.
- `type` values map to `QuestionType` raw values:
  - `"free_text"`
  - `"multiple_choice"`

### 14.2 Runtime files

Under `~/Library/Application Support/GoToSleep/`:

- `answers.jsonl`
- `session-completed`
- `kills.json`

---

## 15) End-to-End Execution Flows

### 15.1 Manual app launch, open settings

1. Process starts in SwiftUI lifecycle (`@main` app).
2. `AppDelegate.applicationDidFinishLaunching` runs and registers distributed notification observer.
3. Menu bar scene hosts `MenuBarView`.
4. Clicking Settings dispatches to `appDelegate.showSettingsWindow()`.
5. AppKit `NSWindowController` is lazily created and shown.

### 15.2 Daemon-triggered overlay when app is already running

1. Daemon loop sees bedtime window and enabled settings.
2. `isMainAppRunning()` true.
3. Daemon posts distributed notification `com.gotosleep.showOverlayNow`.
4. App observer receives and calls `showOverlay()`.
5. Overlay window appears with kiosk options.

### 15.3 Daemon-triggered overlay when app is not running

1. Same gating checks pass.
2. Daemon resolves app executable path.
3. Launches app with `--bedtime`.
4. App delegate sees argument and immediately calls `showOverlay()`.
5. Daemon waits for process exit and checks completion marker.

---

## 16) Swift and Apple Terminology Used Here

- `Scene`: top-level UI/runtime unit in SwiftUI app lifecycle.
- `MenuBarExtra`: menu-bar-specific SwiftUI scene type for status item UX.
- `NSApplicationDelegateAdaptor`: bridge from SwiftUI app lifecycle to AppKit delegate callbacks.
- `@AppStorage`: property wrapper around UserDefaults keys, with automatic view updates and persistence.
- `UserDefaults suite`: named preference domain; shared domain enables multi-process coordination.
- `NSHostingView` / `NSHostingController`: adapter to host SwiftUI views in AppKit windows.
- `NSWindow.level`: z-order level in WindowServer composition.
- `NSApp.presentationOptions`: process-level UI restrictions (dock/menu/process switching behavior).
- `SMAppService.agent`: modern ServiceManagement API for registering LaunchAgents bundled with an app.
- `launchd`: macOS process supervisor.
- `DistributedNotificationCenter`: lightweight local-machine inter-process message bus.

---

## 17) Current Structural/Behavioral Observations

These are factual observations from the code as it currently exists:

1. `PermissionsGuideView` is present but not currently mounted in any active scene path in `GoToSleepApp`.
2. `PermissionsGuideView.registerDaemon()` still tries `NSApp.delegate as? AppDelegate` and can fail in this SwiftUI lifecycle shape.
3. Extensive debug logs are intentionally present using marker `"[GTS_DEBUG_REMOVE_ME]"` across app and shared code.
4. Daemon now supports both "launch app with `--bedtime`" and "signal running app to show overlay".

---

## 18) Files Not Central to Runtime Logic

- `.gitignore`: tooling artifacts filtering only.
- `README.md`: documentation only.
- `GoToSleepDaemon/Info.plist`: daemon bundle metadata.

---

## 19) Practical Source Navigation Index

- App entry: `GoToSleep/App/GoToSleepApp.swift`
- Main coordinator: `GoToSleep/App/AppDelegate.swift`
- Menu command surface: `GoToSleep/Views/MenuBarView.swift`
- Settings persistence model: `GoToSleep/Models/AppSettings.swift`
- Kiosk window mechanics: `GoToSleep/Services/OverlayWindowController.swift`
- Focus reclaim path: `GoToSleep/Services/FocusEnforcer.swift`
- Daemon engine: `GoToSleepDaemon/main.swift`
- Shared persistence/time helpers: `Shared/Paths.swift`, `Shared/TimeCheck.swift`

