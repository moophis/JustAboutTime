import Combine
import Foundation
import WidgetKit

@MainActor
final class TimerCoordinator: ObservableObject {
    @Published private(set) var isSecondaryActivated = false
    @Published private(set) var widgetSetupRole: TimerRole?
    @Published private var orderedTimers: [TimerStore]

    private let preferencesStore: PreferencesStore
    private let reloadWidgets: () -> Void
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
        preferencesStore: PreferencesStore,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: "JustAboutTimeWidget") },
        restoring snapshots: [TimerRole: SharedTimerSnapshot] = [:]
    ) {
        self.preferencesStore = preferencesStore
        self.reloadWidgets = reloadWidgets
        primaryTimer.assignRole(.primary)
        secondaryTimer.assignRole(.secondary)
        orderedTimers = [primaryTimer, secondaryTimer]
        if let snapshot = snapshots[.primary] { primaryTimer.restoreWidgetSnapshot(snapshot) }
        if let snapshot = snapshots[.secondary] {
            isSecondaryActivated = secondaryTimer.restoreWidgetSnapshot(snapshot)
        }
        observeTimers([primaryTimer, secondaryTimer])
        publishWidgetSnapshots(reloadWidget: true)
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
            preferencesStore: preferencesStore,
            restoring: SharedTimerSnapshotStore.load()
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


    func consumeWidgetCommand() {
        guard let command = SharedTimerSnapshotStore.takeCommand() else { return }
        applyWidgetCommand(command)
    }

    func applyWidgetCommand(_ command: SharedTimerCommand) {
        let store = timer(for: command.role)
        guard (command.role == .primary || isSecondaryActivated),
              command.sessionID == store.sessionID,
              store.sharedSnapshot().availableActions.contains(command.action) else {
            publishWidgetSnapshots(reloadWidget: true)
            return
        }
        switch command.action {
        case .pause: timer(for: command.role).pause()
        case .resume: timer(for: command.role).resume()
        case .finish: if command.role == .secondary { deactivateSecondary() } else { timer(for: command.role).finish() }
        case .repeatLast: timer(for: command.role).repeatLastTimer()
        }
        publishWidgetSnapshots(reloadWidget: true)
    }

    func handleWidgetURL(_ url: URL) {
        guard url.scheme == "justabouttime" else { return }
        let components = url.pathComponents
        if url.host == "setup", let role = TimerRole(rawValue: components.dropFirst().first ?? "") {
            widgetSetupRole = role
            return
        }
        guard url.host == "timer", components.count >= 3, let role = TimerRole(rawValue: components[1]) else { return }
        if components[2] == "open" {
            widgetSetupRole = role
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        guard let token = query?.first(where: { $0.name == "session" })?.value, let sessionID = UUID(uuidString: token), sessionID == timer(for: role).sessionID else { return }
        let action: SharedTimerCommand.Action?
        if components[2] == "toggle" {
            action = timer(for: role).sharedSnapshot().availableActions.first
        } else {
            action = SharedTimerCommand.Action(rawValue: components[2])
        }
        if let action { applyWidgetCommand(SharedTimerCommand(role: role, sessionID: sessionID, action: action)) }
    }

    func consumeWidgetSetupRequest() -> TimerRole? {
        defer { widgetSetupRole = nil }
        return widgetSetupRole
    }

    func activateSecondary() {
        isSecondaryActivated = true
        publishWidgetSnapshots(reloadWidget: true)
    }

    func deactivateSecondary() {
        guard isSecondaryActivated else { return }
        secondaryTimer.deactivate()
        isSecondaryActivated = false
        publishWidgetSnapshots(reloadWidget: true)
    }

    func swapTimers() {
        guard isSecondaryActivated else { return }

        let newPrimary = secondaryTimer
        let newSecondary = primaryTimer
        newPrimary.assignRole(.primary)
        newSecondary.assignRole(.secondary)
        preferencesStore.swapTimerProfiles()
        orderedTimers = [newPrimary, newSecondary]
        publishWidgetSnapshots(reloadWidget: true)
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

    private func publishWidgetSnapshots(reloadWidget: Bool = false) {
        var snapshots: [TimerRole: SharedTimerSnapshot] = [.primary: primaryTimer.sharedSnapshot()]
        if isSecondaryActivated { snapshots[.secondary] = secondaryTimer.sharedSnapshot() }
        SharedTimerSnapshotStore.save(snapshots)
        if reloadWidget { reloadWidgets() }
    }

    private func observeTimers(_ timers: [TimerStore]) {
        for timer in timers {
            timer.widgetStateDidChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    self?.publishWidgetSnapshots(reloadWidget: true)
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
