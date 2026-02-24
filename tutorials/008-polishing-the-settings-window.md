# Polishing the Settings Window

The settings window currently works, but it looks cramped and unpolished. This
tutorial walks through improving it — the layout, spacing, and visual structure
— so it feels like a proper macOS settings panel.

---

## What You're Working With

The settings UI is **SwiftUI**, not AppKit. The `SettingsView` struct in
`GoToSleep/Views/SettingsView.swift` defines all the controls. The AppDelegate
just wraps it in an `NSHostingController` and presents it inside a plain
`NSWindow`.

So all the visual improvements happen in SwiftUI. You don't need to touch
AppDelegate's window creation code (beyond possibly adjusting the window size).

---

## Try It Yourself First

Before reading the full solution, here are some pointers. Open
`GoToSleep/Views/SettingsView.swift` and the screenshot side by side. Ask
yourself:

### Why does it feel cramped?

Look at the `.frame(width: 400, height: 320)` at the bottom of the view body.
Then look at the `Form` — does it have any padding? What happens if you add
`.padding()` to the Form, or wrap it in a VStack with padding?

### Why do the sections blur together?

On macOS, SwiftUI's `Form` with `Section(header:)` renders section headers as
small grey text with no visual boundary between groups. Compare this to how
macOS System Preferences panels look — they use bordered boxes to group related
controls.

SwiftUI has a view called `GroupBox` (available since macOS 10.15) that draws a
rounded, bordered box around its content. What happens if you replace
`Section(header: Text("Schedule"))` with `GroupBox(label: Text("Schedule"))`?

### Why are the labels misaligned?

The `Form` on macOS uses a two-column layout: labels on the left, controls on
the right. This is actually fine and is the standard macOS pattern. But notice
how "Questions per session: 1" has the value baked into the label string on the
Stepper — it reads as one long left-column label that pushes the stepper arrow
far to the right. What if the label and value were separated?

### Why does the window feel like the wrong size?

The window is 400x320, but the content doesn't quite fill it properly. SwiftUI
forms have their own intrinsic size based on content. Try removing the explicit
`.frame()` on the view and instead only setting the window size in
`AppDelegate.swift` via `setContentSize`. Or try using `.frame(minWidth:,
idealWidth:, minHeight:, idealHeight:)` to let the content breathe.

### Things to experiment with

1. Add `.padding()` around or inside the Form
2. Replace `Section` with `GroupBox`
3. Increase the window size in AppDelegate (try 460x380 or 480x400)
4. Update the `.frame()` on SettingsView to match
5. Add spacing between the GroupBoxes with a `VStack(spacing: 16)`

Give it a go. Build, open Settings from the menu bar, and iterate visually.
When you're happy (or stuck), read on.

---

## Full Solution

### The problems

1. **No padding** — The Form content extends right to the window edges with
   minimal margins, making everything feel jammed in.

2. **Flat section headers** — `Section(header: Text(...))` inside a `Form` on
   macOS renders as small grey text with no visual border or background. The
   sections visually run into each other.

3. **Tight window** — 400x320 doesn't give the content enough room to breathe,
   especially once you add proper spacing.

4. **Stepper label includes value** — `"Questions per session: \(n)"` makes the
   label column unnecessarily wide and looks unbalanced.

### The approach

Replace the `Form` + `Section` pattern with a `ScrollView` containing a
`VStack` of `GroupBox` views. This gives you:

- Visible bordered boxes around each group (the standard macOS look for
  preference panels)
- Full control over spacing and padding
- No reliance on Form's automatic two-column layout (which you can replicate
  manually where needed)

### Step 1: Update the window size

In `GoToSleep/App/AppDelegate.swift`, find the `showSettingsWindow()` method.
Change the content size:

```swift
// Before:
settingsWindow.setContentSize(NSSize(width: 400, height: 320))

// After:
settingsWindow.setContentSize(NSSize(width: 460, height: 370))
```

This gives the content more room. You'll also update the frame in the view to
match.

### Step 2: Rewrite SettingsView

Replace the entire body of `SettingsView.swift` with the layout below. This
keeps all the same bindings and data — it's purely a visual restructure.

Here's the new view structure:

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    private let gracePeriodOptions = [
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 hour"),
        (120, "2 hours"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            scheduleSection
            questionsSection
            afterCompletionSection
        }
        .padding(24)
        .frame(width: 460, height: 370)
    }

    // MARK: - Sections

    private var scheduleSection: some View {
        GroupBox(label: Text("Schedule").font(.headline)) {
            VStack(spacing: 12) {
                settingsRow("Enabled") {
                    Toggle("", isOn: $settings.isEnabled)
                        .labelsHidden()
                }

                settingsRow("Bedtime starts at") {
                    Picker("", selection: $settings.bedtimeStartHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                settingsRow("Bedtime ends at") {
                    Picker("", selection: $settings.bedtimeEndHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(formatHour(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
            .padding(.top, 8)
        }
    }

    private var questionsSection: some View {
        GroupBox(label: Text("Questions").font(.headline)) {
            VStack(spacing: 12) {
                settingsRow("Questions per session") {
                    Stepper("\(settings.questionsPerSession)",
                            value: $settings.questionsPerSession, in: 1...10)
                }
            }
            .padding(.top, 8)
        }
    }

    private var afterCompletionSection: some View {
        GroupBox(label: Text("After Completion").font(.headline)) {
            VStack(spacing: 12) {
                settingsRow("Grace period") {
                    Picker("", selection: $settings.gracePeriodMinutes) {
                        ForEach(gracePeriodOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func settingsRow<Content: View>(_ label: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
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
}
```

### What changed and why

#### `Form` + `Section` replaced with `VStack` + `GroupBox`

`Form` on macOS applies its own two-column layout and styling, which is
opinionated and hard to override. By switching to a manual `VStack` of
`GroupBox` views, you get:

- **Visible borders** around each group — the rounded rectangle that macOS
  users expect from preference panels
- **Full control** over alignment, spacing, and padding
- **Consistent look** across macOS versions (Form rendering varies between OS
  versions)

#### Custom `settingsRow` helper

Instead of relying on Form's automatic label/control alignment, the
`settingsRow` helper creates explicit `HStack` rows with `Text` on the left,
`Spacer()` in the middle, and the control on the right. This gives you the same
two-column layout but with predictable sizing.

The controls use `.labelsHidden()` because the label is already provided by the
`Text` in the HStack — without this, you'd get double labels (one from the
HStack Text, one from the Picker/Toggle's own label).

#### Stepper label separated from value

Before:
```swift
Stepper("Questions per session: \(settings.questionsPerSession)", ...)
```

The entire string including the number was treated as the label column, pushing
the stepper control far right and making the row look unbalanced.

After:
```swift
settingsRow("Questions per session") {
    Stepper("\(settings.questionsPerSession)", value: ...)
}
```

Now "Questions per session" is the left-column label, and the stepper (showing
just the number and arrows) is the right-column control.

#### Fixed-width pickers

```swift
.frame(width: 140)
```

Without an explicit width, the Picker dropdown stretches to fill available
space, making it look oversized. 140pt is enough for "15 minutes" or "9 PM"
without wasting space.

#### Padding

```swift
.padding(24)
```

24 points of padding on all sides gives the content breathing room from the
window edges. The `.padding(.top, 8)` inside each GroupBox adds a small gap
between the GroupBox label and the first row of controls.

#### Spacing

```swift
VStack(alignment: .leading, spacing: 16)
```

16 points between each GroupBox. 12 points between rows inside each GroupBox.
This creates a clear visual hierarchy: groups are further apart than items
within a group.

### Step 3: Build and verify

```bash
xcodebuild -project GoToSleep.xcodeproj \
  -target GoToSleep \
  -configuration Debug \
  build 2>&1 | tail -5
```

Launch the app, click the menu bar icon, and open Settings. You should see:

- Three visually distinct bordered boxes (Schedule, Questions, After Completion)
- Labels left-aligned, controls right-aligned with consistent spacing
- Proper padding from the window edges
- The whole thing feeling like a real macOS preferences panel

### Step 4: Fine-tuning (optional)

Once the basic structure is working, you might want to tweak:

- **Window size**: If the content feels too tight or too loose, adjust both
  `setContentSize` in AppDelegate and `.frame()` in SettingsView. They should
  match.
- **Picker width**: If "15 minutes" gets clipped, bump the `.frame(width:)` up
  to 160 or 180.
- **GroupBox label style**: If `.font(.headline)` is too bold, try
  `.font(.subheadline)` or `.font(.body).bold()`.
- **Spacing values**: The 16pt/12pt spacing works well as a starting point.
  Increase for more air, decrease for a denser look.

### Step 5: Remove debug logging

While you're in here, this is a good time to remove those
`[GTS_DEBUG_REMOVE_ME]` `onChange` handlers if you no longer need them. They're
useful during development but add noise to the console and shouldn't ship.

---

## macOS Compatibility Notes

Everything in this tutorial works on **macOS 11+**:

| API | Minimum macOS |
|-----|---------------|
| `GroupBox(label:content:)` | 10.15 |
| `VStack`, `HStack`, `Spacer` | 10.15 |
| `.labelsHidden()` | 10.15 |
| `.font(.headline)` | 10.15 |
| `@ViewBuilder` | 10.15 |

No macOS 13+ APIs are used.
