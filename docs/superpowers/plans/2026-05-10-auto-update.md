# Auto-Update via GitHub Releases API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add in-app update checking via GitHub Releases API with full auto-update flow (download DMG → mount → replace app → relaunch).

**Architecture:** New `UpdateManager` ObservableObject handles all update logic (API query, version comparison, download, install). Injected from App into AboutView via environmentObject. Launch check is silent; manual check shows dialog results.

**Tech Stack:** SwiftUI, AppKit, URLSession, Process (hdiutil/rsync shell script), Swift Testing

---

### Task 1: Create `UpdateManager.swift`

**Files:**
- Create: `JustAboutTime/UpdateManager.swift`

- [ ] **Step 1: Create the file with full implementation**

```swift
import AppKit
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    enum Status: Equatable {
        case unknown
        case checking
        case upToDate
        case updateAvailable(version: String, downloadURL: URL)
        case downloading(progress: Double)
        case downloadFailed(String)
        case checkFailed(String)
    }

    @Published var status: Status = .unknown

    private let owner = "moophis"
    private let repo = "JustAboutTime"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private static let githubAPIBase = "https://api.github.com"

    var isBusy: Bool {
        if case .checking = status { return true }
        if case .downloading = status { return true }
        return false
    }

    private var currentVersion: String {
        Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.1"
    }

    // MARK: - Public API

    func checkForUpdatesIfNeeded() {
        guard !isBusy else { return }
        Task {
            await performCheck(silent: true)
        }
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        Task {
            await performCheck(silent: false)
        }
    }

    func downloadAndInstall(url: URL) {
        guard !isBusy else { return }
        Task {
            await performDownloadAndInstall(from: url)
        }
    }

    // MARK: - Version Check

    private func performCheck(silent: Bool) async {
        status = .checking

        let url = URL(string: "\(Self.githubAPIBase)/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            guard httpResponse?.statusCode == 200 else {
                let code = httpResponse?.statusCode ?? 0
                if code == 403 {
                    status = .checkFailed("GitHub rate limit exceeded. Try again later.")
                } else {
                    status = .checkFailed("Unable to check for updates (HTTP \(code)).")
                }
                if !silent {
                    showAlert(message: statusMessage)
                }
                return
            }
            data = responseData
        } catch {
            let message = error.localizedDescription.contains("offline") || error.localizedDescription.contains("connection")
                ? "Unable to check for updates. Check your internet connection."
                : "Unable to check for updates: \(error.localizedDescription)"
            status = .checkFailed(message)
            if !silent {
                showAlert(message: message)
            }
            return
        }

        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            status = .checkFailed("Unable to parse release information.")
            if !silent {
                showAlert(message: statusMessage)
            }
            return
        }

        let latestVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard isVersion(latestVersion, newerThan: currentVersion) else {
            status = .upToDate
            if !silent {
                showAlert(message: "JustAboutTime is up to date.")
            }
            return
        }

        guard let dmgAsset = release.assets.first(where: { asset in
            asset.contentType.contains("diskimage") ||
            asset.name.hasSuffix(".dmg") ||
            asset.browserDownloadURL.pathExtension == "dmg"
        }) else {
            status = .checkFailed("No download available for this release.")
            if !silent {
                showAlert(message: statusMessage)
            }
            return
        }

        status = .updateAvailable(version: latestVersion, downloadURL: dmgAsset.browserDownloadURL)

        if !silent {
            let alert = NSAlert()
            alert.messageText = "New Version Available"
            alert.informativeText = "JustAboutTime \(latestVersion) is available. You have \(currentVersion). Would you like to download and install it?"
            alert.addButton(withTitle: "Install & Restart")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                downloadAndInstall(url: dmgAsset.browserDownloadURL)
            }
        }
    }

    // MARK: - Download & Install

    private func performDownloadAndInstall(from url: URL) async {
        status = .downloading(progress: 0)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustAboutTime-Update-\(UUID().uuidString)")
        let dmgPath = tempDir.appendingPathComponent("update.dmg")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            status = .downloadFailed("Failed to create temporary directory.")
            return
        }

        let dmgURL: URL
        do {
            dmgURL = try await downloadFile(from: url, to: dmgPath) { [weak self] progress in
                Task { @MainActor in
                    self?.status = .downloading(progress: progress)
                }
            }
        } catch {
            status = .downloadFailed("Download failed. Please try again.")
            return
        }

        guard let mountPoint = mountDMG(at: dmgURL) else {
            status = .downloadFailed("Failed to mount disk image.")
            return
        }

        let appName = (Bundle.main.bundleURL.lastPathComponent as NSString).deletingPathExtension
        let mountedAppPath = "\(mountPoint)/\(appName).app"
        let targetAppPath = Bundle.main.bundlePath

        guard FileManager.default.fileExists(atPath: mountedAppPath) else {
            ejectDMG(at: mountPoint)
            status = .downloadFailed("App not found in disk image.")
            return
        }

        let scriptPath = tempDir.appendingPathComponent("install.sh")

        let script = """
        #!/bin/bash
        sleep 2
        rsync -a --delete "\(mountedAppPath)/" "\(targetAppPath)/"
        hdiutil detach "\(mountPoint)" -force 2>/dev/null
        rm -rf "\(tempDir.path)"
        open "\(targetAppPath)"
        """

        do {
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            ejectDMG(at: mountPoint)
            status = .downloadFailed("Failed to prepare installer.")
            return
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptPath.path
            )
        } catch {
            ejectDMG(at: mountPoint)
            status = .downloadFailed("Failed to prepare installer.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            ejectDMG(at: mountPoint)
            status = .downloadFailed("Failed to start installer.")
            return
        }

        // Brief delay so the process can start, then quit this app
        try? await Task.sleep(nanoseconds: 500_000_000)
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func downloadFile(
        from url: URL,
        to destination: URL,
        progressHandler: @MainActor @escaping (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await session.bytes(from: url)
        let expectedLength = Double(response.expectedContentLength)
        let fileHandle = try FileHandle(forWritingTo: destination)
        var receivedBytes = 0

        for try await chunk in bytes {
            try fileHandle.write(contentsOf: chunk)
            receivedBytes += chunk.count
            if expectedLength > 0 {
                await progressHandler(Double(receivedBytes) / expectedLength)
            }
        }
        try fileHandle.close()
        return destination
    }

    private func mountDMG(at url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", url.path, "-nobrowse", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else {
            return nil
        }

        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }
        return nil
    }

    private func ejectDMG(at mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-force"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    var statusMessage: String {
        switch status {
        case .unknown, .checking, .upToDate, .updateAvailable, .downloading:
            return ""
        case .checkFailed(let message), .downloadFailed(let message):
            return message
        }
    }

    // MARK: - Version Comparison

    func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let latestParts = sanitizedVersionComponents(latest)
        let currentParts = sanitizedVersionComponents(current)

        let maxCount = max(latestParts.count, currentParts.count)
        for i in 0 ..< maxCount {
            let latestComponent = i < latestParts.count ? latestParts[i] : 0
            let currentComponent = i < currentParts.count ? currentParts[i] : 0
            if latestComponent > currentComponent { return true }
            if latestComponent < currentComponent { return false }
        }
        return false
    }

    private func sanitizedVersionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .components(separatedBy: ".")
            .compactMap { component in
                let digits = component.prefix(while: { $0.isNumber })
                return Int(digits)
            }
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let contentType: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case browserDownloadURL = "browser_download_url"
    }
}
```

### Task 2: Modify `AboutView.swift`

**Files:**
- Modify: `JustAboutTime/AboutView.swift`

- [ ] **Step 1: Replace the entire file with the updated version**

```swift
import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var updateManager: UpdateManager

    private let githubURL = URL(string: "https://github.com/moophis/JustAboutTime")!

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 64, height: 64)

            Text("JustAboutTime")
                .font(.title3.bold())

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            updateSection
                .font(.callout)

            Link("GitHub", destination: githubURL)
                .font(.callout)
        }
        .padding(24)
        .frame(width: 260)
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updateManager.status {
        case .unknown:
            Button("Check for Updates\u{2026}") {
                updateManager.checkForUpdates()
            }
            .disabled(updateManager.isBusy)

        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("Checking for updates\u{2026}")
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("JustAboutTime is up to date.")
                    .foregroundStyle(.secondary)
            }
            Button("Check for Updates\u{2026}") {
                updateManager.checkForUpdates()
            }
            .disabled(updateManager.isBusy)

        case .updateAvailable(let version, let downloadURL):
            VStack(spacing: 8) {
                Text("New version \(version) available")
                    .foregroundStyle(.secondary)
                Button("Install & Restart") {
                    updateManager.downloadAndInstall(url: downloadURL)
                }
                .disabled(updateManager.isBusy)
            }

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress) {
                    Text("Downloading\u{2026}")
                }
                .frame(width: 180)
                Text("\(Int(progress * 100))%")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

        case .downloadFailed(let message):
            VStack(spacing: 6) {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    updateManager.checkForUpdates()
                }
                .disabled(updateManager.isBusy)
            }

        case .checkFailed(let message):
            VStack(spacing: 6) {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    updateManager.checkForUpdates()
                }
                .disabled(updateManager.isBusy)
            }
        }
    }

    private var appVersion: String {
        Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.1"
    }
}
```

### Task 3: Modify `JustAboutTimeApp.swift`

**Files:**
- Modify: `JustAboutTime/JustAboutTimeApp.swift`

- [ ] **Step 1: Add UpdateManager to the App**

Replace the existing content with:

```swift
import AppKit
import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var historyStore: HistoryStore
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var preferencesStore = PreferencesStore()
    @StateObject private var timerStore: TimerStore
    @StateObject private var shortcutManager: ShortcutManager
    @StateObject private var updateManager = UpdateManager()

    init() {
        let historyStore = HistoryStore()
        let notificationManager = NotificationManager()
        let preferencesStore = PreferencesStore()
        let timerStore = TimerStore(historyStore: historyStore, notificationManager: notificationManager, preferencesStore: preferencesStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _timerStore = StateObject(wrappedValue: timerStore)
        _shortcutManager = StateObject(wrappedValue: ShortcutManager(timerStore: timerStore))

        Task { @MainActor [timerStore, preferencesStore, updateManager] in
            Self.setupSystemObservers(timerStore: timerStore, preferencesStore: preferencesStore)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            updateManager.checkForUpdatesIfNeeded()
        }
    }

    @MainActor
    private static func setupSystemObservers(timerStore: TimerStore, preferencesStore: PreferencesStore) {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak timerStore, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerStore, let preferencesStore, preferencesStore.pauseOnScreenLocked else { return }
                timerStore.systemPause()
            }
        }

        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak timerStore, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerStore, let preferencesStore, preferencesStore.resumeOnRelogin else { return }
                timerStore.systemResume()
            }
        }

        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak timerStore, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerStore, let preferencesStore, preferencesStore.pauseOnScreenLocked else { return }
                timerStore.systemPause()
            }
        }

        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak timerStore, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerStore, let preferencesStore, preferencesStore.resumeOnRelogin else { return }
                timerStore.systemResume()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerStore: timerStore, preferencesStore: preferencesStore)
        } label: {
            StatusBarLabelView(
                presentation: timerStore.statusPresentation,
                countdownProgress: timerStore.countdownProgress
            )
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: HistoryWindow.id) {
            HistoryView(historyStore: historyStore, timerStore: timerStore)
        }

        Window("About JustAboutTime", id: AboutWindow.id) {
            AboutView()
                .environmentObject(updateManager)
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)
        }
    }
}

enum HistoryWindow {
    static let id = "history"
}

enum AboutWindow {
    static let id = "about"
}

private struct StatusBarLabelView: View {
    let presentation: TimerStatusPresentation
    let countdownProgress: CountdownProgressPresentation?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: StatusBarLabelImageRenderer.image(
            presentation: presentation,
            countdownProgress: countdownProgress,
            colorScheme: colorScheme
        ))
            .accessibilityLabel(presentation.text)
    }
}

private enum StatusBarLabelImageRenderer {
    private enum Layout {
        static let dotDiameter = 6.0
        static let dotSpacing = 4.0
        static let progressHeight = 5.0
        static let progressSpacing = 1.0
        static let progressInset = 1.0
    }

    static func image(
        presentation: TimerStatusPresentation,
        countdownProgress: CountdownProgressPresentation?,
        colorScheme: ColorScheme
    ) -> NSImage {
        let needsOriginalColor = usesSemanticRed(presentation: presentation, countdownProgress: countdownProgress)
        let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor
        let attributes = textAttributes(foregroundColor: primaryColor)
        let textSize = presentation.text.size(withAttributes: attributes)
        let textRowSize = rowSize(textSize: textSize)
        let progressHeight = countdownProgress == nil ? 0 : Layout.progressSpacing + Layout.progressHeight
        let progressWidth = max(34, textRowSize.width)
        let imageSize = NSSize(width: max(textRowSize.width, progressWidth), height: textRowSize.height + progressHeight)
        let image = NSImage(size: imageSize)
        image.isTemplate = !needsOriginalColor

        image.lockFocus()
        defer { image.unlockFocus() }

        let rowOriginX = (imageSize.width - textRowSize.width) / 2
        let textOrigin = NSPoint(x: rowOriginX + Layout.dotDiameter + Layout.dotSpacing, y: progressHeight)
        let isLeadingRed = presentation.dotPhase == .leadingRed
        let isTrailingRed = presentation.dotPhase == .trailingRed

        drawDot(
            isVisible: presentation.dotPhase == .leading || isLeadingRed,
            color: isLeadingRed ? .systemRed : primaryColor,
            in: NSRect(
                x: rowOriginX,
                y: progressHeight + (textRowSize.height - Layout.dotDiameter) / 2,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )

        presentation.text.draw(at: textOrigin, withAttributes: attributes)

        drawDot(
            isVisible: presentation.dotPhase == .trailing || isTrailingRed,
            color: isTrailingRed ? .systemRed : primaryColor,
            in: NSRect(
                x: textOrigin.x + textSize.width + Layout.dotSpacing,
                y: progressHeight + (textRowSize.height - Layout.dotDiameter) / 2,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )

        if let countdownProgress {
            drawProgress(
                countdownProgress,
                primaryColor: primaryColor,
                in: NSRect(x: 0, y: 0, width: progressWidth, height: Layout.progressHeight)
            )
        }

        return image
    }

    private static func rowSize(textSize: NSSize) -> NSSize {
        NSSize(
            width: Layout.dotDiameter * 2 + Layout.dotSpacing * 2 + textSize.width,
            height: max(Layout.dotDiameter, textSize.height)
        )
    }

    private static func usesSemanticRed(
        presentation: TimerStatusPresentation,
        countdownProgress: CountdownProgressPresentation?
    ) -> Bool {
        presentation.dotPhase == .leadingRed ||
            presentation.dotPhase == .trailingRed ||
            countdownProgress?.isWarning == true
    }

    private static func menuBarPrimaryColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? .white : .black
    }

    private static func textAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: foregroundColor
        ]
    }

    private static func drawDot(isVisible: Bool, color: NSColor = .labelColor, in rect: NSRect) {
        guard isVisible else {
            return
        }

        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private static func drawProgress(_ progress: CountdownProgressPresentation, primaryColor: NSColor, in rect: NSRect) {
        let outlineRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let progressColor = progress.isWarning ? NSColor.systemRed : primaryColor
        let outlinePath = NSBezierPath(
            roundedRect: outlineRect,
            xRadius: outlineRect.height / 2,
            yRadius: outlineRect.height / 2
        )

        progressColor.setStroke()
        outlinePath.lineWidth = 1
        outlinePath.stroke()

        let fillRect = outlineRect.insetBy(dx: Layout.progressInset, dy: Layout.progressInset)
        let fillWidth = fillRect.width * min(1, max(0, progress.fractionComplete))
        guard fillWidth > 0 else {
            return
        }

        let fillPath = NSBezierPath(
            roundedRect: NSRect(x: fillRect.minX, y: fillRect.minY, width: fillWidth, height: fillRect.height),
            xRadius: fillRect.height / 2,
            yRadius: fillRect.height / 2
        )
        progressColor.withAlphaComponent(0.75).setFill()
        fillPath.fill()
    }
}
```

### Task 4: Add `UpdateManager.swift` to Xcode project

**Files:**
- Modify: `JustAboutTime.xcodeproj/project.pbxproj` — add the new file to the project

- [ ] **Step 1: Add UpdateManager.swift to the Xcode project**

The file `JustAboutTime/UpdateManager.swift` must be added to the Xcode project under the `JustAboutTime` group with target membership for `JustAboutTime`.

Manually: In Xcode, right-click the `JustAboutTime` group → "Add Files to JustAboutTime…" → select `UpdateManager.swift` → ensure "JustAboutTime" target is checked → click Add.

Or edit `project.pbxproj` directly to insert the file reference and build file entry (reference existing entries for pattern, e.g. `AboutView.swift`).

### Task 5: Run tests and verify build

**Files:**
- Test: `JustAboutTimeTests/` (no new test file; verification-only step)

- [ ] **Step 1: Build the project**

Run: `xcodebuild -project JustAboutTime.xcodeproj -scheme JustAboutTime -configuration Debug build 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run existing tests**

Run: `xcodebuild -project JustAboutTime.xcodeproj -scheme JustAboutTime -configuration Debug test 2>&1 | tail -20`
Expected: All tests pass, no regressions.

- [ ] **Step 3: Commit**

```bash
git add JustAboutTime/UpdateManager.swift JustAboutTime/AboutView.swift JustAboutTime/JustAboutTimeApp.swift JustAboutTime.xcodeproj/project.pbxproj
git commit -m "feat: add auto-update checking via GitHub Releases API"
```
