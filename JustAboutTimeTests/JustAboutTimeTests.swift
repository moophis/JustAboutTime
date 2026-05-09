import Testing
@testable import JustAboutTime
import Foundation

struct JustAboutTimeTests {
    struct TestError: Error {}

    @Test func countdownStartsWithCorrectTarget() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        let events = machine.send(.startCountdown(duration: 300, now: now))

        #expect(events.isEmpty)
        #expect(
            machine.state == .active(
                TimerSession(
                    startedAt: now,
                    mode: .countdown(duration: 300),
                    phase: .runningCountdown(targetDate: now.addingTimeInterval(300))
                )
            )
        )
    }

    @Test func pauseAndResumePreserveRemainingCountdownTime() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountdown(duration: 120, now: start))
        _ = machine.send(.pause(now: start.addingTimeInterval(30)))

        #expect(machine.session?.remainingTime(at: start.addingTimeInterval(45)) == 90)

        _ = machine.send(.resume(now: start.addingTimeInterval(50)))

        #expect(machine.session?.remainingTime(at: start.addingTimeInterval(80)) == 60)
    }

    @Test func restartResetsCountdownToOriginalDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountdown(duration: 120, now: start))
        _ = machine.send(.pause(now: start.addingTimeInterval(30)))
        _ = machine.send(.restart(now: start.addingTimeInterval(70)))

        #expect(
            machine.state == .active(
                TimerSession(
                    startedAt: start.addingTimeInterval(70),
                    mode: .countdown(duration: 120),
                    phase: .runningCountdown(targetDate: start.addingTimeInterval(190))
                )
            )
        )
    }

    @Test func overdueRestartEmitsCompletionAndStartsFreshCountdown() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountdown(duration: 120, now: start))
        let events = machine.send(.restart(now: start.addingTimeInterval(130)))

        #expect(events == [.countdownCompleted])
        #expect(
            machine.state == .active(
                TimerSession(
                    startedAt: start.addingTimeInterval(130),
                    mode: .countdown(duration: 120),
                    phase: .runningCountdown(targetDate: start.addingTimeInterval(250))
                )
            )
        )
    }

    @Test func countUpAdvancesFromZero() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountUp(now: start))
        _ = machine.send(.tick(now: start.addingTimeInterval(45)))

        #expect(machine.session?.elapsedTime(at: start.addingTimeInterval(45)) == 45)
    }

    @Test func finishReturnsToIdle() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountUp(now: start))
        let events = machine.send(.finish(now: start))

        #expect(events.isEmpty)
        #expect(machine.state == .idle)
    }

    @Test func overdueFinishEmitsCompletionAndReturnsToIdle() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountdown(duration: 5, now: start))
        let events = machine.send(.finish(now: start.addingTimeInterval(6)))

        #expect(events == [.countdownCompleted])
        #expect(machine.state == .idle)
    }

    @Test func countdownCompletionEmitsCompletionEvent() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountdown(duration: 5, now: start))
        let events = machine.send(.tick(now: start.addingTimeInterval(5)))

        #expect(events == [.countdownCompleted])
        #expect(machine.state == .idle)
    }

    @Test func countdownElapsedTimeStopsAtOriginalDuration() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountdown(duration: 5, now: start))

        #expect(machine.session?.elapsedTime(at: start.addingTimeInterval(10)) == 5)
    }

    @Test func zeroCountdownCompletesImmediately() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        let events = machine.send(.startCountdown(duration: 0, now: start))

        #expect(events == [.countdownCompleted])
        #expect(machine.state == .idle)
    }

    @Test func negativeCountdownCompletesImmediately() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        let events = machine.send(.startCountdown(duration: -5, now: start))

        #expect(events == [.countdownCompleted])
        #expect(machine.state == .idle)
    }

    @Test func countUpNeverGoesNegativeWhenTimeMovesBackward() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var machine = TimerStateMachine()

        _ = machine.send(.startCountUp(now: start))

        #expect(machine.session?.elapsedTime(at: start.addingTimeInterval(-10)) == 0)

        _ = machine.send(.pause(now: start.addingTimeInterval(-10)))

        #expect(machine.session?.elapsedTime(at: start.addingTimeInterval(5)) == 0)
    }

    @Test func appConfigurationDefinesExpectedDefaults() {
        #expect(AppConfiguration.appDisplayName == "Just About Time")
        #expect(AppConfiguration.menuBarSystemImage == "timer")
        #expect(AppConfiguration.defaultPresetDurations == [300, 1_500, 3_000])
        #expect(AppConfiguration.minimumPresetDuration == 1)
        #expect(AppConfiguration.maximumPresetDuration == 86_400)
        #expect(AppConfiguration.startPauseShortcutName.rawValue == "startPauseTimer")
        #expect(AppConfiguration.restartShortcutName.rawValue == "restartTimer")
        #expect(AppConfiguration.finishShortcutName.rawValue == "finishTimer")
    }

    @Test func infoPlistEnablesAgentMode() throws {
        let plist = try projectDictionary(at: projectFilePath("JustAboutTime/Info.plist"))

        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
    }

    @Test func appEntrypointUsesMenuBarExtraWithoutWindowGroup() throws {
        let appSource = try source(at: projectFilePath("JustAboutTime/JustAboutTimeApp.swift"))

        #expect(appSource.contains("MenuBarExtra"))
        #expect(appSource.contains("WindowGroup") == false)
        #expect(appSource.contains("MenuBarView(timerStore: timerStore, preferencesStore: preferencesStore)"))
        #expect(appSource.contains("presentation: timerStore.statusPresentation"))
        #expect(appSource.contains("countdownProgress: timerStore.countdownProgress"))
        #expect(appSource.contains("@StateObject private var historyStore: HistoryStore"))
        #expect(appSource.contains("@StateObject private var notificationManager: NotificationManager"))
        #expect(appSource.contains("@StateObject private var shortcutManager: ShortcutManager"))
        #expect(appSource.contains("@StateObject private var preferencesStore = PreferencesStore()"))
        #expect(appSource.contains("let historyStore = HistoryStore()"))
        #expect(appSource.contains("let notificationManager = NotificationManager()"))
        #expect(appSource.contains("let timerStore = TimerStore(historyStore: historyStore, notificationManager: notificationManager, preferencesStore: preferencesStore)"))
        #expect(appSource.contains("ShortcutManager(timerStore: timerStore)"))
        #expect(appSource.contains("Window(\"History\", id: HistoryWindow.id)"))
        #expect(appSource.contains("HistoryView(historyStore: historyStore, timerStore: timerStore)"))
        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)"))
    }

    @Test func menuBarViewAcceptsTimerStore() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("timerStore: TimerStore"))
    }

    @Test func menuBarViewAcceptsPreferencesStore() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("preferencesStore: PreferencesStore"))
        #expect(menuSource.contains("@ObservedObject var preferencesStore: PreferencesStore"))
    }

    @Test func menuBarViewObservesTimerStore() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("@ObservedObject var timerStore: TimerStore"))
    }

    @Test func menuBarViewKeepsQuitPath() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Button(\"Quit"))
        #expect(menuSource.contains("NSApplication.shared.terminate(nil)"))
    }

    @Test func idleMenuIncludesPresetActionsAndEntryPoints() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("preferencesStore.presetDurations.enumerated()"))
        #expect(menuSource.contains("Button(\"Count Up\")"))
        #expect(menuSource.contains("Button(\"Open History…\")"))
        #expect(menuSource.contains("Button(\"Preferences…\")"))
        #expect(menuSource.contains("@Environment(\\.openSettings) private var openSettings"))
        #expect(menuSource.contains("openSettings()"))
    }

    @Test func activeMenuIncludesTimerControlsAndSummary() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Button(isRunning ? \"Pause\" : \"Resume\")"))
        #expect(menuSource.contains("Button(\"Restart\")"))
        #expect(menuSource.contains("Button(\"Finish\")"))
        #expect(menuSource.contains("timerInfo"))
        #expect(menuSource.contains("StableTimerStatusView(timerStore: timerStore)"))
    }

    @Test func statusBarLabelKeepsFixedDotSlotsAndTemplateTintWhenPossible() throws {
        let appSource = try source(at: projectFilePath("JustAboutTime/JustAboutTimeApp.swift"))

        #expect(appSource.contains("Image(nsImage: StatusBarLabelImageRenderer.image"))
        #expect(appSource.contains("@Environment(\\.colorScheme) private var colorScheme"))
        #expect(appSource.contains("colorScheme: colorScheme"))
        #expect(appSource.contains("image.isTemplate = !needsOriginalColor"))
        #expect(appSource.contains("let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor"))
        #expect(appSource.contains("private static func menuBarPrimaryColor(for colorScheme: ColorScheme) -> NSColor"))
        #expect(appSource.contains("colorScheme == .dark ? .white : .black"))
        #expect(appSource.contains("presentation.dotPhase == .leading"))
        #expect(appSource.contains("presentation.dotPhase == .trailing"))
        #expect(appSource.contains("presentation.dotPhase == .leadingRed"))
        #expect(appSource.contains("presentation.dotPhase == .trailingRed"))
        #expect(appSource.contains("progress.isWarning ? NSColor.systemRed : primaryColor"))
        #expect(appSource.contains("drawProgress("))
    }

    @Test func projectKeepsKeyboardShortcutsPackageAndAppIconSetting() throws {
        let projectSource = try source(at: projectFilePath("JustAboutTime.xcodeproj/project.pbxproj"))

        #expect(projectSource.contains("https://github.com/sindresorhus/KeyboardShortcuts.git"))
        #expect(projectSource.contains("Assets.xcassets in Resources"))
        #expect(projectSource.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon"))
    }

    @Test func preferencesViewIncludesPresetShortcutAndNotificationSections() throws {
        let source = try source(at: projectFilePath("JustAboutTime/PreferencesView.swift"))

        #expect(source.contains("Section(\"Countdown Presets\")"))
        #expect(source.contains("KeyboardShortcuts.Recorder(for: name)"))
        #expect(source.contains("Conflicting or invalid shortcuts are rejected automatically."))
        #expect(source.contains("Section(\"Notifications\")"))
        #expect(source.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(source.contains(".task(id: scenePhase)"))
        #expect(source.contains("if let settingsURL = URL("))
        #expect(source.contains("Notifications-Settings.extension\")!)") == false)
    }

    @Test func shortcutManagerUsesKeyboardShortcutsGlobalKeyUpHandler() throws {
        let source = try source(at: projectFilePath("JustAboutTime/ShortcutManager.swift"))

        #expect(source.contains("KeyboardShortcuts.onKeyUp(for: name)"))
        #expect(source.contains("client: Client = .live"))
    }

    @Test func historyViewIncludesErrorStateBannerAndTable() throws {
        let source = try source(at: projectFilePath("JustAboutTime/HistoryView.swift"))

        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains("timerStore.latestHistoryError"))
        #expect(source.contains("historyStore.latestLoadError"))
        #expect(source.contains("Table(historyStore.entries)"))
    }

    private func projectFilePath(_ relativePath: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relativePath)
    }

    private func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func projectDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw TestError()
        }
        return plist
    }
}
