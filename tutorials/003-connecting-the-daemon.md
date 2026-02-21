# Connecting the Daemon

The daemon registration code exists (`AppDelegate.registerDaemon()`) and the UI
to trigger it exists (`PermissionsGuideView`), but they're not wired into the
app lifecycle. This tutorial explains what's disconnected and what to change.

---

## What's Wrong

There are three broken links in the chain:

1. **PermissionsGuideView is never shown.** The `hasCompletedSetup` flag exists
   in AppSettings but nothing in AppDelegate checks it or presents the guide.
   The view is defined, compiled, and completely unused.

2. **The "Enabled" toggle doesn't touch the daemon.** In AppDelegate,
   `toggleEnabled()` (line 68) just flips `AppSettings.shared.isEnabled`. It
   never calls `registerDaemon()` or `unregisterDaemon()`.

3. **No automatic daemon registration on launch.** Even after completing setup,
   if the Mac reboots or the daemon gets unloaded, nothing re-registers it.

The result: the app launches, shows a moon icon in the menu bar, and does
nothing else. The daemon binary sits inside the app bundle untouched.

---

## Fix 1: Show the Permissions Guide on First Launch

**File:** `GoToSleep/App/AppDelegate.swift`

The setup guide needs to appear when the user hasn't completed setup yet. Add a
method to show it and call it from `applicationDidFinishLaunching`.

### Step 1: Add a window controller property for the guide

Find the existing properties at the top of the class (around lines 5–13):

```swift
private var settingsWindowController: NSWindowController?
private var statusItem: NSStatusItem!
```

Add a new property right after `settingsWindowController`:

```swift
private var setupWindowController: NSWindowController?
```

### Step 2: Add a method to show the guide

Add this method somewhere in the class (after `showSettingsWindow()` is a
natural spot, around line 168):

```swift
private func showSetupGuideIfNeeded() {
    guard !AppSettings.shared.hasCompletedSetup else { return }
    print("\(debugMarker) First launch — showing setup guide")
    NSApp.activate(ignoringOtherApps: true)

    let guideView = PermissionsGuideView(appDelegate: self)
    let hostingController = NSHostingController(rootView: guideView)
    let window = NSWindow(contentViewController: hostingController)
    window.title = "Go To Sleep — Setup"
    window.styleMask = [.titled, .closable]
    window.setContentSize(NSSize(width: 540, height: 480))
    window.center()
    window.isReleasedWhenClosed = false

    setupWindowController = NSWindowController(window: window)
    setupWindowController?.showWindow(nil)
    window.makeKeyAndOrderFront(nil)
}
```

### Step 3: Call it from applicationDidFinishLaunching

Find `applicationDidFinishLaunching` (line 17). It currently ends with the
`--bedtime` check. Add the setup guide call right before that check:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    print("\(debugMarker) applicationDidFinishLaunching args=\(CommandLine.arguments)")

    setupStatusItem()
    audioMuter.restoreIfNeeded()
    registerOverlayNotificationObserver()

    showSetupGuideIfNeeded()          // <-- ADD THIS LINE

    if CommandLine.arguments.contains("--bedtime") {
        print("\(debugMarker) Detected --bedtime launch, showing overlay")
        showOverlay()
    }
}
```

Now the first time the app runs, the setup guide appears, the user grants
Accessibility and clicks "Enable" to register the daemon.

---

## Fix 2: Wire the Enabled Toggle to the Daemon

**File:** `GoToSleep/App/AppDelegate.swift`

Find `toggleEnabled()` (around line 67):

```swift
@objc private func toggleEnabled() {
    AppSettings.shared.isEnabled.toggle()
    print("\(debugMarker) Toggled isEnabled -> \(AppSettings.shared.isEnabled)")
}
```

Change it to:

```swift
@objc private func toggleEnabled() {
    AppSettings.shared.isEnabled.toggle()
    print("\(debugMarker) Toggled isEnabled -> \(AppSettings.shared.isEnabled)")

    if AppSettings.shared.isEnabled {
        registerDaemon()
    } else {
        unregisterDaemon()
    }
}
```

Now toggling "Enabled" off in the menu bar will unload the daemon via
`launchctl unload`, and toggling it back on will re-register and load it.

---

## Fix 3: Re-register the Daemon on Launch

If the Mac reboots, the LaunchAgent plist in `~/Library/LaunchAgents/` persists
and macOS will auto-start the daemon (because `RunAtLoad = true`). But if the
user deletes that plist or it gets lost, the daemon won't come back.

To be safe, ensure the daemon is registered every time the app starts (if
enabled and setup is complete).

**File:** `GoToSleep/App/AppDelegate.swift`

In `applicationDidFinishLaunching`, add this after the setup guide call:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    print("\(debugMarker) applicationDidFinishLaunching args=\(CommandLine.arguments)")

    setupStatusItem()
    audioMuter.restoreIfNeeded()
    registerOverlayNotificationObserver()

    showSetupGuideIfNeeded()

    // Ensure daemon is registered if user has completed setup and is enabled
    if AppSettings.shared.hasCompletedSetup && AppSettings.shared.isEnabled {
        registerDaemon()
    }

    if CommandLine.arguments.contains("--bedtime") {
        print("\(debugMarker) Detected --bedtime launch, showing overlay")
        showOverlay()
    }
}
```

Calling `launchctl load` on an already-loaded daemon is harmless (it prints a
warning to stderr but doesn't break anything), so this is safe to call every
launch.

---

## Summary of Changes

All changes are in `GoToSleep/App/AppDelegate.swift`:

| What | Where | Change |
|------|-------|--------|
| New property | Top of class | Add `setupWindowController` |
| New method | After `showSettingsWindow()` | Add `showSetupGuideIfNeeded()` |
| Call setup guide | `applicationDidFinishLaunching` | Add `showSetupGuideIfNeeded()` call |
| Auto-register | `applicationDidFinishLaunching` | Add `registerDaemon()` call when enabled |
| Toggle wiring | `toggleEnabled()` | Add `registerDaemon()`/`unregisterDaemon()` calls |

No changes needed to any other files. The PermissionsGuideView already calls
`appDelegate.registerDaemon()` correctly — it just was never being shown.

---

## Testing

After making these changes, build and run:

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  build
```

Then launch:

```bash
open build/Build/Products/Debug/GoToSleep.app
```

### First launch

1. The setup guide window should appear automatically.
2. Click "Open Settings" to grant Accessibility (you'll need to add the app in
   System Settings > Privacy & Security > Accessibility).
3. Click "Check Again" to verify.
4. Click "Enable" to register the daemon.
5. Click "Done" to dismiss.

### Verify the daemon is running

```bash
pgrep GoToSleepDaemon
```

Should return a PID.

```bash
cat /tmp/go-to-sleep-daemon.stdout.log
```

Should show `[GoToSleepDaemon] Started at <date>`.

### Verify the LaunchAgent plist was written

```bash
cat ~/Library/LaunchAgents/com.gotosleep.daemon.plist
```

Should exist and contain the `ProgramArguments` pointing to the daemon binary
inside your app bundle.

### Test the Enabled toggle

Click the moon icon in the menu bar, toggle "Enabled" off, then check:

```bash
pgrep GoToSleepDaemon
```

Should return nothing (daemon unloaded).

Toggle it back on and check again — daemon should be running.
