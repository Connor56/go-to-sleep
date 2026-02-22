# Fixing Daemon-App Communication

There are two bugs with how the daemon and the main app communicate:

1. **Distributed notifications only work once.** The daemon sends a
   notification, the main app receives it and shows the overlay the first time,
   but subsequent notifications are silently dropped. Restarting the app or
   opening Settings makes it work again (once).

2. **The daemon thinks the app is always running.** Even after you quit the main
   app, `isMainAppRunning()` keeps returning `true`, so the daemon never
   falls through to `launchAndMonitor()` — it just keeps sending notifications
   into the void.

---

## Try It Yourself First

Both bugs share the same underlying theme. Here are some breadcrumbs.

### Bug 1: Notifications stop arriving

Think about what the main app is doing when it works vs when it doesn't:

- **Works:** right after launch, or right after opening Settings.
- **Doesn't work:** after the overlay has been dismissed and the app is just
  sitting as a menu bar icon with no windows.

Ask yourself:

- What does `showSettingsWindow()` do that might "wake up" notification
  delivery? Look at line 175 of `AppDelegate.swift`.
- The app is an `LSUIElement` (no dock icon). What does macOS consider the
  app's state when it has no visible windows?
- Look at the observer registration in `registerOverlayNotificationObserver()`.
  It uses the block-based `addObserver(forName:object:queue:using:)` API. Is
  there a different `DistributedNotificationCenter` API that gives you more
  control over *when* notifications are delivered?
- Search the Apple docs for `DistributedNotificationCenter` and look for a
  parameter called `suspensionBehavior`.

### Bug 2: The app appears immortal

The daemon checks if the app is running with:

```swift
func isMainAppRunning() -> Bool {
    let apps = NSWorkspace.shared.runningApplications
    return apps.contains { $0.bundleIdentifier == "com.gotosleep.app" }
}
```

Ask yourself:

- `NSWorkspace.shared.runningApplications` is a property that updates via
  system notifications. What does the daemon's main loop look like? Is there
  anything that would allow those system notifications to be processed?
- Look at the daemon's `main()` function. What does `sleep(10)` do to the
  thread? What does that mean for the run loop?
- Is there an alternative to `sleep()` that would keep the thread alive for 10
  seconds *while still processing events*?
- Check the `RunLoop` documentation for a method that runs the loop for a
  specific duration.

### The common theme

Both bugs are caused by the same fundamental concept. macOS delivers many types
of system information (workspace notifications, distributed notifications,
KVO updates) through the **run loop**. If a process isn't running its run loop,
those updates never arrive.

If you've figured it out, go ahead and fix both. If you want the full solution,
read on.

---

## Full Solution

### Bug 1: Notification suspension behavior

**File:** `GoToSleep/App/AppDelegate.swift`

`DistributedNotificationCenter` has a concept called **suspension behavior**.
When an app is "suspended" (macOS considers an `LSUIElement` app with no
visible windows to be suspended), the default behavior is to **coalesce**
notifications — meaning they're queued and may not be delivered until the app
becomes active again.

That's why opening Settings fixes it: `showSettingsWindow()` calls
`NSApp.activate(ignoringOtherApps: true)`, which unsuspends the app and
delivers any queued notifications.

The fix is to use the selector-based observer API, which lets you specify
`.deliverImmediately` as the suspension behavior.

Find `registerOverlayNotificationObserver()` (around line 178):

```swift
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
```

Replace it with:

```swift
private func registerOverlayNotificationObserver() {
    DistributedNotificationCenter.default().addObserver(
        self,
        selector: #selector(handleOverlayRequest),
        name: showOverlayNotificationName,
        object: "com.gotosleep.app",
        suspensionBehavior: .deliverImmediately
    )
    print("\(debugMarker) Registered distributed overlay observer")
}

@objc private func handleOverlayRequest(_ notification: Notification) {
    print("\(debugMarker) Received distributed overlay request")
    showOverlay()
}
```

The key change: `suspensionBehavior: .deliverImmediately` tells macOS to
deliver notifications to this observer even when the app is considered
suspended. The block-based API doesn't expose this parameter — you have to use
the selector-based version.

### Bug 2: Stale running applications list

**File:** `GoToSleepDaemon/main.swift`

`NSWorkspace.shared.runningApplications` is updated via workspace notifications
delivered through the run loop. The daemon's main loop uses `sleep(10)`, which
**blocks the thread entirely** — the run loop never gets a chance to process
events. So `runningApplications` returns the same stale snapshot from when the
daemon first started, and any app that was running at startup appears to be
running forever.

The fix is to replace `sleep(10)` with a run loop call that processes events
for 10 seconds:

Find the main loop in `main()`:

```swift
while true {
    sleep(10)
```

Replace `sleep(10)` with:

```swift
while true {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 10))
```

`RunLoop.current.run(until:)` does the same thing as `sleep(10)` — it waits
for 10 seconds before continuing — but it **processes events** during that
wait. This means workspace notifications are delivered, and
`NSWorkspace.shared.runningApplications` stays up to date.

No other changes needed in the daemon. `isMainAppRunning()` will now return
accurate results because the underlying data is being kept fresh.

---

## Summary

| Bug | Root cause | Fix | File |
|-----|-----------|-----|------|
| Notifications stop after first delivery | Default suspension behavior coalesces notifications for inactive LSUIElement apps | Use selector-based observer with `.deliverImmediately` | `AppDelegate.swift` |
| Daemon thinks app is always running | `sleep(10)` blocks the run loop, so `runningApplications` is never updated | Replace `sleep(10)` with `RunLoop.current.run(until:)` | `GoToSleepDaemon/main.swift` |

Both bugs come from the same concept: macOS delivers system information through
the run loop, and if you're not running it, you don't get updates.

---

## Testing

After making both fixes, build and run:

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  build
```

### Test notification delivery

1. Launch the app.
2. Simulate the daemon sending a notification (you can do this from Terminal):

```bash
# Send a distributed notification manually
osascript -e 'tell application "System Events" to do shell script "swift -e \"import Foundation; DistributedNotificationCenter.default().post(name: Notification.Name(\\\"com.gotosleep.showOverlayNow\\\"), object: \\\"com.gotosleep.app\\\")\"" '
```

Or more simply, just adjust your bedtime window to include the current hour and
let the daemon trigger it naturally. Complete the overlay, wait for the grace
period to expire, and verify it triggers again without restarting the app.

### Test daemon app detection

1. Start the daemon and the main app.
2. Quit the main app (menu bar > Quit).
3. Watch the daemon logs:

```bash
tail -f /tmp/go-to-sleep-daemon.stdout.log
```

You should see it switch from "Main app already running — requesting overlay
via distributed notification" to "Bedtime — launching main app" within one
loop cycle (10 seconds) of you quitting.
