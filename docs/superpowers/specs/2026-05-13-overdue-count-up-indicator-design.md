# Overdue Count-Up Indicator Design

## Goal

When a countdown completes and the app continues counting up, make the overdue state more obvious in the menu bar. The timer text should be red, and the progress bar should stay full while its inner solid bar blinks.

## Current Behavior

`TimerStore` marks post-countdown count-up as overdue with `isCountingUpAfterCountdown`. `StatusBarPresenter` uses that flag to alternate red status dots. `TimerStore.countdownProgress` returns a full warning progress bar for this state, and `StatusBarLabelImageRenderer` draws the outline and filled bar in red.

The current progress model only knows whether the progress is a warning. It cannot distinguish a normal warning countdown from a due timer that is counting up.

## Approach

Extend `CountdownProgressPresentation` with an `isBlinking` flag and an `isFillVisible` frame value. Normal countdown progress sets `isBlinking` to `false` and keeps `isFillVisible` true. Completed countdown and overdue count-up progress set `isBlinking` to `true` only when the app is showing the due state, and alternate `isFillVisible` once per tick.

Thread the current `animationStep` into progress generation so the renderer can blink the inner fill in sync with the existing one-second tick without inferring blink state from dot position. The progress outline remains visible on every frame. The inner filled bar is drawn only when `isFillVisible` is true.

Extend status text rendering so semantic red applies to overdue timer text, not only to dots and progress. Keep non-overdue count-up, non-warning countdown, and idle text unchanged.

## Components

- `CountdownProgressPresentation`: add `isBlinking` and `isFillVisible`.
- `TimerStore`: set blinking for completed/due presentations and keep normal countdown warnings non-blinking.
- `StatusBarLabelImageRenderer`: draw the progress outline every frame, skip only the inner fill on the blink-off phase, and render overdue timer text red.

## Tests

Add or update tests to cover:

- Overdue count-up progress is full, warning-red, and blinking.
- Normal warning countdown progress is red but not blinking.
- Completed countdown progress keeps the existing full warning state and blinks while the due indicator is visible.
