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
        #expect(machine.state == .active(TimerSession(mode: .countdown(duration: 300), phase: .runningCountdown(targetDate: now.addingTimeInterval(300)))))
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

        #expect(machine.state == .active(TimerSession(mode: .countdown(duration: 120), phase: .runningCountdown(targetDate: start.addingTimeInterval(190)))))
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
        let events = machine.send(.finish)

        #expect(events.isEmpty)
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

    @Test func appConfigurationDefinesExpectedDefaults() {
        #expect(AppConfiguration.appDisplayName == "Just About Time")
        #expect(AppConfiguration.menuBarSystemImage == "timer")
        #expect(AppConfiguration.toggleTimerShortcutName.rawValue == "toggleTimer")
    }

    @Test func infoPlistEnablesAgentMode() throws {
        let plist = try projectDictionary(at: projectFilePath("JustAboutTime/Info.plist"))

        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
    }

    @Test func appEntrypointUsesMenuBarExtraWithoutWindowGroup() throws {
        let appSource = try source(at: projectFilePath("JustAboutTime/JustAboutTimeApp.swift"))

        #expect(appSource.contains("MenuBarExtra("))
        #expect(appSource.contains("WindowGroup") == false)
    }

    @Test func menuBarViewKeepsQuitPath() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Button(\"Quit"))
        #expect(menuSource.contains("NSApplication.shared.terminate(nil)"))
    }

    @Test func projectKeepsKeyboardShortcutsPackageAndNoAppIconSetting() throws {
        let projectSource = try source(at: projectFilePath("JustAboutTime.xcodeproj/project.pbxproj"))

        #expect(projectSource.contains("https://github.com/sindresorhus/KeyboardShortcuts.git"))
        #expect(projectSource.contains("ASSETCATALOG_COMPILER_APPICON_NAME") == false)
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
