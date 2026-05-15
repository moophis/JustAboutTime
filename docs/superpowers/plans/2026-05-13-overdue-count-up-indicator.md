# Overdue Count-Up Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the menu bar due count-up state show red timer text and a blinking full progress fill.

**Architecture:** Keep overdue/due state calculation in `TimerStore`, pass explicit progress blink state through `CountdownProgressPresentation`, and keep drawing decisions inside `StatusBarLabelImageRenderer`. Reuse the existing one-second `animationStep` so dots and the progress fill blink in sync without adding another timer.

**Tech Stack:** Swift, SwiftUI/AppKit `NSImage` rendering, Swift Testing, Xcode macOS app target.

---

## File Structure

- Modify `JustAboutTime/TimerStore.swift`: add progress blink fields, compute fill visibility from `animationStep`, and return blinking full progress for due/completed countdown display.
- Modify `JustAboutTime/JustAboutTimeApp.swift`: render blinking progress fill and make due timer text red.
- Modify `JustAboutTimeTests/TimerStoreTests.swift`: assert blinking progress for completed/due states and non-blinking progress for normal warning countdowns.

No commits are included in this plan because repo instructions say not to commit unless the user explicitly requests it.

---

### Task 1: Add Explicit Progress Blink State

**Files:**
- Modify: `JustAboutTime/TimerStore.swift:246-286`
- Modify: `JustAboutTime/TimerStore.swift:378-381`

- [ ] **Step 1: Pass animation step into progress generation**

In `TimerStore.synchronizePresentation(referenceTime:events:)`, replace the current progress assignment:

```swift
countdownProgress = countdownProgress(for: session, referenceTime: referenceTime)
```

with:

```swift
countdownProgress = countdownProgress(for: session, referenceTime: referenceTime, animationStep: animationStep)
```

- [ ] **Step 2: Replace progress generation with due blink support**

Replace `countdownProgress(for:referenceTime:)` with:

```swift
private func countdownProgress(
    for session: TimerSession?,
    referenceTime: Date,
    animationStep: Int
) -> CountdownProgressPresentation? {
    if session != nil, isCountingUpAfterCountdown, lastCompletedCountdownDuration != nil {
        return dueCountdownProgress(animationStep: animationStep)
    }

    if session == nil, latestEvent == .countdownCompleted, let duration = lastCompletedCountdownDuration, duration > 0 {
        return dueCountdownProgress(animationStep: animationStep)
    }

    guard let session,
          let duration = session.originalDuration,
          duration > 0,
          let remaining = session.remainingTime(at: referenceTime) else {
        return nil
    }

    return CountdownProgressPresentation(
        fractionComplete: min(1, max(0, remaining / duration)),
        isWarning: isCountdownWarning(remaining: remaining, duration: duration)
    )
}

private func dueCountdownProgress(animationStep: Int) -> CountdownProgressPresentation {
    CountdownProgressPresentation(
        fractionComplete: 1.0,
        isWarning: true,
        isBlinking: true,
        isFillVisible: animationStep.isMultiple(of: 2)
    )
}
```

- [ ] **Step 3: Extend `CountdownProgressPresentation`**

Replace the struct at the bottom of `JustAboutTime/TimerStore.swift` with:

```swift
struct CountdownProgressPresentation: Equatable {
    let fractionComplete: Double
    let isWarning: Bool
    let isBlinking: Bool
    let isFillVisible: Bool

    init(
        fractionComplete: Double,
        isWarning: Bool,
        isBlinking: Bool = false,
        isFillVisible: Bool = true
    ) {
        self.fractionComplete = fractionComplete
        self.isWarning = isWarning
        self.isBlinking = isBlinking
        self.isFillVisible = isFillVisible
    }
}
```

---

### Task 2: Render Red Text And Blinking Fill

**Files:**
- Modify: `JustAboutTime/JustAboutTimeApp.swift:126-181`
- Modify: `JustAboutTime/JustAboutTimeApp.swift:192-247`

- [ ] **Step 1: Use red text only for blinking due progress**

In `StatusBarLabelImageRenderer.image(presentation:countdownProgress:colorScheme:)`, replace the color and attributes setup with:

```swift
let needsOriginalColor = usesSemanticRed(presentation: presentation, countdownProgress: countdownProgress)
let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor
let textColor = countdownProgress?.isBlinking == true ? NSColor.systemRed : primaryColor
let attributes = textAttributes(foregroundColor: textColor)
```

- [ ] **Step 2: Keep semantic-red rendering enabled for blinking progress**

Replace `usesSemanticRed(presentation:countdownProgress:)` with:

```swift
private static func usesSemanticRed(
    presentation: TimerStatusPresentation,
    countdownProgress: CountdownProgressPresentation?
) -> Bool {
    presentation.dotPhase == .leadingRed ||
        presentation.dotPhase == .trailingRed ||
        countdownProgress?.isWarning == true ||
        countdownProgress?.isBlinking == true
}
```

- [ ] **Step 3: Hide only the inner fill on blink-off frames**

In `drawProgress(_:primaryColor:in:)`, keep outline drawing unchanged and insert this guard immediately after `outlinePath.stroke()`:

```swift
guard progress.isFillVisible else {
    return
}
```

The middle of the method should read:

```swift
progressColor.setStroke()
outlinePath.lineWidth = 1
outlinePath.stroke()

guard progress.isFillVisible else {
    return
}

let fillRect = outlineRect.insetBy(dx: Layout.progressInset, dy: Layout.progressInset)
```

---

### Task 3: Update Timer Store Tests

**Files:**
- Modify: `JustAboutTimeTests/TimerStoreTests.swift:136-159`
- Modify: `JustAboutTimeTests/TimerStoreTests.swift:286-362`

- [ ] **Step 1: Assert normal warning progress does not blink**

In `countdownProgressTracksRemainingFractionAndWarningWindow`, replace the warning assertion block after `store.pause()` with:

```swift
#expect(store.countdownProgress == CountdownProgressPresentation(fractionComplete: 0.1, isWarning: true))
#expect(store.countdownProgress?.isBlinking == false)
#expect(store.countdownProgress?.isFillVisible == true)
```

- [ ] **Step 2: Assert completed countdown progress blinks**

In `timerStoreSurfacesCountdownCompletionEvents`, replace the assertions from `#expect(store.latestEvent == .countdownCompleted)` through the final progress assertion after the second tick with:

```swift
#expect(store.latestEvent == .countdownCompleted)
#expect(store.activeSession == nil)
#expect(store.statusPresentation.text == "00:00")
let completedProgress = try #require(store.countdownProgress)
#expect(completedProgress.fractionComplete == 1)
#expect(completedProgress.isWarning)
#expect(completedProgress.isBlinking)
#expect(completedProgress.isFillVisible == (store.statusPresentation.dotPhase == .leadingRed))
let completedDotPhase = store.statusPresentation.dotPhase
let completedFillVisible = completedProgress.isFillVisible
#expect([DotPhase.leadingRed, .trailingRed].contains(completedDotPhase))

clock.advance(by: 1)
await sleeper.resumeOnce()
while store.statusPresentation.dotPhase == completedDotPhase {
    await Task.yield()
}

#expect(store.statusPresentation.text == "00:00")
let nextCompletedProgress = try #require(store.countdownProgress)
#expect(nextCompletedProgress.fractionComplete == 1)
#expect(nextCompletedProgress.isWarning)
#expect(nextCompletedProgress.isBlinking)
#expect(nextCompletedProgress.isFillVisible == (store.statusPresentation.dotPhase == .leadingRed))
#expect(nextCompletedProgress.isFillVisible != completedFillVisible)
#expect([DotPhase.leadingRed, .trailingRed].contains(store.statusPresentation.dotPhase))
#expect(store.statusPresentation.dotPhase != completedDotPhase)
```

- [ ] **Step 3: Assert overdue count-up progress blinks**

In `completedCountdownCountsUpWhenPreferenceIsEnabled`, replace the assertions from `#expect(store.latestEvent == .countdownCompleted)` through the final progress assertion after the second tick with:

```swift
#expect(store.latestEvent == .countdownCompleted)
#expect(store.activeSession?.mode == .countUp)
#expect(store.statusPresentation.text == "00:02")
#expect([DotPhase.leadingRed, .trailingRed].contains(store.statusPresentation.dotPhase))
let overdueProgress = try #require(store.countdownProgress)
#expect(overdueProgress.fractionComplete == 1)
#expect(overdueProgress.isWarning)
#expect(overdueProgress.isBlinking)
#expect(overdueProgress.isFillVisible == (store.statusPresentation.dotPhase == .leadingRed))
let overdueDotPhase = store.statusPresentation.dotPhase
let overdueFillVisible = overdueProgress.isFillVisible

clock.advance(by: 1)
await sleeper.resumeOnce()
while store.statusPresentation.text != "00:03" {
    await Task.yield()
}

#expect(store.activeSession?.mode == .countUp)
#expect([DotPhase.leadingRed, .trailingRed].contains(store.statusPresentation.dotPhase))
#expect(store.statusPresentation.dotPhase != overdueDotPhase)
let nextOverdueProgress = try #require(store.countdownProgress)
#expect(nextOverdueProgress.fractionComplete == 1)
#expect(nextOverdueProgress.isWarning)
#expect(nextOverdueProgress.isBlinking)
#expect(nextOverdueProgress.isFillVisible == (store.statusPresentation.dotPhase == .leadingRed))
#expect(nextOverdueProgress.isFillVisible != overdueFillVisible)
```

---

### Task 4: Verify Build And Tests

**Files:**
- Verify: `JustAboutTime.xcodeproj`
- Verify: `JustAboutTimeTests/TimerStoreTests.swift`

- [ ] **Step 1: Delegate the test run to the mechanical subagent**

Ask `@mechanical` to run:

```bash
xcodebuild test -scheme JustAboutTime -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

Expected result: command exits 0 and includes `** TEST SUCCEEDED **`.

- [ ] **Step 2: If tests fail, inspect only relevant failures**

Use the reported failure locations to fix compile or assertion errors in:

```text
JustAboutTime/TimerStore.swift
JustAboutTime/JustAboutTimeApp.swift
JustAboutTimeTests/TimerStoreTests.swift
```

- [ ] **Step 3: Re-run the same delegated test command**

Ask `@mechanical` to run the same `xcodebuild test` command again.

Expected result: command exits 0 and includes `** TEST SUCCEEDED **`.
