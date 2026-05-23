# Status Indicators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace idle/completed and paused menu-bar indicators with explicit square and pause icons.

**Architecture:** Keep the existing `TimerStatusPresentation` pipeline. Expand `DotPhase` with explicit indicator cases, then let `StatusBarLabelImageRenderer` draw the selected indicator shape on the left or right. Idle and completed states share the calm `00:00` square plus hollow progress treatment.

**Tech Stack:** Swift, SwiftUI `MenuBarExtra`, AppKit `NSImage` drawing, Swift Testing.

---

### Task 1: Presentation Semantics

**Files:**
- Modify: `JustAboutTime/StatusBarPresenter.swift`
- Modify: `JustAboutTime/TimerStore.swift`
- Test: `JustAboutTimeTests/TimerStoreTests.swift`

- [ ] Return `.leadingSquare` for idle and completed countdown snapshots.
- [ ] Return `.leadingPause` for paused countdown/count-up snapshots.
- [ ] Keep warning and overdue running states alternating red dots.
- [ ] Change idle and completed countdown progress to a hollow, non-blinking outline.
- [ ] Update tests that expect idle or paused `.hidden` and completed red-dot alternation.

### Task 2: Renderer Shapes

**Files:**
- Modify: `JustAboutTime/JustAboutTimeApp.swift`

- [ ] Update the renderer to draw left indicators by shape: filled dot, solid square, or double pause bars.
- [ ] Preserve right red-dot rendering only for warning/overdue alternating states.
- [ ] Keep idle/completed state in primary text color by excluding square/hollow progress from semantic-red detection.
- [ ] Keep progress outline rendering but skip fill when `isFillVisible` is false.

### Task 3: Verification

**Files:**
- Test: `JustAboutTimeTests/TimerStoreTests.swift`

- [ ] Run the affected tests through the mechanical verifier.
- [ ] If compile errors identify missed enum cases, update all call sites without changing unrelated behavior.
