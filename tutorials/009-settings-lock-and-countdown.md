# Settings Lock and Countdown

The settings window has a lock mechanism: users can't just change their bedtime
whenever they feel like it (because they'd weaken it right when the app is doing
its job). Instead, they request a change, wait 20 minutes, then get a 20-minute
window to edit. This is a commitment device — and a good one.

You've got the skeleton in place: `SettingsView` switches between
`LockedSettingsView` and `UnlockedSettingsView` based on a timestamp. But
several things are broken or incomplete. This tutorial walks through fixing
them.

---

## Does @AppStorage Make Sense Here?

**Yes**, and here's why:

`@AppStorage` backed by the shared UserDefaults suite (`com.gotosleep.shared`)
is the right tool for this timestamp because:

1. **It persists across app launches.** If the user requests a change then
   quits the app, the countdown continues. When they reopen, the remaining time
   is still correct because it's stored as a Unix epoch timestamp, not a
   relative "seconds remaining" value.

2. **It's reactive.** `@AppStorage` is a property wrapper that triggers SwiftUI
   view updates when the value changes. When the button writes a new timestamp,
   any view reading that `@AppStorage` key re-evaluates automatically.

3. **The shared suite means the daemon can read it too.** If you ever want the
   daemon to know about pending settings changes (e.g., to show a notification),
   it can read the same key from `UserDefaults(suiteName:
"com.gotosleep.shared")`.

4. **`Int` for epoch timestamps is fine.** Simple, no encoding/decoding, no
   ambiguity with time zones. `Int(Date().timeIntervalSince1970)` round-trips
   cleanly.

The one thing to understand: `@AppStorage` with `Int` defaults to `0`. A
timestamp of `0` means January 1, 1970 — the alteration window for that would
be 1200–2400 seconds after epoch, which is decades in the past. So
`inAlterationWindow` correctly evaluates to `false` on first run, meaning the
settings start locked. This isn't accidental — it's a useful property of the
design.

---

## What's Currently Broken

Open `GoToSleep/Views/SettingsView.swift` and look at the three structs:
`SettingsView`, `UnlockedSettingsView`, and `LockedSettingsView`.

### Bug 1: The "Request change" button does nothing

Look at line 130-132:

```swift
Button("Request change") {

}
```

The closure is empty. What should it do?

### Bug 2: The countdown doesn't count down

Look at `LockedSettingsView`, line 120:

```swift
private let currentTime = Int(Date().timeIntervalSince1970)
```

This is a `let` — a constant. It captures the current time once when the struct
is created. Now look at line 128:

```swift
Text("Opens in \(startTime - currentTime) seconds")
```

Ask yourself: does `currentTime` ever change? The parent `SettingsView` has a
1-second timer that increments `tickCount`, which forces a body re-evaluation,
which creates a _new_ `LockedSettingsView` struct. So `currentTime` _does_ get
a fresh value each second — but only because the parent happens to rebuild the
child every tick.

This works by accident. If you ever refactor the timer, move it, or change how
the parent rebuilds, the countdown silently breaks. It's also confusing to
read — someone looking at `private let currentTime` would reasonably think "this
never changes".

### Bug 3: The countdown shows raw seconds

"Opens in 1137 seconds" is not a great user experience. The user would prefer
"Opens in 18:57".

### Bug 4: No state for "never requested"

When settings open for the first time, `requestedSettingsChangeTimestamp` is 0.
The alteration window is `1200...2400` (epoch). Current time is ~1.7 billion. So
`startTime > currentTime` is false, and the button shows. This is correct.

But after the user clicks "Request change" and the 40-minute window passes,
they're back to seeing the button. What if you want to distinguish between
"never requested" and "request expired"? Right now you can't — both show the
same button. This isn't necessarily a bug (maybe you want both states to look
identical), but it's worth being aware of.

---

## Try It Yourself First

Here are breadcrumbs for each fix. Try implementing them before reading the full
solution.

### Fix the button

The button needs to write the current Unix timestamp into
`requestedSettingsChangeTimestamp`. `LockedSettingsView` already has an
`@AppStorage` property for this key. What one line goes in the button closure?

### Fix the countdown

You need `currentTime` to be reactive — it should update every second. You have
a few options:

- **Option A:** Remove `currentTime` from `LockedSettingsView` entirely.
  Instead, pass the current timestamp _into_ the view as a parameter from the
  parent (which already has a timer ticking). This makes the data flow explicit.

- **Option B:** Give `LockedSettingsView` its own timer (via `.onReceive`) and
  store the current time in a `@State` property that updates each tick.

- **Option C:** Compute the remaining seconds as a function of `startTime` and
  `Date()` inside a computed property, and rely on the parent's timer to trigger
  re-creation. This is essentially what you have now — but made intentional by
  documenting why it works.

Which approach makes the dependency on the timer most obvious? Which is hardest
to accidentally break?

### Format the countdown

Given a number of remaining seconds (e.g. 1137), how would you display
"18:57"? Think: integer division and modulo. You need minutes and seconds.
What format string would you use? Think about zero-padding the seconds (e.g.
"3:07" not "3:7").

`String(format:)` with `%d:%02d` is one approach. There are others.

---

## Full Solution

### Step 1: Wire up the button

In `LockedSettingsView`, the button needs to record the current time:

```swift
Button("Request change") {
    requestedSettingsChangeTimestamp = Int(Date().timeIntervalSince1970)
}
```

That's it. When this fires:

1. `requestedSettingsChangeTimestamp` writes to shared UserDefaults via
   `@AppStorage`
2. The parent `SettingsView` also reads this `@AppStorage` key, so its computed
   properties (`settingsAlterationWindowStart`, `inAlterationWindow`) update
3. `startTime > currentTime` becomes `true` (start is 20 minutes from now)
4. The view switches from showing the button to showing the countdown

### Step 2: Make the countdown explicit

Replace the `private let currentTime` approach. Pass the current time in from
the parent, which already has a timer driving updates.

**In `SettingsView`**, change how `LockedSettingsView` is created:

```swift
// Before:
LockedSettingsView(startTime: settingsAlterationWindowStart)

// After:
LockedSettingsView(
    startTime: settingsAlterationWindowStart,
    currentTime: Int(Date().timeIntervalSince1970)
)
```

The parent's `tickCount` timer fires every second, rebuilds the body, and
passes a fresh `currentTime` each time. The data flow is now visible in the
call site — anyone reading this line knows the countdown depends on a
time value from the parent.

**In `LockedSettingsView`**, change `currentTime` from a private constant to a
parameter:

```swift
// Before:
private let currentTime = Int(Date().timeIntervalSince1970)

// After:
let currentTime: Int
```

### Step 3: Format the countdown nicely

Add a helper to `LockedSettingsView` that formats remaining seconds as
`MM:SS`:

```swift
private func formatCountdown(_ totalSeconds: Int) -> String {
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
```

Then update the countdown text:

```swift
// Before:
Text("Opens in \(startTime - currentTime) seconds")

// After:
Text("Opens in \(formatCountdown(startTime - currentTime))")
```

Now the user sees "Opens in 18:57" instead of "Opens in 1137 seconds".

### Step 4: Polish the locked view

The locked view is pretty bare. Here's a more complete version with a bit of
visual hierarchy:

```swift
struct LockedSettingsView: View {
    @AppStorage("requestedSettingsChangeTimestamp",
                store: UserDefaults(suiteName: AppSettings.suiteName))
    private var requestedSettingsChangeTimestamp: Int

    let startTime: Int
    let currentTime: Int

    private var remainingSeconds: Int {
        max(0, startTime - currentTime)
    }

    private var hasActiveRequest: Bool {
        remainingSeconds > 0
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("Settings are locked")
                .font(.title2)
                .fontWeight(.medium)

            if hasActiveRequest {
                Text("Opens in \(formatCountdown(remainingSeconds))")
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            } else {
                Text("Request a 20-minute window to change your settings.")T
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)

                Button("Request change") {
                    requestedSettingsChangeTimestamp = Int(Date().timeIntervalSince1970)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func formatCountdown(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

Key details:

- **`remainingSeconds`** — computed property using `max(0, ...)` to avoid
  negative values during the transition second where the parent hasn't switched
  to `UnlockedSettingsView` yet.
- **`hasActiveRequest`** — clearer name for the conditional than raw
  `startTime > currentTime`.
- **`.monospacedDigit()`** — prevents the countdown text from jiggling
  left/right as digits change width (e.g. "1" is narrower than "8" in
  proportional fonts). Forces all digits to the same width.
- **`.keyboardShortcut(.defaultAction)`** — makes the button blue (the "default
  action" appearance), same pattern used elsewhere in the project to avoid
  `.buttonStyle(.borderedProminent)` which requires macOS 12+.
- **Lock icon** — `SF Symbols` `lock.fill` gives a visual cue that reinforces
  the locked state.

### Step 5: Update the parent to pass currentTime

Here's the complete updated `SettingsView`:

```swift
struct SettingsView: View {

    @AppStorage("requestedSettingsChangeTimestamp",
                store: UserDefaults(suiteName: AppSettings.suiteName))
    private var requestedSettingsChangeTimestamp: Int = 0

    private let twentyMinutesInSeconds: Int = 1200

    private var settingsAlterationWindowStart: Int {
        requestedSettingsChangeTimestamp + twentyMinutesInSeconds
    }

    private var settingsAlterationWindowEnd: Int {
        requestedSettingsChangeTimestamp + 2 * twentyMinutesInSeconds
    }

    private var inAlterationWindow: Bool {
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        return currentTimestamp >= settingsAlterationWindowStart
            && currentTimestamp <= settingsAlterationWindowEnd
    }

    @State private var tickCount = 0

    var body: some View {
        Group {
            if inAlterationWindow {
                UnlockedSettingsView()
            } else {
                LockedSettingsView(
                    startTime: settingsAlterationWindowStart,
                    currentTime: Int(Date().timeIntervalSince1970)
                )
                .frame(width: 400, height: 300)
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            tickCount += 1
        }
    }
}
```

The only changes from your current version:

1. `LockedSettingsView` now receives `currentTime` as a parameter
2. `inAlterationWindow` body simplified (same logic, fewer lines)

### Step 6: Build and verify

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  build 2>&1 | tail -5
```

Then test the flow:

1. Launch the app, open Settings — you should see the locked view with the
   "Request change" button
2. Click the button — it should switch to a countdown ("Opens in 19:59" and
   counting down)
3. For testing, temporarily change `twentyMinutesInSeconds` to `10` (10
   seconds) so you don't have to wait 20 minutes
4. Watch the countdown reach 0:00 — the view should switch to the unlocked
   settings form
5. Wait another 10 seconds (with the temporary value) — it should lock again

**Don't forget to change `twentyMinutesInSeconds` back to `1200` after
testing.**

---

## macOS Compatibility Notes

| API                                 | Minimum macOS       |
| ----------------------------------- | ------------------- |
| `@AppStorage`                       | 11.0                |
| `.monospacedDigit()`                | 11.0                |
| `Image(systemName:)` (SF Symbols)   | 11.0                |
| `.keyboardShortcut(.defaultAction)` | 11.0                |
| `GroupBox`                          | 10.15               |
| `String(format:)`                   | Foundation (always) |

Everything here works on macOS 11+.

---

## Design Considerations

A few things to think about as you use this:

**The 20-minute delay is the whole point.** If you're tempted to shorten it for
convenience, remember: the reason this exists is to prevent you from weakening
your bedtime rules in the moment. The friction is the feature.

**The 20-minute edit window auto-closes.** If you open settings, request a
change, wait, then get distracted, the window expires. This is intentional —
it prevents leaving settings permanently unlocked.

**The daemon doesn't need to know about the lock.** The lock is purely a UI
concern. The daemon reads `bedtimeStartHour`, `bedtimeEndHour`, etc. from
shared UserDefaults — it doesn't care whether the settings window was locked or
unlocked when those values were written.
