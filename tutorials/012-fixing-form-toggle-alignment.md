# Why Your Toggles Don't Align With the Rest of the Form

The Settings view uses a macOS SwiftUI `Form` to lay out pickers, steppers, and
toggles. The pickers and stepper look correct — label on the left, control on the
right, all left edges aligned. But the skill tag toggles (Half Life Decay,
Percentages) are center-aligned and vertically stacked with no left-hand label,
breaking the visual consistency.

This tutorial explains why the toggles don't participate in the form's alignment
system, and the fix.

---

## The Symptom

The settings form has rows that look like this:

```
  Bedtime starts at    [9 pm ▾]
  Bedtime ends at      [7 am ▾]
  Questions per session: 2  [⬆⬇]
                    ☑ Half Life Decay
                    ☑ Percentages
  Grace period           [15 minutes ▾]
```

The toggles sit in a centered blob below the stepper. They don't have a left-hand
label. They don't align with "Bedtime starts at" or "Grace period". They look like
they belong to a different UI.

---

## Understanding macOS Form Layout

A macOS SwiftUI `Form` uses a two-column layout:

```
  [label]              [control]
  [label]              [control]
  [label]              [control]
```

Each **direct child** of the `Form` (or `Section`) that is a standard SwiftUI
control — `Picker`, `Stepper`, `Toggle`, `TextField` — gets this treatment
automatically. The form inspects the view's label and places it in the left
column, with the interactive control in the right column.

The key phrase is **direct child**. The form only applies its two-column alignment
to views it recognises as form rows. If you wrap multiple toggles in a `VStack`
and drop that `VStack` into the form, the form sees one opaque child (the VStack),
not individual toggles. It renders the whole VStack as a single row's content,
centered, with no label column.

---

## Why It Breaks

The `SkillTagTogglesView` is structured like this:

```swift
struct SkillTagTogglesView: View {
    var body: some View {
        // ...
        VStack(spacing: 4) {                    // <-- opaque container
            ForEach(allTags, id: \.self) { tag in
                Toggle(friendlyName(for: tag),   // <-- individual toggles
                       isOn: ...)
            }
        }
    }
}
```

The `VStack` wraps the toggles into a single view. When the form encounters
`SkillTagTogglesView()`, it sees one custom view, not N toggles. It can't extract
the individual labels, so it falls back to rendering the whole thing as a single
centered block.

The same thing would happen if you wrapped pickers or steppers in a VStack
and dropped them into a form — they'd lose their label alignment too.

---

## The Fix

Remove the `VStack` wrapper so each `Toggle` is a direct child of the `Section`.

### Before (broken)

```swift
Section {
    Stepper(
        "Questions per session: \(settings.questionsPerSession)",
        value: $settings.questionsPerSession, in: 1...10
    )

    SkillTagTogglesView()      // <-- opaque VStack, form can't see the toggles
        .padding(.bottom, 32)
}
```

`SkillTagTogglesView` returns a `VStack` of toggles. The form treats it as one
row.

### After (fixed)

Inline the `ForEach` directly into the `Section`, or refactor
`SkillTagTogglesView` to return a bare `ForEach` without a wrapping container:

```swift
Section {
    Stepper(
        "Questions per session: \(settings.questionsPerSession)",
        value: $settings.questionsPerSession, in: 1...10
    )

    ForEach(store.allAvailableTags.sorted(), id: \.self) { tag in
        Toggle(
            friendlyName(for: tag),
            isOn: Binding(
                get: { enabledTags.contains(tag) },
                set: { enabled in
                    var tags = settings.getEnabledTags()
                    if enabled { tags.insert(tag) } else { tags.remove(tag) }
                    settings.setEnabledTags(tags)
                }
            )
        )
    }
    .padding(.bottom, 32)
}
```

Each `Toggle` is now a direct child of the `Section`. The form recognises each
one as a form row, places its label ("Half Life Decay", "Percentages") in the
left column, and the checkbox in the right column:

```
  Questions per session: 2   [⬆⬇]
  Half Life Decay            [☑]
  Percentages                [☑]
```

All left edges align with "Bedtime starts at", "Grace period", etc.

---

## The General Rule

**Every view you want the form to align must be a direct child of the `Form` or
`Section`.**

If you wrap form controls in a container (`VStack`, `HStack`, `Group` with
modifiers, a custom view that returns a container), the form can't inspect the
individual controls. It falls back to rendering the container as an opaque blob.

This applies to:

| Pattern | Form sees | Result |
|---------|-----------|--------|
| `Toggle("A", ...)` directly in Section | A toggle | Aligned row |
| `ForEach { Toggle(...) }` in Section | N toggles | N aligned rows |
| `VStack { ForEach { Toggle(...) } }` in Section | One VStack | One centered blob |
| `CustomView()` returning a `VStack` of toggles | One custom view | One centered blob |

If you need a reusable component, have it return a `ForEach` or use
`@ViewBuilder` to return multiple views without a wrapping container:

```swift
@ViewBuilder
var skillTagToggles: some View {
    ForEach(allTags, id: \.self) { tag in
        Toggle(friendlyName(for: tag), isOn: ...)
    }
}
```

This way the form still sees each `Toggle` as a direct child.

---

## macOS Compatibility Notes

| API | Minimum macOS |
|-----|---------------|
| `Form` | SwiftUI 1.0 (10.15) |
| `Toggle` | SwiftUI 1.0 (10.15) |
| `ForEach` | SwiftUI 1.0 (10.15) |
| `@ViewBuilder` | SwiftUI 1.0 (10.15) |

No compatibility concerns. This is a pure layout restructure.
