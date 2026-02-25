# Auto-Dismiss the Overlay When Bedtime Ends

Right now, once the overlay appears, it stays forever until the user answers all
the questions. If bedtime runs from 9 PM to 7 AM and the user falls asleep
without completing the questions, the kiosk overlay is still sitting there at
10 AM — audio muted, dock hidden, process switching disabled.

This tutorial adds a mechanism to automatically tear down the overlay the moment
bedtime ends.

---

## Try It Yourself First

Before reading the solution, here are some questions to guide you.

### Who owns the overlay lifecycle?

Open `GoToSleep/App/AppDelegate.swift`. Look at `showOverlay()` and
`dismissOverlay()`. Which object is responsible for starting the overlay? Which
object tears it down? Where does the completion callback fire?

Now ask: if you wanted something *other than the user* to trigger dismissal,
where would that logic live?

### There's already a bedtime check

The codebase already has a function that answers "is it currently bedtime?"
— `TimeCheck.isWithinBedtimeWindow(startHour:endHour:)` in
`Shared/TimeCheck.swift`. It's used in two places already: the daemon's main
loop and the menu bar status text. You don't need to write a new one.

### When should the check run?

The overlay needs to notice when bedtime ends. It can't just check once — it
needs to check **periodically** while the overlay is showing. What Foundation
class runs a block on a schedule? Where would you start that schedule? Where
would you stop it?

### What should happen when bedtime ends?

Look at the two methods that close the overlay:

- `completeSession()` — writes a `session-completed` marker file, then calls
  `dismissOverlay()`
- `dismissOverlay()` — tears down windows, unmutes audio, stops focus enforcer,
  resets the `isShowingOverlay` flag

Which one should you call when bedtime ends? Think about what the
`session-completed` marker does — the daemon reads it to enforce the grace
period ("don't show the overlay again for N minutes after completion"). If
bedtime has ended, does the daemon need a grace period? Will it even try to
show the overlay again?

### What about state?

You said you want "no state preserved." Look at where state lives:

- `OverlayView` has `@State` properties for `currentIndex` and `answers`
- `OverlayWindowController` holds the `KioskWindow` reference and blocker
  windows
- `AppDelegate` has the `isShowingOverlay` flag

When `dismissOverlay()` runs, what happens to each of these? Does the
`OverlayWindowController.dismiss()` method destroy the window content? Read it
and check.

### Putting it together

You need:

1. A `Timer` property on `AppDelegate` to hold the periodic check
2. Start the timer when the overlay is shown
3. On each tick, check `TimeCheck.isWithinBedtimeWindow(...)` with the current
   settings
4. If bedtime has ended, call the appropriate dismiss method
5. Stop the timer when the overlay is dismissed (whether by the user completing
   questions or by bedtime ending)

Think about:

- **Timer interval** — how often should it check? Every second is overkill.
  Every 60 seconds is fine — bedtime boundaries are on the hour, and a
  worst-case 59-second delay before auto-dismiss is perfectly acceptable.
- **Where to invalidate** — the timer must be invalidated in `dismissOverlay()`,
  not just in the bedtime-end path. Otherwise if the user finishes questions
  normally, the timer keeps firing in the background.

Give it a shot. The changes are all in `AppDelegate.swift` and amount to about
15 lines of code.

---

## Full Solution

### Step 1: Add a timer property

At the top of `AppDelegate`, alongside the other properties:

```swift
private var bedtimeCheckTimer: Timer?
```

### Step 2: Start the timer in showOverlay()

At the end of `showOverlay()`, after the overlay is presented, schedule the
timer:

```swift
func showOverlay() {
    // ... existing code up to overlayController.show() ...

    overlayController.show(questions: questions) { [weak self] in
        self?.completeSession()
    }

    startBedtimeEndTimer()
}
```

### Step 3: Write the timer start/check methods

```swift
private func startBedtimeEndTimer() {
    bedtimeCheckTimer?.invalidate()
    bedtimeCheckTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
        self?.checkBedtimeEnd()
    }
}

private func checkBedtimeEnd() {
    let settings = AppSettings.shared
    let stillBedtime = TimeCheck.isWithinBedtimeWindow(
        startHour: settings.bedtimeStartHour,
        endHour: settings.bedtimeEndHour
    )

    if !stillBedtime {
        dismissOverlay()
    }
}
```

Key details:

- **`invalidate()` before scheduling** — safety against accidentally stacking
  multiple timers if `showOverlay()` is called twice.
- **`[weak self]`** — prevents a retain cycle between the timer and the
  AppDelegate. Without this, the timer holds a strong reference to
  `self`, and `self` holds a strong reference to the timer, so neither
  is ever deallocated.
- **60-second interval** — bedtime boundaries are on the hour. Checking every
  minute means the overlay dismisses within at most 59 seconds of bedtime
  ending. That's fine.

### Step 4: Stop the timer in dismissOverlay()

Add one line at the top of `dismissOverlay()`:

```swift
func dismissOverlay() {
    bedtimeCheckTimer?.invalidate()
    bedtimeCheckTimer = nil

    overlayController.dismiss()
    audioMuter.unmute()
    focusEnforcer.stop()
    isShowingOverlay = false
}
```

This is critical. The timer must be stopped here — not just in
`checkBedtimeEnd()` — because `dismissOverlay()` is called from two paths:

1. **User completes questions** → `completeSession()` → `dismissOverlay()`
2. **Bedtime ends** → `checkBedtimeEnd()` → `dismissOverlay()`

Both paths need the timer cleaned up.

### Why dismissOverlay() and not completeSession()?

`completeSession()` writes a `session-completed` marker file. The daemon reads
this marker to enforce the grace period — "the user already answered tonight,
don't show the overlay again for N minutes."

When bedtime ends naturally, you don't need the grace period. The daemon's own
main loop checks `isWithinBedtimeWindow` before doing anything — once bedtime
is over, it won't try to show the overlay regardless of whether a completion
marker exists.

Calling `dismissOverlay()` directly skips the marker write, which is the
correct behaviour: the session wasn't completed, bedtime just ended.

### What about state?

When `dismissOverlay()` fires:

- **`OverlayWindowController.dismiss()`** calls `orderOut(nil)` on the kiosk
  window and sets `contentView = nil`. The SwiftUI `OverlayView` (and its
  `@State` for `currentIndex` and `answers`) is destroyed with it. No state
  survives.
- **`AudioMuter.unmute()`** restores volume and removes the event tap. The
  `audio-muted` marker file is deleted.
- **`FocusEnforcer.stop()`** removes the workspace notification observer.
- **`isShowingOverlay = false`** resets the guard flag.

The next time the overlay is shown (next bedtime), `showOverlay()` creates
fresh questions, a fresh `OverlayView` with fresh `@State`, and a fresh kiosk
window. Nothing carries over.

### Step 5: Build and verify

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  build 2>&1 | tail -5
```

To test without waiting for actual bedtime to end:

1. Set your bedtime to start at the current hour and end at the current hour + 1
   (e.g., if it's 3 PM, set start=15, end=16)
2. Show the overlay (via menu bar "Test Overlay" or daemon)
3. Wait for the end hour to pass
4. The overlay should auto-dismiss within 60 seconds of the hour changing

For faster testing, you can temporarily change the timer interval from `60` to
`5` and set your bedtime end to the current hour (so it's already past). The
overlay should dismiss within 5 seconds.

**Don't forget to change the timer interval back to `60` after testing.**

---

## macOS Compatibility Notes

| API | Minimum macOS |
|-----|---------------|
| `Timer.scheduledTimer(withTimeInterval:repeats:block:)` | 10.12 |
| `Timer.invalidate()` | Foundation (always) |

Everything here works on macOS 11+.

---

## Edge Cases to Be Aware Of

**System sleep/wake:** If the Mac sleeps at 11 PM and wakes at 8 AM, the timer
fires shortly after wake. `isWithinBedtimeWindow` returns false (it's 8 AM,
past the 7 AM end), and the overlay dismisses. This works correctly without
special handling because `Timer` fires its pending events after the system wakes.

**User changes bedtime settings while overlay is showing:** The timer reads
`AppSettings.shared` fresh on each tick. If the user somehow managed to change
settings (they can't — the overlay blocks interaction), the new values would be
picked up automatically.

**Test Overlay outside bedtime:** If you use "Test Overlay" from the menu bar
while it's not bedtime, `checkBedtimeEnd()` will fire on the first tick and
immediately dismiss the overlay (because `isWithinBedtimeWindow` is false). If
you want "Test Overlay" to stay up regardless, you'd need to skip starting the
timer for test invocations. For now this is probably fine — it still proves the
overlay works, just briefly.
