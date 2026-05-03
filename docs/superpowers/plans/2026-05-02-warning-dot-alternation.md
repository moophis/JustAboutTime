# Warning Dot Alternation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the countdown warning/completed status bar dot alternate left/right in red once per second.

**Architecture:** Keep timer-display state in `StatusBarPresenter` and rendering in `StatusBarLabelImageRenderer`. `TimerStore` computes whether an active countdown is in the warning window because it has both remaining time and original duration.

**Tech Stack:** Swift, SwiftUI/AppKit `NSImage` rendering, Swift Testing, Xcode macOS app target.

---

## File Structure

- Modify `JustAboutTime/StatusBarPresenter.swift`: add warning state to countdown snapshots, add red trailing dot phase, and choose red alternating dots for warning/completed countdowns.
- Modify `JustAboutTime/TimerStore.swift`: pass warning state into countdown snapshots and share the existing 10% threshold with progress presentation.
- Modify `JustAboutTime/JustAboutTimeApp.swift`: draw red trailing dots as well as red leading dots.
- Modify `JustAboutTimeTests/TimerStoreTests.swift`: update snapshot call sites and add coverage for warning/completed red alternation.

No commits are included in this plan because repo instructions say not to commit unless the user explicitly requests it.

---

### Task 1: Update Presenter State And Dot Logic

**Files:**
- Modify: `JustAboutTime/StatusBarPresenter.swift:3-51`
- Test updates in Task 4.

- [ ] **Step 1: Add warning state and red trailing phase**

Replace the top model declarations in `JustAboutTime/StatusBarPresenter.swift` with:

```swift
enum TimerStatusSnapshot: Equatable {
    case idle
    case countdown(remaining: TimeInterval, isRunning: Bool, isWarning: Bool)
    case countUp(elapsed: TimeInterval, isRunning: Bool)
    case countdownCompleted
}

enum DotPhase: Equatable {
    case hidden
    case leading
    case trailing
    case leadingRed
    case trailingRed
}
```

- [ ] **Step 2: Route countdown warning/completed states through red alternation**

Replace `StatusBarPresenter.presentation(for:animationStep:)` and the helper methods below `format(_:)` with:

```swift
func presentation(for snapshot: TimerStatusSnapshot, animationStep: Int) -> TimerStatusPresentation {
    switch snapshot {
    case .idle:
        return TimerStatusPresentation(text: format(0), dotPhase: .hidden)
    case let .countdown(remaining, isRunning, isWarning):
        return TimerStatusPresentation(
            text: format(remaining),
            dotPhase: countdownDotPhase(isRunning: isRunning, isWarning: isWarning, animationStep: animationStep)
        )
    case let .countUp(elapsed, isRunning):
        return TimerStatusPresentation(text: format(elapsed), dotPhase: dotPhase(isRunning: isRunning, animationStep: animationStep))
    case .countdownCompleted:
        return TimerStatusPresentation(text: "00:00", dotPhase: redAlternatingDotPhase(animationStep: animationStep))
    }
}

private func format(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval.rounded(.down)))
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60

    return String(format: "%02d:%02d", minutes, seconds)
}

private func countdownDotPhase(isRunning: Bool, isWarning: Bool, animationStep: Int) -> DotPhase {
    guard isRunning else {
        return .hidden
    }

    guard isWarning else {
        return dotPhase(isRunning: isRunning, animationStep: animationStep)
    }

    return redAlternatingDotPhase(animationStep: animationStep)
}

private func dotPhase(isRunning: Bool, animationStep: Int) -> DotPhase {
    guard isRunning else {
        return .hidden
    }

    return animationStep.isMultiple(of: 2) ? .leading : .hidden
}

private func redAlternatingDotPhase(animationStep: Int) -> DotPhase {
    animationStep.isMultiple(of: 2) ? .leadingRed : .trailingRed
}
```

- [ ] **Step 3: Confirm count-up behavior is unchanged in code review**

Inspect `case let .countUp(elapsed, isRunning)` and confirm it still calls `dotPhase(isRunning:animationStep:)`, so count-up timers still blink leading/hidden rather than alternating red.

---

### Task 2: Pass Warning State From TimerStore

**Files:**
- Modify: `JustAboutTime/TimerStore.swift:209-230`
- Test updates in Task 4.

- [ ] **Step 1: Reuse the warning threshold for progress**

In `countdownProgress(for:referenceTime:)`, replace the `CountdownProgressPresentation` return block with:

```swift
return CountdownProgressPresentation(
    fractionComplete: min(1, max(0, remaining / duration)),
    isWarning: isCountdownWarning(remaining: remaining, duration: duration)
)
```

- [ ] **Step 2: Add the private threshold helper**

Add this helper immediately after `countdownProgress(for:referenceTime:)`:

```swift
private func isCountdownWarning(remaining: TimeInterval, duration: TimeInterval) -> Bool {
    remaining <= duration * 0.1
}
```

- [ ] **Step 3: Include warning state in countdown snapshots**

In `snapshot(for:referenceTime:)`, replace the `.runningCountdown, .pausedCountdown` case body with:

```swift
let remaining = session.remainingTime(at: referenceTime) ?? 0
let duration = session.originalDuration ?? 0
return .countdown(
    remaining: remaining,
    isRunning: session.isRunning,
    isWarning: duration > 0 && isCountdownWarning(remaining: remaining, duration: duration)
)
```

The full case should read:

```swift
case .runningCountdown, .pausedCountdown:
    let remaining = session.remainingTime(at: referenceTime) ?? 0
    let duration = session.originalDuration ?? 0
    return .countdown(
        remaining: remaining,
        isRunning: session.isRunning,
        isWarning: duration > 0 && isCountdownWarning(remaining: remaining, duration: duration)
    )
```

---

### Task 3: Render Red Trailing Dot

**Files:**
- Modify: `JustAboutTime/JustAboutTimeApp.swift:92-116`
- Test updates in Task 4.

- [ ] **Step 1: Add local red-state booleans before drawing dots**

In `StatusBarLabelImageRenderer.image(presentation:countdownProgress:)`, after `textOrigin` is created, add:

```swift
let isLeadingRed = presentation.dotPhase == .leadingRed
let isTrailingRed = presentation.dotPhase == .trailingRed
```

- [ ] **Step 2: Update leading dot rendering**

Replace the leading `drawDot` call with:

```swift
drawDot(
    isVisible: presentation.dotPhase == .leading || isLeadingRed,
    color: isLeadingRed ? .systemRed : .labelColor,
    in: NSRect(
        x: rowOriginX,
        y: progressHeight + (textRowSize.height - Layout.dotDiameter) / 2,
        width: Layout.dotDiameter,
        height: Layout.dotDiameter
    )
)
```

- [ ] **Step 3: Update trailing dot rendering**

Replace the trailing `drawDot` call with:

```swift
drawDot(
    isVisible: presentation.dotPhase == .trailing || isTrailingRed,
    color: isTrailingRed ? .systemRed : .labelColor,
    in: NSRect(
        x: textOrigin.x + textSize.width + Layout.dotSpacing,
        y: progressHeight + (textRowSize.height - Layout.dotDiameter) / 2,
        width: Layout.dotDiameter,
        height: Layout.dotDiameter
    )
)
```

---

### Task 4: Update And Add Tests

**Files:**
- Modify: `JustAboutTimeTests/TimerStoreTests.swift:18-56`
- Modify: `JustAboutTimeTests/TimerStoreTests.swift:86-110`
- Modify: `JustAboutTimeTests/TimerStoreTests.swift:205-227`

- [ ] **Step 1: Update existing countdown snapshot call sites**

Replace existing direct `TimerStatusSnapshot.countdown` construction in tests with the new signature. For example, update `statusBarPresenterFormatsRunningCountdownSnapshot` to:

```swift
@Test func statusBarPresenterFormatsRunningCountdownSnapshot() {
    let presenter = StatusBarPresenter()

    let presentation = presenter.presentation(
        for: .countdown(remaining: 125, isRunning: true, isWarning: false),
        animationStep: 1
    )

    #expect(presentation.text == "02:05")
    #expect(presentation.dotPhase == .hidden)
}
```

- [ ] **Step 2: Add presenter coverage for warning countdown alternation**

Add this test after `statusBarPresenterOnlyAnimatesDotsWhileRunning`:

```swift
@Test func statusBarPresenterAlternatesWarningCountdownDotsInRed() {
    let presenter = StatusBarPresenter()

    let leading = presenter.presentation(
        for: .countdown(remaining: 10, isRunning: true, isWarning: true),
        animationStep: 0
    )
    let trailing = presenter.presentation(
        for: .countdown(remaining: 9, isRunning: true, isWarning: true),
        animationStep: 1
    )
    let paused = presenter.presentation(
        for: .countdown(remaining: 8, isRunning: false, isWarning: true),
        animationStep: 2
    )

    #expect(leading.text == "00:10")
    #expect(leading.dotPhase == .leadingRed)
    #expect(trailing.text == "00:09")
    #expect(trailing.dotPhase == .trailingRed)
    #expect(paused.dotPhase == .hidden)
}
```

- [ ] **Step 3: Add presenter coverage for completed countdown alternation**

Add this test after the warning presenter test:

```swift
@Test func statusBarPresenterAlternatesCompletedCountdownDotsInRed() {
    let presenter = StatusBarPresenter()

    let leading = presenter.presentation(for: .countdownCompleted, animationStep: 0)
    let trailing = presenter.presentation(for: .countdownCompleted, animationStep: 1)

    #expect(leading.text == "00:00")
    #expect(leading.dotPhase == .leadingRed)
    #expect(trailing.text == "00:00")
    #expect(trailing.dotPhase == .trailingRed)
}
```

- [ ] **Step 4: Add store coverage for warning threshold and tick alternation**

Add this test near `countdownProgressTracksRemainingFractionAndWarningWindow`:

```swift
@MainActor
@Test func countdownWarningDotAlternatesWhileRunning() async {
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
    let sleeper = TestSleeper()
    let store = TimerStore(
        historyStore: makeIsolatedHistoryStore(),
        now: { clock.now },
        sleep: sleeper.sleep(for:)
    )

    store.startCountdown(duration: 100)

    clock.advance(by: 90)
    await sleeper.resumeOnce()
    while store.statusPresentation.text != "00:10" {
        await Task.yield()
    }

    #expect(store.statusPresentation.dotPhase == .trailingRed)

    clock.advance(by: 1)
    await sleeper.resumeOnce()
    while store.statusPresentation.text != "00:09" {
        await Task.yield()
    }

    #expect(store.statusPresentation.dotPhase == .leadingRed)
}
```

- [ ] **Step 5: Strengthen completed countdown store coverage**

In `timerStoreSurfacesCountdownCompletionEvents`, append these expectations after `#expect(store.activeSession == nil)`:

```swift
#expect(store.statusPresentation.text == "00:00")
#expect(store.statusPresentation.dotPhase == .trailingRed)

clock.advance(by: 1)
await sleeper.resumeOnce()
while store.statusPresentation.dotPhase == .trailingRed {
    await Task.yield()
}

#expect(store.statusPresentation.text == "00:00")
#expect(store.statusPresentation.dotPhase == .leadingRed)
```

---

### Task 5: Verify With Mechanical Subagent

**Files:**
- No source edits.

- [ ] **Step 1: Ask `@mechanical` to run the focused test target**

Per repo instructions, do not run build/test verification directly. Ask `@mechanical` to run:

```bash
xcodebuild test -scheme JustAboutTime -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

Expected result includes:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: If tests fail, inspect the failure before changing code**

Use `systematic-debugging` before any fix if the failure is unexpected. Keep fixes scoped to the files listed in this plan unless the failure identifies a directly related file.

---

## Self-Review

- Spec coverage: warning countdown alternates left/right in red, completed countdown alternates left/right in red, completed text remains `00:00`, and non-warning behavior remains unchanged.
- Placeholder scan: no unfinished placeholder markers remain.
- Type consistency: `TimerStatusSnapshot.countdown` uses `remaining`, `isRunning`, and `isWarning` consistently across presenter, store, and tests; `DotPhase.trailingRed` is consumed by renderer.
