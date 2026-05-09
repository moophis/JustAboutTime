# Tabbed Settings Design

## Goal

Refactor JustAboutTime settings from one long grouped page into a native macOS tabbed settings window. Each settings section should live in its own SwiftUI page, matching the tabbed style shown in the reference image.

## Current State

`PreferencesView` currently owns all settings UI in one file:

1. Countdown preset duration controls.
2. Keyboard shortcut recorders.
3. Notification authorization/status controls.

The app presents this view from the SwiftUI `Settings` scene in `JustAboutTimeApp.swift`.

## Chosen Approach

Use a native SwiftUI `TabView` inside `PreferencesView`. This keeps the settings window aligned with macOS behavior and avoids custom tab chrome.

Tabs:

1. `General`: countdown preset durations.
2. `Shortcuts`: keyboard shortcut recorders and conflict note.
3. `Notifications`: notification authorization/status controls.

## Components

`PreferencesView` becomes a small shell that receives the existing `PreferencesStore` and `NotificationManager`, then renders the tab view.

New focused page views:

1. `GeneralPreferencesView`: owns preset duration rows and the duration binding helper.
2. `ShortcutPreferencesView`: owns shortcut recorder rows.
3. `NotificationPreferencesView`: owns notification status copy, action button, scene-phase refresh, and notification action handling.

Shared small views remain local to the settings implementation where useful:

1. `PreferencesGroup`: section title, content spacing, divider.
2. `PresetDurationRow`: text field, stepper, formatted duration label.

## Data Flow

`PreferencesStore` remains the single source of truth for preset durations and shortcut names. `GeneralPreferencesView` writes preset duration updates through `setPresetDurations(_:)`, preserving validation and persistence.

`ShortcutPreferencesView` continues to use `KeyboardShortcuts.Recorder` with the existing shortcut names.

`NotificationPreferencesView` observes `NotificationManager`, refreshes when settings become active, requests authorization for undecided status, opens System Settings for denied status, and refreshes for all other states.

## Layout

The settings window should use the native tab header produced by `TabView`. Each tab page should preserve the current visual language: left-aligned groups, semibold row labels, secondary explanatory text, and dividers between groups.

The window can keep the current minimum size unless native tab chrome needs a small adjustment for comfortable spacing.

## Error Handling

Preset edits keep the existing clamping behavior of 1 to 1,440 minutes. Invalid duration writes continue to be ignored through the existing `try?` behavior.

Notification errors continue to display through `notificationManager.preferencesErrorText`.

## Testing

Update source-inspection tests to verify:

1. `PreferencesView` uses `TabView`.
2. The three tabs are named `General`, `Shortcuts`, and `Notifications`.
3. The app still wires `PreferencesView(preferencesStore:notificationManager:)` from `Settings`.
4. Countdown, shortcut, and notification controls still exist in their factored views.

Run the project test suite through the mechanical verification workflow after implementation.

## Out Of Scope

1. Adding new settings.
2. Changing persisted preferences keys or shortcut registration.
3. Custom tab-bar drawing beyond native SwiftUI tab styling.
4. Changing menu bar behavior, timer behavior, history, or About window UI.
