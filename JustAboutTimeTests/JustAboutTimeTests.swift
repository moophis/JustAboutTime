import Testing
@testable import JustAboutTime
import Foundation
import AppKit

struct JustAboutTimeTests {
    struct TestError: Error {}

    @MainActor
    @Test func statusBarLabelKeepsOverdueTextWidthStableWithoutPlusPrefix() {
        let progress = CountdownProgressPresentation(fractionComplete: 1, isWarning: false)
        for dual in [false, true] {
            let sizes = [TimerUrgency.neutral, .warning, .pausedWarning, .overdue].map { urgency in
                StatusBarLabelImageRenderer.image(
                    primaryPresentation: TimerStatusPresentation(
                        text: "00:01",
                        dotPhase: .hidden, urgency: urgency),
                    primaryProgress: progress,
                    secondaryPresentation: dual ? TimerStatusPresentation(text: "00:30", dotPhase: .hidden) : nil,
                    secondaryProgress: dual ? progress : nil,
                    colorScheme: .light,
                    primaryPillOpacity: urgency.opacity
                ).size
            }
            #expect(sizes.dropFirst().allSatisfy {
                abs($0.width - sizes[0].width) < 0.5 && abs($0.height - sizes[0].height) < 0.5
            })
        }
    }

    @MainActor
    @Test func statusBarLabelKeepsEnlargedDigitsWithinStatusBarHeight() {
        let progress = CountdownProgressPresentation(fractionComplete: 0.5, isWarning: false)
        let mmss = StatusBarLabelImageRenderer.image(
            primaryPresentation: TimerStatusPresentation(text: "04:52", dotPhase: .hidden),
            primaryProgress: progress,
            secondaryPresentation: nil,
            secondaryProgress: nil,
            colorScheme: .light
        )
        let overdue = StatusBarLabelImageRenderer.image(
            primaryPresentation: TimerStatusPresentation(text: "01:04:52", dotPhase: .hidden, urgency: .overdue),
            primaryProgress: progress,
            secondaryPresentation: nil,
            secondaryProgress: nil,
            colorScheme: .light,
            primaryPillOpacity: 1
        )
        let dual = StatusBarLabelImageRenderer.image(
            primaryPresentation: TimerStatusPresentation(text: "04:52", dotPhase: .hidden),
            primaryProgress: progress,
            secondaryPresentation: TimerStatusPresentation(text: "01:04:52", dotPhase: .hidden, urgency: .overdue),
            secondaryProgress: progress,
            colorScheme: .light,
            primaryPillOpacity: 0.1,
            secondaryPillOpacity: 1
        )

        #expect(StatusBarLabelImageRenderer.timerFontSize == NSFont.systemFontSize)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = ("04:52" as NSString).size(withAttributes: attributes)
        let geometry = StatusBarLabelImageRenderer.rowGeometry(text: "04:52", attributes: attributes, textSize: textSize)
        #expect(abs(mmss.size.width - (geometry.rowSize.width + 16)) < 0.01)
        #expect(mmss.size.height > 0)
        #expect(overdue.size.height == mmss.size.height)
        #expect(dual.size.height == mmss.size.height)
        #expect(mmss.size.height > textSize.height + 2)
        #expect(overdue.size.height >= mmss.size.height)
        #expect(overdue.size.width > mmss.size.width)
    }

    @MainActor
    @Test func statusBarRenderedGeometryUsesEqualVisibleGlyphGapsAndWhiteUrgencyDots() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = ("00:08" as NSString).size(withAttributes: attributes)
        let geometry = StatusBarLabelImageRenderer.rowGeometry(text: "00:08", attributes: attributes, textSize: textSize)
        let leftGap = geometry.textInkBounds.minX + geometry.textOrigin.x - geometry.leadingDot.maxX
        let rightGap = geometry.trailingDot.minX - (geometry.textInkBounds.maxX + geometry.textOrigin.x)
        #expect(abs(leftGap - rightGap) < 0.01)
        #expect(geometry.rowSize.width > textSize.width + 20)

        let overdue = TimerStatusPresentation(text: "00:08", dotPhase: .leading, urgency: .overdue)
        let image = StatusBarLabelImageRenderer.image(primaryPresentation: overdue, primaryProgress: nil, secondaryPresentation: nil, secondaryProgress: nil, colorScheme: .light)
        #expect(image.size.width == geometry.rowSize.width + 16)
        // The renderer canvas and pill geometry remain unchanged; the separate
        // native status-button inset is reduced by the label's outer padding.
        #expect(image.size.width - geometry.rowSize.width == 16)
        let white = StatusBarLabelImageRenderer.indicatorColor(for: .overdue, base: .systemRed).usingColorSpace(.sRGB)
        #expect((white?.redComponent ?? 0) > 0.95)
        #expect((white?.greenComponent ?? 0) > 0.95)
        #expect((white?.blueComponent ?? 0) > 0.95)
    }

    @MainActor
    @Test func statusBarProductionRendererWritesDeterministicDueAndOverdueArtifacts() throws {
        let directory = ProcessInfo.processInfo.environment["STATUSBAR_RENDER_ARTIFACT_DIR"] ?? "/tmp/just-about-time-render-artifacts"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let progress = CountdownProgressPresentation(fractionComplete: 0.5, isWarning: false)
        let cases: [(String, TimerStatusPresentation, TimerStatusPresentation?)] = [
            ("due-leading", TimerStatusPresentation(text: "01:39", dotPhase: .leading, urgency: .warning), nil),
            ("due-trailing", TimerStatusPresentation(text: "01:39", dotPhase: .trailingRed, urgency: .warning), nil),
            ("overdue-leading", TimerStatusPresentation(text: "01:39", dotPhase: .leading, urgency: .overdue), nil),
            ("overdue-trailing", TimerStatusPresentation(text: "01:39", dotPhase: .trailingRed, urgency: .overdue), nil),
            ("dual-due", TimerStatusPresentation(text: "01:39", dotPhase: .leading, urgency: .warning), TimerStatusPresentation(text: "00:30", dotPhase: .trailingRed, urgency: .warning)),
            ("dual-overdue", TimerStatusPresentation(text: "01:39", dotPhase: .leading, urgency: .overdue), TimerStatusPresentation(text: "00:30", dotPhase: .trailingRed, urgency: .overdue))
        ]
        for (name, presentation, secondary) in cases {
            let image = StatusBarLabelImageRenderer.image(
                primaryPresentation: presentation,
                primaryProgress: progress,
                secondaryPresentation: secondary,
                secondaryProgress: secondary.map { _ in progress },
                colorScheme: .light,
                primaryPillOpacity: 1,
                secondaryPillOpacity: secondary == nil ? 0 : 1
            )
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("statusbar-\(name).png"))
        }
    }

    @Test func statusBarPresenterUsesBlinkingLeftDotNormallyAndRotatesOnlyWhenUrgent() {
        let presenter = StatusBarPresenter()
        #expect(presenter.presentation(for: .idle, animationStep: 0).dotPhase == .leadingSquare)
        #expect(presenter.presentation(for: .countdown(remaining: 60, isRunning: true, isWarning: false), animationStep: 0).dotPhase == .leading)
        #expect(presenter.presentation(for: .countdown(remaining: 60, isRunning: true, isWarning: false), animationStep: 1).dotPhase == .hidden)
        #expect(presenter.presentation(for: .countdown(remaining: 5, isRunning: true, isWarning: true), animationStep: 0).dotPhase == .leadingRed)
        #expect(presenter.presentation(for: .countUp(elapsed: 5, isRunning: true, isOverdue: true), animationStep: 1).dotPhase == .hidden)
        #expect(presenter.presentation(for: .countUp(elapsed: 5, isRunning: true, isOverdue: true), animationStep: 0).text == "00:05")
        #expect(presenter.presentation(for: .countdown(remaining: 60, isRunning: false, isWarning: false), animationStep: 0).dotPhase == .leadingPause)
    }

    @Test func countUpNeverRotatesEvenAfterLongElapsedOverdue() {
        let presenter = StatusBarPresenter()
        for step in [0, 1, 2, 17, 10_000] {
            let normal = presenter.presentation(for: .countUp(elapsed: 86_401, isRunning: true, isOverdue: false), animationStep: step)
            let overdue = presenter.presentation(for: .countUp(elapsed: 86_401, isRunning: true, isOverdue: true), animationStep: step)
            #expect(normal.dotPhase == (step.isMultiple(of: 2) ? .leading : .hidden))
            #expect(overdue.dotPhase == (step.isMultiple(of: 2) ? .leading : .hidden))
            #expect(overdue.text == "24:00:01")
        }
    }

    @Test func countdownWarningRotatesWhileNormalCountdownOnlyBlinksLeadingSlot() {
        let presenter = StatusBarPresenter()
        for step in [0, 1, 2, 3] {
            let normal = presenter.presentation(for: .countdown(remaining: 60, isRunning: true, isWarning: false), animationStep: step)
            #expect(normal.dotPhase == (step.isMultiple(of: 2) ? .leading : .hidden))
        }
        #expect(presenter.presentation(for: .countdown(remaining: 5, isRunning: true, isWarning: true), animationStep: 0).dotPhase == .leadingRed)
        #expect(presenter.presentation(for: .countdown(remaining: 5, isRunning: true, isWarning: true), animationStep: 1).dotPhase == .trailingRed)
    }

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
        #expect(menuSource.contains("startNewTimerMenu(timer: timer, role: role)"))
        #expect(menuSource.contains("repeatLastTimerButton(timer: timer)"))
        #expect(menuSource.contains("Label(\"Repeat Last Timer\", systemImage: \"arrow.clockwise\")"))
        #expect(menuSource.contains(".disabled(!timer.canRepeatLastTimer)"))
        #expect(menuSource.contains(".keyboardShortcut(\"l\", modifiers: shortcutModifiers(for: timer.role))"))
        #expect(menuSource.contains("Label(\"Start New Timer\", systemImage: \"timer\")"))
        #expect(menuSource.contains("Button(formattedDuration(duration) + \" Countdown\")"))
        #expect(menuSource.contains("indentedCountdownTitle") == false)
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

    @Test func statusBarLabelUsesIsolatedCompactCellsAndFullCountersForDualTimers() throws {
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
        #expect(appSource.contains("ofSize: compactFontSize"))
        #expect(appSource.contains("NSFont.monospacedDigitSystemFont(ofSize: compactFontSize, weight: .regular)"))
        #expect(appSource.contains("NSFont.monospacedDigitSystemFont(ofSize: compactFontSize, weight: .semibold)" ) == false)
        #expect(appSource.contains("$0 * 2 + Layout.progressGap"))
        #expect(appSource.contains("pillHorizontalPadding"))
        #expect(appSource.contains("pillVerticalPadding"))
        #expect(appSource.contains("statusButtonHorizontalInset: CGFloat = 10"))
        #expect(appSource.contains(".padding(.horizontal, -StatusBarLabelImageRenderer.statusButtonHorizontalInset)"))
        #expect(appSource.contains("drawPill(opacity: primaryPillOpacity"))
        #expect(appSource.contains("secondaryTextSize = secondaryPresentation.text.size(withAttributes: attributes)"))
        #expect(appSource.contains("drawPill(opacity: secondaryPillOpacity"))
        #expect(appSource.contains("presentation.text.draw(at: textOrigin, withAttributes: attributes)"))
        #expect(appSource.contains("\"2\".draw(at: secondaryOrigin") == false)
        #expect(appSource.contains("drawProgress("))
        #expect(appSource.contains("progressInset"))
        #expect(appSource.contains("progressHeight"))
        #expect(appSource.contains("drawPill(opacity: primaryPillOpacity"))
        #expect(appSource.contains("width: cellWidth + Layout.pillHorizontalPadding * 2"))
        #expect(appSource.contains("height: imageSize.height"))
        #expect(appSource.contains(".trailing, .trailingRed"))
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
