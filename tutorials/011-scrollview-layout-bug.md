# Why Your Views Vanish Below a ScrollView

After implementing `HardMultipleChoiceView`, selecting an answer should show three
things below the choice list: a hint (for wrong answers), an explanation, and a
"Next" button. Debug prints confirm the code runs — but the UI shows nothing.
The views exist in memory but are invisible on screen.

This tutorial explains the bug, how to diagnose it, and the one-line structural
fix.

---

## The Symptom

After tapping a choice:

- `print()` inside `explanationSection` fires — the code path executes
- `print()` inside `nextButton` fires — the button is created
- The screen shows the choices with a green check or red cross on the selected one
- No hint, no explanation, no "Next" button appears underneath

Before tapping a choice, the layout looks fine. The bug only manifests when
conditional content appears below the `ScrollView`.

---

## Understanding the Layout Chain

To diagnose this you need to understand how the view is embedded. There are two
nested VStacks involved.

### The outer VStack (OverlayView)

```
ZStack (full screen)
  └─ VStack(spacing: 40)
       .padding(40)
       ├─ Spacer()              ← flexible
       ├─ scoreIndicator        ← fixed (~20pt)
       ├─ QuestionView          ← flexible (contains a ScrollView)
       │    .frame(maxWidth: 500)
       └─ Spacer()              ← flexible
```

The `QuestionView` sits between two `Spacer`s in a padded, full-screen VStack.
It has a max width constraint but **no explicit height constraint**. Its height
is whatever the outer VStack offers after the Spacers and score indicator take
their share.

### The inner VStack (HardMultipleChoiceView) — the buggy layout

```
VStack(alignment: .leading, spacing: 20)
  ├─ Text(question)             ← fixed
  ├─ ScrollView {               ← FLEXIBLE — this is the problem
  │    VStack(spacing: 10) {
  │      ForEach(choices) { choiceButton }
  │    }
  │  }
  ├─ explanationSection         ← fixed (conditional — only after selection)
  └─ nextButton                 ← fixed (conditional — only after selection)
```

---

## Why It Breaks

### Before selection

The inner VStack has three children:

1. `Text` — fixed size
2. `ScrollView` — flexible, content is 10 choice buttons
3. `nextButton` — a `Group` wrapping an `if selectedIndex != nil` that evaluates
   to `EmptyView`

There are effectively two real children. The `ScrollView` takes all remaining
vertical space after the `Text`. The empty `Group` takes zero space. Everything
fits. The choices scroll happily inside the `ScrollView`.

### After selection

`selectedIndex` changes from `nil` to a value. Now the inner VStack has four
children:

1. `Text` — fixed size (~50pt)
2. `ScrollView` — flexible, content is still 10 choice buttons (~600pt of content)
3. `explanationSection` — fixed size (~100pt of text)
4. `nextButton` — fixed size (44pt)

The total ideal height is now ~50 + 600 + 100 + 44 + spacing = ~854pt. The
available height (after the outer VStack's padding, spacing, Spacers, and score
indicator) might only be ~500–600pt.

SwiftUI's VStack layout algorithm should compress the `ScrollView` to make room
for its fixed-size siblings. In a simple VStack, it usually does. But here the
`ScrollView` is nested inside a more complex layout: the outer VStack has two
`Spacer`s competing for the same pool of flexible space. The interaction between
the outer Spacers and the inner ScrollView creates a layout negotiation where
the ScrollView retains more height than it should, and the explanation and button
are positioned below the bottom edge of the visible area.

**The views are rendered — they're just off-screen.** That's why the debug prints
fire but you see nothing.

### Why does this only happen after selection?

Before selection, there's nothing below the `ScrollView` that needs to be
visible. The `ScrollView` can greedily take all available space with no
consequences — there are no siblings being pushed out. After selection, new
siblings appear that need space, but the `ScrollView` doesn't yield enough of
its height to accommodate them.

---

## Diagnosing It

If you suspect a "views exist but are invisible" bug, here's a checklist:

### 1. Add print statements inside the view body

This is what the `[GTS_DEBUG_REMOVE_ME]` markers are for. If the print fires,
the view is being created. If you can't see it, it's a layout problem, not a
logic problem.

### 2. Check for greedy layout participants

Scan the view hierarchy for `ScrollView`, `Spacer`, `GeometryReader`, or any
view with `.frame(maxHeight: .infinity)`. These are flexible views that compete
for space. If one of them is a sibling with your invisible content, it's probably
hogging the space.

### 3. Add a temporary debug border

```swift
explanationSection(selectedIndex: selected)
    .border(Color.red, width: 2)
```

If the red border appears at the very bottom edge of the screen (or not at all),
the view is being positioned outside the visible bounds. If it appears but has
zero height, the content is being compressed.

### 4. Temporarily remove the ScrollView

Replace the `ScrollView` with a plain `VStack` and see if the explanation and
button appear. If they do, the `ScrollView` is the culprit.

---

## The Fix

The structural fix is to use **one ScrollView** that wraps all content, instead
of having a ScrollView as one sibling among several in a VStack.

### Before (broken)

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 20) {
        Text(resolved.resolvedText)
            .font(.title2)
            .fontWeight(.medium)
            .foregroundColor(.white)

        ScrollView {                          // ← greedy sibling
            VStack(spacing: 10) {
                ForEach(...) { choiceButton }
            }
        }

        if let selected = selectedIndex {     // ← pushed off-screen
            explanationSection(selectedIndex: selected)
        }

        nextButton                            // ← pushed off-screen
    }
}
```

The `ScrollView` is one child in the VStack. The explanation and button are
siblings positioned below it. When the ScrollView claims too much height, they
disappear.

### After (fixed)

```swift
var body: some View {
    ScrollView {                              // ← single ScrollView wraps everything
        VStack(alignment: .leading, spacing: 20) {
            Text(resolved.resolvedText)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)

            VStack(spacing: 10) {             // ← plain VStack, not a ScrollView
                ForEach(...) { choiceButton }
            }

            if let selected = selectedIndex {
                explanationSection(selectedIndex: selected)
            }

            nextButton
        }
    }
}
```

Two changes:

1. **The `ScrollView` moves to the outside**, wrapping the entire VStack
2. **The inner `ScrollView` becomes a plain `VStack`** — it no longer needs to
   scroll independently because the outer `ScrollView` handles all scrolling

Now every child (question text, choices, explanation, button) lives inside a
single scrollable container. There's no competition for space — the content is
as tall as it needs to be, and the user scrolls to see it all. The explanation
and button are always directly below the choices, never pushed off-screen.

---

## The General Rule

**Never put a `ScrollView` as a middle child in a VStack where conditional
content appears below it.**

The `ScrollView` is greedy — its ideal size is its content size. When you add
or remove siblings below it, the VStack's layout negotiation doesn't reliably
compress the `ScrollView` to make room, especially in nested flexible layouts
(like our outer VStack with Spacers).

Instead, pick one of these patterns:

### Pattern A: One outer ScrollView (what we did)

```swift
ScrollView {
    VStack {
        fixedContent
        listContent        // plain VStack, not ScrollView
        conditionalContent
        button
    }
}
```

Everything scrolls together. Simple and predictable.

### Pattern B: ScrollView at the bottom

```swift
VStack {
    fixedHeader
    ScrollView {
        listContent
    }
}
```

If you need a fixed header that never scrolls and a scrollable list below it,
this works — as long as there's nothing conditional below the `ScrollView`.

### Pattern C: ScrollView with pinned footer

```swift
VStack {
    ScrollView {
        listContent
    }
    conditionalFooter   // always below the ScrollView, never inside
}
```

This works when the footer content is small and you want it pinned to the
bottom rather than scrolling with the list. But be careful — if the ScrollView
content is very tall, the footer gets less space. Test with your maximum
content size.

---

## Why VerifiableFactView and CalculationQuestionView Don't Have This Bug

Neither of them uses a `ScrollView` for their input area. They use plain VStacks
with a `TextField` and a submit button. Their layout is entirely fixed-size
children inside a VStack — no flexible view competing for space. When the
explanation and button appear conditionally, the VStack simply grows taller
and everything remains visible.

---

## macOS Compatibility Notes

| API | Minimum macOS |
|-----|---------------|
| `ScrollView` | SwiftUI 1.0 (10.15) |
| `VStack` | SwiftUI 1.0 (10.15) |

No compatibility concerns. This is a pure layout restructure.
