# Restart Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show every restart target inline under a disabled `Restart` section while a timer is active.

**Architecture:** Keep the feature inside `MenuBarView`, where menu composition already lives. Use existing `TimerStore.startCountdown(duration:)` and `TimerStore.startCountUp()` actions so selecting a restart target replaces the active session without new state.

**Tech Stack:** Swift, SwiftUI `MenuBarExtra`, macOS menu rendering.

---

### Task 1: Active Restart Section

**Files:**
- Modify: `JustAboutTime/MenuBarView.swift:41-64`

- [ ] **Step 1: Replace active restart button with section and restart options**

Change `activeMenu` so `Restart` is disabled text and all preset countdowns plus `Count Up` appear below it:

```swift
@ViewBuilder
private var activeMenu: some View {
    pauseButton

    restartSection

    Button("Finish") {
        timerStore.finish()
    }

    Divider()
    timerInfo
    StableTimerStatusView(timerStore: timerStore)

    Divider()
    aboutButton
    historyButton
    preferencesButton

    Divider()
    quitButton
}
```

- [ ] **Step 2: Add restart section helper**

Add this helper near the other menu helpers:

```swift
@ViewBuilder
private var restartSection: some View {
    Text("Restart")
        .disabled(true)

    ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { _, duration in
        Button(indentedCountdownTitle(for: duration)) {
            timerStore.startCountdown(duration: duration)
        }
    }

    Button("  Count Up") {
        timerStore.startCountUp()
    }
}
```

- [ ] **Step 3: Add indented countdown title helper**

Add this helper beside `countdownTitle(for:)`:

```swift
private func indentedCountdownTitle(for duration: TimeInterval) -> String {
    "  \(formattedDuration(duration)) Countdown"
}
```

- [ ] **Step 4: Verify build**

Run the app build command used by the repo. Expected: build succeeds.

- [ ] **Step 5: Manual UI check**

Start any timer, open the menu, and confirm the menu shows disabled `Restart`, indented preset countdown actions, indented `Count Up`, then `Finish`.
