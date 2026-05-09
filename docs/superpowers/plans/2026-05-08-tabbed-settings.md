# Tabbed Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert JustAboutTime settings into a native macOS tabbed settings UI with `General`, `Shortcuts`, and `Notifications` pages.

**Architecture:** Keep `PreferencesView` as the settings scene entry point, but make it a `TabView` shell. Factor existing section bodies into focused private SwiftUI page views so data flow stays on the existing `PreferencesStore` and `NotificationManager` objects.

**Tech Stack:** SwiftUI, AppKit, KeyboardShortcuts, Swift Testing source-inspection tests, Xcode macOS app target.

---

## File Structure

- Modify `JustAboutTime/PreferencesView.swift`: replace the single long scrolling settings page with a native `TabView`; add `GeneralPreferencesView`, `ShortcutPreferencesView`, `NotificationPreferencesView`, and a shared `PreferencesPage` wrapper in the same file.
- Modify `JustAboutTimeTests/JustAboutTimeTests.swift`: update the existing preferences source-inspection test so it verifies the tabbed page split and preserved controls.
- No project file changes are needed because no new Swift source files are added.

No commits are included in this plan because repo instructions say not to commit unless the user explicitly requests it.

---

### Task 1: Refactor Settings Into Native Tabs

**Files:**
- Modify: `JustAboutTime/PreferencesView.swift:1-166`
- Test updates in Task 2.

- [ ] **Step 1: Replace `PreferencesView.swift` with tabbed page views**

Replace the full contents of `JustAboutTime/PreferencesView.swift` with:

```swift
import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        TabView {
            GeneralPreferencesView(preferencesStore: preferencesStore)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutPreferencesView(preferencesStore: preferencesStore)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            NotificationPreferencesView(notificationManager: notificationManager)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct GeneralPreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        PreferencesPage {
            PreferencesGroup(title: "COUNTDOWN") {
                ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { index, _ in
                    PresetDurationRow(
                        title: "Preset \(index + 1)",
                        durationInMinutes: durationBinding(for: index)
                    )
                }
            }
        }
    }

    private func durationBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                Int((preferencesStore.presetDurations[index] / 60).rounded(.down))
            },
            set: { newValue in
                let clampedMinutes = max(1, min(newValue, 1_440))
                let updatedDurations = preferencesStore.presetDurations.enumerated().map { currentIndex, currentDuration in
                    currentIndex == index ? TimeInterval(clampedMinutes * 60) : currentDuration
                }

                try? preferencesStore.setPresetDurations(updatedDurations)
            }
        )
    }
}

private struct ShortcutPreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        PreferencesPage {
            PreferencesGroup(title: "SHORTCUTS") {
                ForEach(preferencesStore.shortcutNames, id: \.rawValue) { name in
                    HStack(alignment: .firstTextBaseline) {
                        Text(AppShortcuts.title(for: name))
                            .font(.body.weight(.semibold))
                        Spacer()
                        KeyboardShortcuts.Recorder(for: name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Conflicting or invalid shortcuts are rejected automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NotificationPreferencesView: View {
    @ObservedObject var notificationManager: NotificationManager

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PreferencesPage {
            PreferencesGroup(title: "NOTIFICATIONS") {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alerts")
                            .font(.body.weight(.semibold))
                        Text(notificationManager.preferencesDetailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let errorText = notificationManager.preferencesErrorText {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(notificationManager.preferencesActionTitle) {
                        performNotificationAction()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            await notificationManager.refresh()
        }
    }

    private func performNotificationAction() {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            Task { await notificationManager.requestAuthorization() }
        case .denied:
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(settingsURL)
            }
        case .authorized, .provisional, .ephemeral, .unknown:
            Task { await notificationManager.refresh() }
        }
    }
}

private struct PreferencesPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreferencesGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PresetDurationRow: View {
    let title: String
    @Binding var durationInMinutes: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.body.weight(.semibold))
            Spacer()
            TextField("Minutes", value: $durationInMinutes, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Stepper("", value: $durationInMinutes, in: 1...1_440)
                .labelsHidden()
            Text(durationLabel)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationLabel: String {
        let hours = durationInMinutes / 60
        let minutes = durationInMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}
```

- [ ] **Step 2: Review preserved behavior**

Confirm in the edited file that:

```text
GeneralPreferencesView uses preferencesStore.presetDurations and setPresetDurations(_:).
ShortcutPreferencesView still uses KeyboardShortcuts.Recorder(for: name).
NotificationPreferencesView still uses notificationManager.preferencesActionTitle and performNotificationAction().
```

---

### Task 2: Update Preferences Source-Inspection Test

**Files:**
- Modify: `JustAboutTimeTests/JustAboutTimeTests.swift:276-289`

- [ ] **Step 1: Replace the old grouped-settings test**

Replace `preferencesViewIncludesGroupedPresetShortcutAndNotificationSections` in `JustAboutTimeTests/JustAboutTimeTests.swift` with:

```swift
@Test func preferencesViewIncludesTabbedPresetShortcutAndNotificationPages() throws {
    let source = try source(at: projectFilePath("JustAboutTime/PreferencesView.swift"))

    #expect(source.contains("TabView"))
    #expect(source.contains("GeneralPreferencesView(preferencesStore: preferencesStore)"))
    #expect(source.contains("ShortcutPreferencesView(preferencesStore: preferencesStore)"))
    #expect(source.contains("NotificationPreferencesView(notificationManager: notificationManager)"))
    #expect(source.contains("Label(\"General\", systemImage: \"gearshape\")"))
    #expect(source.contains("Label(\"Shortcuts\", systemImage: \"keyboard\")"))
    #expect(source.contains("Label(\"Notifications\", systemImage: \"bell\")"))
    #expect(source.contains("PreferencesGroup(title: \"COUNTDOWN\")"))
    #expect(source.contains("PreferencesGroup(title: \"SHORTCUTS\")"))
    #expect(source.contains("KeyboardShortcuts.Recorder(for: name)"))
    #expect(source.contains("Conflicting or invalid shortcuts are rejected automatically."))
    #expect(source.contains("PreferencesGroup(title: \"NOTIFICATIONS\")"))
    #expect(source.contains("Divider()"))
    #expect(source.contains("@Environment(\\.scenePhase) private var scenePhase"))
    #expect(source.contains(".task(id: scenePhase)"))
    #expect(source.contains("if let settingsURL = URL("))
    #expect(source.contains("Notifications-Settings.extension\")!)") == false)
}
```

- [ ] **Step 2: Confirm app scene wiring test remains valid**

Keep `appEntrypointUsesMenuBarExtraWithoutWindowGroup` unchanged. It should still contain this expectation:

```swift
#expect(appSource.contains("PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)"))
```

---

### Task 3: Verify With Mechanical Subagent

**Files:**
- No source edits.

- [ ] **Step 1: Ask `@mechanical` to run the project tests**

Per repo instructions, do not run build/test verification directly. Ask `@mechanical` to run:

```bash
xcodebuild test -scheme JustAboutTime -destination 'platform=macOS' -derivedDataPath build/DerivedData
```

Expected result includes:

```text
** TEST SUCCEEDED **
```

- [ ] **Step 2: If verification fails, diagnose before changing code**

Use `systematic-debugging` before any fix if the failure is unexpected. Keep fixes scoped to `PreferencesView.swift` and `JustAboutTimeTests.swift` unless the failure identifies a directly related file.

---

## Self-Review

- Spec coverage: Task 1 adds native `TabView`, creates `General`, `Shortcuts`, and `Notifications` pages, keeps countdown presets in `General`, preserves notification refresh/action handling, and keeps existing preference persistence paths.
- Test coverage: Task 2 verifies the new tab shell, page view calls, tab names/icons, preserved controls, and safe notification settings URL handling.
- Placeholder scan: no unfinished placeholder markers remain.
- Scope check: one focused UI refactor; no changes to persisted preferences, shortcuts, timer behavior, history, or About UI.
- Type consistency: `PreferencesStore`, `NotificationManager`, `KeyboardShortcuts.Recorder`, `Binding<Int>`, and `scenePhase` names match existing project code.
