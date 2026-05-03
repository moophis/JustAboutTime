# Warning Dot Alternation Design

## Goal

When a countdown enters the warning window, the status bar dot alternates between the left and right side of the timer text once per second. The dot stays red during this warning animation and continues alternating in red after the countdown completes.

## Current Behavior

`StatusBarPresenter` maps timer snapshots and animation steps to `TimerStatusPresentation`. Running timers currently blink the dot on and off. Completed countdowns show `00:00` and blink a red leading dot. `StatusBarLabelImageRenderer` draws a red dot only for `.leadingRed`; trailing dots are label-colored.

`TimerStore` already advances `animationStep` once per tick while timers are running and while the completed countdown indicator is showing.

## Approach

Use the existing presentation boundary. Add a red trailing dot phase and keep color and position decisions in `StatusBarPresenter`.

`StatusBarPresenter` will:

- Preserve existing idle and non-warning timer behavior.
- Treat countdown snapshots with `isRunning == true` and remaining time in the warning window as a red alternating state.
- Alternate warning/completed dots by animation step: even steps leading red, odd steps trailing red.
- Continue showing completed countdown text as `00:00`.

`StatusBarLabelImageRenderer` will:

- Draw leading dots for `.leading` and `.leadingRed`.
- Draw trailing dots for `.trailing` and `.trailingRed`.
- Use red for both red phases.

## Warning Threshold

Match the existing progress warning threshold: remaining time at or below 10% of the countdown duration. Add an `isWarning` flag to `TimerStatusSnapshot.countdown`; `TimerStore` computes it from the session duration and remaining time, and `StatusBarPresenter` uses it to choose red alternating dots.

## Tests

Add presenter/store coverage for:

- Countdown warning state alternates `.leadingRed` then `.trailingRed` on consecutive ticks.
- Completed countdown alternates `.leadingRed` then `.trailingRed` and keeps `00:00`.
- Non-warning countdown behavior remains unchanged.
