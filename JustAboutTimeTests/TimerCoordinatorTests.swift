import Combine
import Foundation
import KeyboardShortcuts
import Testing

@testable import JustAboutTime

@MainActor
struct TimerCoordinatorTests {
    @Test func secondaryStartsInactiveAndCanBeActivated() {
        let context = makeContext()

        #expect(context.coordinator.isSecondaryActivated == false)

        context.coordinator.activateSecondary()

        #expect(context.coordinator.isSecondaryActivated)
        #expect(context.coordinator.secondaryTimer.activeSession == nil)
    }

    @Test func presentationOnlyTimerChangesDoNotRebuildCoordinatorMenus() {
        let context = makeContext()
        var coordinatorChangeCount = 0
        let cancellable = context.coordinator.objectWillChange.sink {
            coordinatorChangeCount += 1
        }

        context.primaryTimer.objectWillChange.send()

        #expect(coordinatorChangeCount == 0)

        context.primaryTimer.startCountdown(duration: 60)

        #expect(coordinatorChangeCount > 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test func swapMovesLiveTimersAndPersistedProfilesTogether() throws {
        let context = makeContext()
        try context.preferencesStore.setPresetDurations([60, 120, 180], for: .primary)
        try context.preferencesStore.setPresetDurations([300, 600, 900], for: .secondary)
        context.primaryTimer.startCountdown(duration: 60)
        context.secondaryTimer.startCountUp()
        context.coordinator.activateSecondary()

        context.coordinator.swapTimers()

        #expect(context.coordinator.primaryTimer === context.secondaryTimer)
        #expect(context.coordinator.secondaryTimer === context.primaryTimer)
        #expect(context.coordinator.primaryTimer.role == .primary)
        #expect(context.coordinator.secondaryTimer.role == .secondary)
        #expect(context.coordinator.primaryTimer.activeSession?.mode == .countUp)
        #expect(context.coordinator.secondaryTimer.activeSession?.mode == .countdown(duration: 60))
        #expect(context.preferencesStore.presetDurations(for: .primary) == [300, 600, 900])
        #expect(context.preferencesStore.presetDurations(for: .secondary) == [60, 120, 180])
    }

    @Test func deactivationFinishesOnlySecondaryAndResetsItsPresentation() {
        let context = makeContext()
        context.primaryTimer.startCountdown(duration: 60)
        context.secondaryTimer.startCountdown(duration: 90)
        context.coordinator.activateSecondary()

        context.coordinator.deactivateSecondary()

        #expect(context.coordinator.isSecondaryActivated == false)
        #expect(context.primaryTimer.activeSession?.mode == .countdown(duration: 60))
        #expect(context.secondaryTimer.activeSession == nil)
        #expect(context.secondaryTimer.latestEvent == nil)
        #expect(context.secondaryTimer.statusText == "00:00")
        #expect(context.secondaryTimer.countdownProgress?.isFillVisible == false)
    }

    @Test func systemPauseAndResumeApplyToBothActivatedTimers() {
        let context = makeContext()
        context.primaryTimer.startCountdown(duration: 60)
        context.secondaryTimer.startCountUp()
        context.coordinator.activateSecondary()

        context.coordinator.systemPause()

        #expect(context.primaryTimer.activeSession?.phase.isPaused == true)
        #expect(context.secondaryTimer.activeSession?.phase.isPaused == true)

        context.coordinator.systemResume()

        #expect(context.primaryTimer.activeSession?.phase.isRunning == true)
        #expect(context.secondaryTimer.activeSession?.phase.isRunning == true)
    }

    @Test func globalShortcutsFollowPrimaryRoleAfterSwap() {
        let context = makeContext()
        let registry = CoordinatorShortcutRegistry()
        let manager = ShortcutManager(
            timerCoordinator: context.coordinator,
            client: .init(onKeyUp: { name, handler in
                registry.register(handler: handler, for: name)
            })
        )
        context.primaryTimer.startCountdown(duration: 60)
        context.secondaryTimer.startCountdown(duration: 90)
        context.coordinator.activateSecondary()
        context.coordinator.swapTimers()

        registry.press(AppShortcuts.finishTimer)

        #expect(context.secondaryTimer.activeSession == nil)
        #expect(context.primaryTimer.activeSession?.mode == .countdown(duration: 60))
        withExtendedLifetime(manager) {}
    }

    @Test func historyUsesRoleAtCompletionAfterSwap() throws {
        let context = makeContext()
        context.secondaryTimer.startCountdown(duration: 60)
        context.coordinator.activateSecondary()
        context.coordinator.swapTimers()
        context.clock.advance(by: 60)

        context.coordinator.primaryTimer.pause()

        let entry = try #require(context.historyStore.loadEntries().first)
        #expect(entry.timerRole == .primary)
        #expect(entry.presetDuration == 60)
    }

    private func makeContext() -> CoordinatorTestContext {
        let suiteName = "TimerCoordinatorTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let preferencesStore = PreferencesStore(userDefaults: userDefaults)
        let historyStore = HistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(suiteName, isDirectory: true)
                .appendingPathComponent("history.json")
        )
        let clock = CoordinatorClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let primaryTimer = TimerStore(
            role: .primary,
            historyStore: historyStore,
            preferencesStore: preferencesStore,
            now: { clock.now }
        )
        let secondaryTimer = TimerStore(
            role: .secondary,
            historyStore: historyStore,
            preferencesStore: preferencesStore,
            now: { clock.now }
        )
        let coordinator = TimerCoordinator(
            primaryTimer: primaryTimer,
            secondaryTimer: secondaryTimer,
            preferencesStore: preferencesStore
        )
        return CoordinatorTestContext(
            preferencesStore: preferencesStore,
            historyStore: historyStore,
            clock: clock,
            primaryTimer: primaryTimer,
            secondaryTimer: secondaryTimer,
            coordinator: coordinator
        )
    }
}

@MainActor
private struct CoordinatorTestContext {
    let preferencesStore: PreferencesStore
    let historyStore: HistoryStore
    let clock: CoordinatorClock
    let primaryTimer: TimerStore
    let secondaryTimer: TimerStore
    let coordinator: TimerCoordinator
}

private final class CoordinatorClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

@MainActor
private final class CoordinatorShortcutRegistry {
    private var handlers: [String: @MainActor () -> Void] = [:]

    func register(handler: @escaping @MainActor () -> Void, for name: KeyboardShortcuts.Name) {
        handlers[name.rawValue] = handler
    }

    func press(_ name: KeyboardShortcuts.Name) {
        handlers[name.rawValue]?()
    }
}

private extension TimerSession.Phase {
    var isPaused: Bool {
        switch self {
        case .pausedCountdown, .pausedCountUp:
            return true
        case .runningCountdown, .runningCountUp:
            return false
        }
    }

    var isRunning: Bool {
        !isPaused
    }
}
