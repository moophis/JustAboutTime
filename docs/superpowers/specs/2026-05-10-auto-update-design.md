# Auto-Update via GitHub Releases API

**Status**: Draft
**Date**: 2026-05-10

## Overview

Add the ability to check for new versions of JustAboutTime by querying the GitHub Releases API. When a newer version is found, the user can download and install it directly from within the app with a full auto-update flow (download DMG → mount → replace app → relaunch).

## Requirements

- **Check source**: GitHub Releases API (`https://github.com/moophis/JustAboutTime/releases`)
- **Auto-check**: On app launch (silent; only notify if update found)
- **Manual check**: "Check for Updates…" button in the About window
- **Update found**: Show version in About window + present "Install & Restart" option
- **Install flow**: Download DMG → mount → rsync app to /Applications → relaunch
- **No external dependencies**: Uses `URLSession`, `Process`, shell scripting

## Architecture

### New file: `UpdateManager.swift`

`@MainActor ObservableObject` responsible for all update logic.

**Properties**:
- `latestVersion: String?` — latest release tag from GitHub (e.g. `"1.0.3"`)
- `downloadURL: URL?` — DMG asset download URL from the latest release
- `isChecking: Bool` — true while API request or download is in-flight
- `updateStatus: UpdateStatus` — drives About window UI state

**UpdateStatus enum**:
```swift
enum UpdateStatus {
    case unknown
    case checking
    case upToDate
    case updateAvailable(version: String, downloadURL: URL)
    case downloading(progress: Double)
    case downloadFailed(String)
    case checkFailed(String)
}
```

**Methods**:
- `checkForUpdates()` — manual trigger. Updates `updateStatus` throughout. Shows dialogs for results.
- `checkForUpdatesIfNeeded()` — launch trigger. Only sets `updateStatus = .updateAvailable` if newer found; silent otherwise.
- `downloadAndInstall(url:)` — downloads DMG, mounts with `hdiutil attach`, writes helper shell script, runs it (quits app → rsync → relaunch)
- `compareVersions(current:latest:)` — compares two semantic version strings (handles `v` prefix)

**Integration**:
- Instantiated in `JustAboutTimeApp.swift` as `@StateObject`
- Passed to About view via `.environmentObject()`
- `.onAppear` in App calls `updateManager.checkForUpdatesIfNeeded()` (with a short delay so UI is ready)

### Modified file: `AboutView.swift`

**Changes**:
- Accept `@EnvironmentObject var updateManager: UpdateManager`
- Below version text, add status text driven by `updateManager.updateStatus`:
  - `.unknown` → nothing
  - `.checking` → "Checking for updates…"
  - `.upToDate` → "JustAboutTime is up to date."
  - `.updateAvailable(let version, _)` → "New version \(version) available" + "Install & Restart" button
  - `.downloading(_)` → progress indicator + "Downloading…"
  - `.downloadFailed(_)` → error message + "Try Again" button
  - `.checkFailed(_)` → error message + "Try Again" button
- Add "Check for Updates…" button above the GitHub link
  - Disabled while `isChecking` is true
  - Calls `updateManager.checkForUpdates()`

### Modified file: `JustAboutTimeApp.swift`

**Changes**:
- Add `@StateObject private var updateManager = UpdateManager()`
- Pass `.environmentObject(updateManager)` to the About window scene
- In the App body (or a task), call `updateManager.checkForUpdatesIfNeeded()` on launch

## Data Flow

```
Launch → .task → UpdateManager.checkForUpdatesIfNeeded()
    → GET /repos/moophis/JustAboutTime/releases/latest
    → Parse tag_name, compare with CFBundleShortVersionString
    → If newer: updateStatus = .updateAvailable
    → Silent if up to date

Manual → Button in AboutView → UpdateManager.checkForUpdates()
    → Same API flow
    → Show dialog: "New version X.Y.Z" / "You're up to date"

Install → "Install & Restart" button → UpdateManager.downloadAndInstall(url:)
    → URLSession download to temp DMG
    → updateStatus = .downloading(progress)
    → hdiutil attach DMG
    → Write helper script:
        sleep 2
        rsync -a "/Volumes/JustAboutTime/JustAboutTime.app/" "/Applications/JustAboutTime.app/"
        hdiutil detach "/Volumes/JustAboutTime"
        open "/Applications/JustAboutTime.app"
    → Process.run(script)
    → NSApp.terminate(nil)
```

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Network unavailable | `checkFailed("Unable to check for updates. Check your internet connection.")` |
| No releases on GitHub | `checkFailed("No releases found.")` |
| No DMG asset in release | `checkFailed("No download available for this release.")` |
| DMG download fails | `downloadFailed("Download failed. Please try again.")` |
| hdiutil mount fails | `downloadFailed("Failed to mount disk image.")` |
| rsync fails | Script continues (old app remains); user is left to manually install |

## Version Comparison

- Current version: `Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String`
- Latest version: GitHub release `tag_name` (strip `v` prefix, e.g. `"v1.0.3"` → `"1.0.3"`)
- Compare: split by `.`, compare each component as integers
- Only consider semantic versions (ignore pre-release tags if tagged as such)

## Testing

- `UpdateManager` can be unit tested: mock URLSession, verify version comparison logic
- No UI tests needed for initial implementation

## Out of Scope

- Periodic background check (daily, etc.) — launch check is sufficient
- Delta updates / binary patches
- Prerelease channel support
- Update download resume on network interruption
