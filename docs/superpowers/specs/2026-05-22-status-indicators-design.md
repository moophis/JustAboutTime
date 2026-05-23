# Status Indicators Design

## Goal

Update the menu-bar status label so idle, completed, and paused states stop using absent or blinking red dots.

## Behavior

- Initial idle app state shows `00:00` in primary menu-bar text color, a solid square indicator on the left, and a hollow progress outline with no fill.
- Completed countdown and manual countdown finish show the same solid square and hollow progress treatment.
- Paused countdown and paused count-up show a double-vertical-line pause icon on the left, colored the same as the current text.
- Running and warning states keep their existing dot/progress behavior.

## Implementation Shape

- Extend the status presentation model with explicit icon semantics instead of overloading dot visibility.
- Update the image renderer to draw dot, square, and pause-bar indicators from those semantics.
- Update timer store progress state so idle and completed countdown progress is hollow and non-blinking.
- Update presenter/store tests that assert idle, completed, and paused indicators.
