import Combine
import Foundation

@MainActor
final class TimerCoordinator: ObservableObject {
    @Published private(set) var isSecondaryActivated = false
    @Published private var orderedTimers: [TimerStore]

    private let preferencesStore: PreferencesStore
    private var timerCancellables = Set<AnyCancellable>()

    var primaryTimer: TimerStore {
        orderedTimers[0]
    }

    var secondaryTimer: TimerStore {
        orderedTimers[1]
    }

    var latestHistoryFailures: [TimerStore.HistoryFailure] {
        var failures = [primaryTimer.latestHistoryFailure]
        if isSecondaryActivated {
            failures.append(secondaryTimer.latestHistoryFailure)
        }
        return failures.compactMap { $0 }
    }

    init(
        primaryTimer: TimerStore,
        secondaryTimer: TimerStore,
        preferencesStore: PreferencesStore
    ) {
        self.preferencesStore = preferencesStore
        primaryTimer.assignRole(.primary)
        secondaryTimer.assignRole(.secondary)
        orderedTimers = [primaryTimer, secondaryTimer]
        observeTimers([primaryTimer, secondaryTimer])
    }

    convenience init(
        historyStore: HistoryStore,
        notificationManager: NotificationManager,
        preferencesStore: PreferencesStore
    ) {
        self.init(
            primaryTimer: TimerStore(
                role: .primary,
                historyStore: historyStore,
                notificationManager: notificationManager,
                preferencesStore: preferencesStore
            ),
            secondaryTimer: TimerStore(
                role: .secondary,
                historyStore: historyStore,
                notificationManager: notificationManager,
                preferencesStore: preferencesStore
            ),
            preferencesStore: preferencesStore
        )
    }

    func timer(for role: TimerRole) -> TimerStore {
        switch role {
        case .primary:
            return primaryTimer
        case .secondary:
            return secondaryTimer
        }
    }

    func activateSecondary() {
        isSecondaryActivated = true
    }

    func deactivateSecondary() {
        guard isSecondaryActivated else { return }
        secondaryTimer.deactivate()
        isSecondaryActivated = false
    }

    func swapTimers() {
        guard isSecondaryActivated else { return }

        let newPrimary = secondaryTimer
        let newSecondary = primaryTimer
        newPrimary.assignRole(.primary)
        newSecondary.assignRole(.secondary)
        preferencesStore.swapTimerProfiles()
        orderedTimers = [newPrimary, newSecondary]
    }

    func systemPause() {
        primaryTimer.systemPause()
        if isSecondaryActivated {
            secondaryTimer.systemPause()
        }
    }

    func systemResume() {
        primaryTimer.systemResume()
        if isSecondaryActivated {
            secondaryTimer.systemResume()
        }
    }

    private func observeTimers(_ timers: [TimerStore]) {
        for timer in timers {
            timer.$activeSession
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &timerCancellables)

            timer.$latestHistoryFailure
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &timerCancellables)
        }
    }
}
