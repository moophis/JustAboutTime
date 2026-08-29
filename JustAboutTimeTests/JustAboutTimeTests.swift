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
        #expect(AppConfiguration.defaultPresetDurations == [300, 1_500, 2_700])
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
        #expect(appSource.contains("MenuBarView(timerCoordinator: timerCoordinator, preferencesStore: preferencesStore)"))
        #expect(appSource.contains("StatusBarLabelView(timerCoordinator: timerCoordinator)"))
        #expect(appSource.contains("@StateObject private var historyStore: HistoryStore"))
        #expect(appSource.contains("@StateObject private var notificationManager: NotificationManager"))
        #expect(appSource.contains("@StateObject private var shortcutManager: ShortcutManager"))
        #expect(appSource.contains("@StateObject private var preferencesStore = PreferencesStore()"))
        #expect(appSource.contains("@StateObject private var timerCoordinator: TimerCoordinator"))
        #expect(appSource.contains("let historyStore = HistoryStore()"))
        #expect(appSource.contains("let notificationManager = NotificationManager()"))
        #expect(appSource.contains("let timerCoordinator = TimerCoordinator("))
        #expect(appSource.contains("ShortcutManager(timerCoordinator: timerCoordinator)"))
        #expect(appSource.contains("Window(\"History\", id: HistoryWindow.id)"))
        #expect(appSource.contains("HistoryView(historyStore: historyStore, timerCoordinator: timerCoordinator)"))
        #expect(appSource.contains("Settings {"))
        #expect(appSource.contains("PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)"))
    }

    @Test func menuBarViewAcceptsTimerCoordinator() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("@ObservedObject var timerCoordinator: TimerCoordinator"))
    }

    @Test func menuBarViewAcceptsPreferencesStore() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("preferencesStore: PreferencesStore"))
        #expect(menuSource.contains("@ObservedObject var preferencesStore: PreferencesStore"))
    }

    @Test func menuBarViewKeepsQuitPath() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Label(\"Quit\", systemImage: \"power\")"))
        #expect(menuSource.contains("NSApplication.shared.terminate(nil)"))
    }

    @Test func menuIncludesTimerSectionsAndEntryPoints() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Section(\"Primary Timer\")"))
        #expect(menuSource.contains("Section(\"Secondary Timer\")"))
        #expect(menuSource.contains("preferencesStore.presetDurations(for: role).enumerated()"))
        #expect(menuSource.contains("Button(\"Count Up\")"))
        #expect(menuSource.contains("Label(\"Activate Secondary Timer\", systemImage: \"plus.circle\")"))
        #expect(menuSource.contains("Label(\"About JustAboutTime\", systemImage: \"info.circle\")"))
        #expect(menuSource.contains("Label(\"Open History…\", systemImage: \"clock.arrow.circlepath\")"))
        #expect(menuSource.contains("Label(\"Preferences…\", systemImage: \"gearshape\")"))
        #expect(menuSource.contains("@Environment(\\.openSettings) private var openSettings"))
        #expect(menuSource.contains("openSettings()"))
    }

    @Test func activeMenuIncludesTimerControlsAndMenuCompatibleStatusRows() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Label(isRunning ? \"Pause\" : \"Resume\", systemImage: isRunning ? \"pause.fill\" : \"play.fill\")"))
        #expect(menuSource.contains("Button(\"Restart\")"))
        #expect(menuSource.contains("Label(\"Finish\", systemImage: \"checkmark.circle\")"))
        #expect(menuSource.contains("Section(\"Primary Timer\") {\n            TimerMenuStatusRows(timerStore: timerCoordinator.primaryTimer)"))
        #expect(menuSource.contains("if timerCoordinator.isSecondaryActivated {\n                TimerMenuStatusRows(timerStore: timerCoordinator.secondaryTimer)"))
        #expect(menuSource.contains("Text(statusLine)"))
        #expect(menuSource.contains(".font(.system(.body, design: .monospaced))"))
        #expect(menuSource.contains("static let menuIconGutterWidth = 22.0"))
        #expect(menuSource.components(separatedBy: ".padding(.leading, -Layout.menuIconGutterWidth)").count == 3)
        #expect(menuSource.contains("static let statusCharacterCount = 40"))
        #expect(menuSource.contains("rightPadded(unpaddedStatusLine, to: Layout.statusCharacterCount)"))
        #expect(menuSource.contains(".accessibilityLabel(statusPresentation.accessibilityText)"))
        #expect(menuSource.contains("static let progressSegmentCount = 24"))
        #expect(menuSource.contains("String(repeating: \"▰\", count: filledCount)"))
        #expect(menuSource.contains("String(repeating: \"▱\", count: Layout.progressSegmentCount - filledCount)"))
        #expect(menuSource.contains("NSViewRepresentable") == false)
        #expect(menuSource.contains("timerInfo(") == false)
        #expect(menuSource.contains("Label(\"Swap Timers\", systemImage: \"arrow.up.arrow.down\")"))
    }

    @Test func menuBarViewAssignsLocalTimerShortcuts() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains(".keyboardShortcut(\"a\", modifiers: [.option])"))
        #expect(menuSource.contains(".keyboardShortcut(\"p\", modifiers: shortcutModifiers(for: role))"))
        #expect(menuSource.contains(".keyboardShortcut(\"r\", modifiers: shortcutModifiers(for: role))"))
        #expect(menuSource.contains("modifiers: shortcutModifiers(for: role)"))
        #expect(menuSource.contains(".keyboardShortcut(\"4\", modifiers: shortcutModifiers(for: role))"))
        #expect(menuSource.contains(".keyboardShortcut(\"f\", modifiers: shortcutModifiers(for: role))"))
        #expect(menuSource.contains(".keyboardShortcut(\"s\", modifiers: [.option])"))
        #expect(menuSource.contains("role == .secondary ? [.option] : []"))
    }

    @Test func statusBarLabelUsesIsolatedCompactCellsAndFullCountersWithoutDotsForDualTimers() throws {
        let appSource = try source(at: projectFilePath("JustAboutTime/JustAboutTimeApp.swift"))

        #expect(appSource.contains("Image(nsImage: StatusBarLabelImageRenderer.image"))
        #expect(appSource.contains("@Environment(\\.colorScheme) private var colorScheme"))
        #expect(appSource.contains("colorScheme: colorScheme"))
        #expect(appSource.contains("image.isTemplate = !needsOriginalColor"))
        #expect(appSource.contains("let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor"))
        #expect(appSource.contains("private static func menuBarPrimaryColor(for colorScheme: ColorScheme) -> NSColor"))
        #expect(appSource.contains("colorScheme == .dark ? .white : .black"))
        #expect(appSource.contains("primaryPresentation: TimerStatusPresentation"))
        #expect(appSource.contains("secondaryPresentation: TimerStatusPresentation?"))
        #expect(appSource.contains("let isDualTimer = secondaryPresentation != nil"))
        #expect(appSource.contains("ofSize: isDualTimer ? compactFontSize : NSFont.systemFontSize"))
        #expect(appSource.contains("NSFont.monospacedDigitSystemFont(ofSize: compactFontSize, weight: .regular)"))
        #expect(appSource.contains("NSFont.monospacedDigitSystemFont(ofSize: compactFontSize, weight: .semibold)" ) == false)
        #expect(appSource.contains("$0 * 2 + Layout.progressGap"))
        #expect(appSource.contains("drawDualTextRow("))
        #expect(appSource.contains("secondaryTextSize = secondaryPresentation.text.size(withAttributes: attributes)"))
        #expect(appSource.contains("secondaryText: secondaryPresentation.text"))
        #expect(appSource.contains("secondaryText.draw(at: secondaryOrigin, withAttributes: secondaryAttributes)"))
        #expect(appSource.contains("\"2\".draw(at: secondaryOrigin") == false)
        #expect(appSource.contains("let barWidth = (progressWidth - Layout.progressGap) / 2"))
        #expect(appSource.contains("progress.isWarning ? NSColor.systemRed : primaryColor"))
        #expect(appSource.contains("drawProgress("))
    }

    @Test func timerTicksUpdateStatusContentWithoutRebuildingSelectableMenuRows() throws {
        let coordinatorSource = try source(at: projectFilePath("JustAboutTime/TimerCoordinator.swift"))
        let appSource = try source(at: projectFilePath("JustAboutTime/JustAboutTimeApp.swift"))
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(coordinatorSource.contains("timer.$activeSession"))
        #expect(coordinatorSource.contains("timer.$latestHistoryFailure"))
        #expect(coordinatorSource.contains(".removeDuplicates()"))
        #expect(coordinatorSource.contains("timer.objectWillChange") == false)
        #expect(appSource.contains("private struct StatusBarTimerContentView: View"))
        #expect(appSource.contains("@ObservedObject var primaryTimer: TimerStore"))
        #expect(appSource.contains("@ObservedObject var secondaryTimer: TimerStore"))
        #expect(menuSource.contains("private final class MenuTrackingMonitor: ObservableObject"))
        #expect(menuSource.contains("NSMenu.didBeginTrackingNotification"))
        #expect(menuSource.contains("NSMenu.didEndTrackingNotification"))
        #expect(menuSource.contains("if MenuTrackingMonitor.shared.isTracking"))
        #expect(menuSource.contains("@StateObject private var statusObserver: TimerMenuStatusObserver"))
        #expect(menuSource.contains("@ObservedObject var timerStore: TimerStore") == false)
    }

    @Test func projectKeepsKeyboardShortcutsPackageAndAppIconSetting() throws {
        let projectSource = try source(at: projectFilePath("JustAboutTime.xcodeproj/project.pbxproj"))

        #expect(projectSource.contains("https://github.com/sindresorhus/KeyboardShortcuts.git"))
        #expect(projectSource.contains("Assets.xcassets in Resources"))
        #expect(projectSource.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon"))
    }

    @Test func preferencesViewIncludesTabbedPresetShortcutAndNotificationPages() throws {
        let source = try source(at: projectFilePath("JustAboutTime/PreferencesView.swift"))

        #expect(source.contains("TabView"))
        #expect(source.contains("GeneralPreferencesView(preferencesStore: preferencesStore)"))
        #expect(source.contains("ShortcutPreferencesView(preferencesStore: preferencesStore)"))
        #expect(source.contains("NotificationPreferencesView(notificationManager: notificationManager)"))
        #expect(source.contains("Label(\"General\", systemImage: \"gearshape\")"))
        #expect(source.contains("Label(\"Shortcuts\", systemImage: \"keyboard\")"))
        #expect(source.contains("Label(\"Notifications\", systemImage: \"bell\")"))
        #expect(source.contains("PreferencesGroup(title: \"COUNTDOWN TIMERS\")"))
        #expect(source.contains("Text(\"Primary Timer\")"))
        #expect(source.contains("Text(\"Secondary Timer\")"))
        #expect(source.contains("PreferencesGroup(title: \"SHORTCUTS\")"))
        #expect(source.contains("KeyboardShortcuts.Recorder(for: name)"))
        #expect(source.contains("Global shortcuts always control the current Primary Timer."))
        #expect(source.contains("PreferencesGroup(title: \"NOTIFICATIONS\")"))
        #expect(source.contains("Divider()"))
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
        #expect(source.contains("timerCoordinator.latestHistoryFailures"))
        #expect(source.contains("historyStore.latestLoadError"))
        #expect(source.contains("Table(historyStore.entries)"))
        #expect(source.contains("TableColumn(\"Timer\")"))
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
