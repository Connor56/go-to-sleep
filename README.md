# Go To Sleep

A macOS app that forces reflective questions at bedtime. It takes over your screen during configured hours and asks you to actually think about why you're still awake — then lets you go once you've answered.

It's genuinely hard to dismiss. A background daemon relaunches the app if you kill it. If you kill it 5 times in 10 minutes, it gives up (safety valve, not malware).

## What It Does

- **During bedtime hours** (default 9 PM – 7 AM), a full-screen overlay appears
- It asks 3 reflective questions (configurable) — mix of free-text and multiple-choice
- You must answer each question before proceeding to the next
- Once done, the overlay dismisses and a grace period prevents it from re-triggering
- The overlay blocks Cmd+Tab, hides the dock, and disables force quit
- A background daemon re-launches the overlay if you kill the app

## Requirements

- **macOS 13 (Ventura)** or later
- **Xcode 15** or later
- Accessibility permissions (for kiosk mode)

## Getting Started

### 1. Install Xcode

Download Xcode from the Mac App Store. It's Apple's IDE — it includes the Swift compiler, Interface Builder, and everything needed to build macOS apps.

### 2. Open the Project

```
open GoToSleep.xcodeproj
```

This opens the project in Xcode. You'll see two targets in the sidebar:
- **GoToSleep** — the main app (menu bar icon + overlay UI)
- **GoToSleepDaemon** — the background process that monitors bedtime

### 3. Build and Run

Press **Cmd+R** in Xcode (or Product → Run). The app appears as a moon icon in your menu bar — no dock icon, by design.

### 4. Grant Accessibility Permissions

On first launch, the app will guide you through granting Accessibility permissions. This is required for kiosk mode (the full-screen lock). Go to:

**System Settings → Privacy & Security → Accessibility** → toggle on GoToSleep

Without Accessibility permissions, the overlay still works but can be dismissed.

## Project Structure

```
GoToSleep/
├── App/
│   ├── GoToSleepApp.swift          The @main entry point. Defines the menu bar and settings scenes.
│   └── AppDelegate.swift           Bridges SwiftUI and AppKit. Coordinates the overlay lifecycle.
├── Views/
│   ├── OverlayView.swift           The full-screen question flow (progress, navigation, completion).
│   ├── QuestionView.swift          Renders a single question (free-text or multiple-choice).
│   ├── SettingsView.swift          Preferences panel (Cmd+,).
│   ├── MenuBarView.swift           The dropdown when you click the menu bar icon.
│   └── PermissionsGuideView.swift  First-run setup (Accessibility + daemon registration).
├── Models/
│   ├── Question.swift              The Question type — id, text, type, optional choices.
│   ├── QuestionStore.swift         Loads questions from the bundle and selects random ones.
│   ├── SessionLog.swift            The shape of a logged answer entry.
│   └── AppSettings.swift           All user preferences, backed by UserDefaults.
├── Services/
│   ├── OverlayWindowController.swift  Creates the kiosk-mode window and manages presentation.
│   ├── FocusEnforcer.swift         Backup focus reclaimer if something steals focus.
│   └── AnswerLogger.swift          Appends answers to a JSON Lines file.
├── Resources/
│   ├── questions.json              Default question bank (7 questions).
│   └── Assets.xcassets             App icon and menu bar icon.
├── Info.plist                      LSUIElement = YES (no dock icon).
└── GoToSleep.entitlements          App Sandbox disabled (required for Accessibility APIs).

GoToSleepDaemon/
├── main.swift                      The daemon — time check loop, process monitoring, kill tracking.
└── Info.plist

Shared/
├── Paths.swift                     File paths used by both app and daemon.
└── TimeCheck.swift                 Bedtime window logic (handles midnight crossing).

Resources/
└── com.gotosleep.daemon.plist      LaunchAgent configuration for the daemon.
```

## Key Swift/SwiftUI Concepts

If you're new to Swift, here's a quick guide to the patterns used in this project:

### `@main`
Marks the entry point of the app. In `GoToSleepApp.swift`, the `@main` attribute tells Swift "this is where execution starts." The struct conforms to the `App` protocol, which requires a `body` property that returns one or more `Scene`s.

### Scenes
A Scene is a top-level piece of UI that the system manages. We use two:
- `MenuBarExtra` — puts an icon in the menu bar with a dropdown
- `Settings` — the preferences window (opened with Cmd+,)

### `@AppStorage`
A property wrapper that reads/writes to `UserDefaults` (macOS's key-value preferences store). When you write `@AppStorage("key") var value = default`, it automatically loads the saved value on launch and saves changes. We use a shared suite (`com.gotosleep.app`) so the daemon can read the same settings.

### `Codable`
A protocol that lets you convert Swift types to/from JSON (or other formats). Our `Question` struct is `Codable`, which means `JSONDecoder` can turn JSON data into `Question` instances automatically — no manual parsing needed.

### `ObservableObject` and `@ObservedObject`
SwiftUI's way of sharing mutable state between views. `AppSettings` is an `ObservableObject` — when any of its `@AppStorage` properties change, all views observing it re-render automatically.

### AppKit vs SwiftUI
SwiftUI is Apple's declarative UI framework (describe what you want, the system figures out how to draw it). AppKit is the older imperative framework (you tell the system exactly what to do, step by step). We use both:
- **SwiftUI** for all the UI (views, settings, menu bar)
- **AppKit** for things SwiftUI can't do: controlling window level, setting presentation options, detecting app activation

The bridge between them is `NSApplicationDelegateAdaptor` (lets SwiftUI apps use an AppKit delegate) and `NSHostingView` (puts SwiftUI views inside AppKit windows).

## How the Background Daemon Works

### What is `launchd`?

`launchd` is macOS's system-level process manager — think of it as the boss that starts and manages every background process on your Mac. It's the very first process that runs when your Mac boots (PID 1), and it's responsible for starting system services, login items, and background agents.

### LaunchAgents vs LaunchDaemons

macOS has two kinds of background processes managed by `launchd`:

- **LaunchAgents** run per-user, in the user's GUI session. They can interact with the screen. This is what we use.
- **LaunchDaemons** run system-wide as root, with no GUI access. Used for low-level system services.

We need a LaunchAgent because the daemon needs to launch the main app, which shows UI on the user's screen.

### How `SMAppService.agent` Works

`SMAppService.agent(plistName:)` is Apple's modern API (macOS 13+) for registering a LaunchAgent that's bundled inside your `.app`. It replaces the old approach of manually copying plist files to `~/Library/LaunchAgents/`.

When we call `try service.register()`, macOS:
1. Reads the plist from inside the app bundle
2. Registers it with `launchd`
3. Shows it in **System Settings → General → Login Items** where the user can enable/disable it

### The Plist File

Our `com.gotosleep.daemon.plist` tells `launchd` how to run the daemon:

- **`KeepAlive: true`** — if the daemon crashes or is killed, `launchd` restarts it automatically. This is why the daemon itself is persistent.
- **`RunAtLoad: true`** — start the daemon as soon as it's loaded (at login).
- **`BundleProgram`** — path to the daemon binary, relative to the app bundle.

### Why This Is Standard Practice

Every macOS app that needs background work uses LaunchAgents — Dropbox, 1Password, Docker Desktop, etc. Apple explicitly provides this mechanism and the user approves it in System Settings → Login Items.

### The Full Lifecycle

1. User logs in → `launchd` starts the daemon
2. Daemon checks the time every 10 seconds
3. If it's bedtime and no grace period is active → daemon launches the main app with `--bedtime`
4. Main app shows the overlay → user answers questions
5. Main app writes `session-completed` marker file → overlay dismisses
6. Daemon sees the marker → grace period starts
7. If the user kills the main app instead → daemon notices (no marker) → relaunches
8. If killed 5 times in 10 minutes → safety valve: daemon writes the marker itself (grace period)

## Kiosk Mode vs Non-Kiosk Mode

### Non-Kiosk (Normal Window)

A regular macOS window. The user can Cmd+Tab away, click outside it, minimize it, close it, force-quit it. The window is just a suggestion — "please answer these questions." This is how most apps work.

### Kiosk Mode (What We Use)

The window takes over the entire screen and disables the user's ability to escape. Specifically:

- **`NSWindow.level = .screenSaver`** — places the window above everything, including the dock and menu bar
- **`NSApp.presentationOptions`** with **`disableProcessSwitching`** — disables Cmd+Tab at the OS level
- **`disableForceQuit`** — disables the Cmd+Opt+Esc force quit dialog
- **`hideDock` + `hideMenuBar`** — removes the dock and menu bar so there's nothing to click on
- **`FocusEnforcer`** — if the user somehow switches away, the app reclaims focus immediately

### Why This Exists

Apple designed these presentation options for legitimate use cases — exam proctoring software, point-of-sale kiosks, digital signage, museum exhibits. The APIs exist specifically so apps can lock down the screen when appropriate. It's not a hack; it's a supported macOS feature.

The key difference is **permission-based**: kiosk mode requires the app to have **Accessibility permissions** (granted by the user in System Settings). Without Accessibility, the app falls back to a persistent-but-dismissible window. With Accessibility, it can truly lock the screen.

We use kiosk mode because the whole point of this app is to be hard to dismiss. If you could just Cmd+Tab away, you'd never answer the questions and never go to bed.

## Settings

Open settings via the menu bar icon → Settings, or **Cmd+,**:

| Setting | Default | Description |
|---------|---------|-------------|
| Enabled | On | Quick toggle without quitting |
| Bedtime start | 9 PM | When the overlay can trigger |
| Bedtime end | 7 AM | When the overlay stops triggering |
| Questions per session | 3 | How many questions to ask (1–10) |
| Grace period | 1 hour | How long after completion before re-triggering |

## Common Tasks

### Adding Questions

Edit `GoToSleep/Resources/questions.json`. Each question needs:

```json
{
    "id": "unique-id",
    "text": "Your question text?",
    "type": "free_text",
    "choices": null
}
```

For multiple-choice, set `type` to `"multiple_choice"` and provide `choices` as an array of strings.

### Changing the Default Question Count

Edit `AppSettings.swift`, change the default value for `questionsPerSession`.

### Testing the Overlay

Click the menu bar icon → **Test Overlay**. This triggers the overlay immediately regardless of bedtime settings.

## Data Storage

| Data | Location | Format |
|------|----------|--------|
| Settings | UserDefaults (shared suite `com.gotosleep.app`) | Managed by macOS |
| Answer log | `~/Library/Application Support/GoToSleep/answers.jsonl` | JSON Lines (one entry per line) |
| Questions | Bundled in app | `questions.json` |
| Session markers | `~/Library/Application Support/GoToSleep/session-*` | Timestamp files |
| Kill log | `~/Library/Application Support/GoToSleep/kills.json` | Array of timestamps |

## Troubleshooting

### Overlay doesn't go full-screen / Cmd+Tab still works
Grant Accessibility permissions: **System Settings → Privacy & Security → Accessibility** → toggle on GoToSleep. Without this, the app can't enable kiosk mode.

### Daemon doesn't start
Check that it's registered: **System Settings → General → Login Items** → GoToSleep should be listed. If not, open the app and go through the first-run setup again.

Check daemon logs:
```bash
cat /tmp/go-to-sleep-daemon.stdout.log
cat /tmp/go-to-sleep-daemon.stderr.log
```

### App doesn't appear in menu bar
Make sure you're running the **GoToSleep** target (not GoToSleepDaemon). The app has `LSUIElement = YES`, which means no dock icon — look in the menu bar for the moon icon.

### Questions don't load
Make sure `questions.json` is included in the app bundle. In Xcode, check that it appears under **GoToSleep → Resources** in the project navigator and is listed in the target's "Copy Bundle Resources" build phase.
