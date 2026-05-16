# Restart Menu Design

## Goal

When a timer is active, the menu should always show every restart target directly under a disabled `Restart` section label. Each restart target is tappable and visually indented.

## Menu Behavior

The active timer menu should keep `Pause` or `Resume` first, then show:

```text
Restart
  5m Countdown
  25m Countdown
  45m Countdown
  Count Up
```

`Restart` is a section label, not an action. It should not restart the current timer when clicked. The countdown entries come from `PreferencesStore.presetDurations`, so custom presets appear automatically. `Count Up` is always included.

Selecting a countdown entry starts a fresh countdown for that duration, replacing the current session. Selecting `Count Up` starts a fresh count-up, replacing the current session.

## Implementation Notes

Keep the change in `MenuBarView`. Reuse the existing formatting helper for countdown durations. Add a small helper for indented labels if needed, rather than introducing new menu model types.

## Testing

Verify the app builds and the active menu shows the disabled restart header plus all indented restart options. Existing timer store behavior already covers starting countdown and count-up sessions.
