import Combine
import Foundation

@MainActor
final class TimerStore: ObservableObject {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private enum RepeatableStartMode: Equatable {
        case countdown(duration: TimeInterval)
        case countUp
    }

    enum Event: Equatable {
        case countdownCompleted
    }

    @Published private(set) var activeSession: TimerSession?
    @Published private(set) var statusPresentation: TimerStatusPresentation
    @Published private(set) var latestEvent: Event?
    @Published private(set) var latestHistoryError: HistoryStore.HistoryError?

    private var stateMachine = TimerStateMachine()
    private let presenter: StatusBarPresenter
    private let historyStore: HistoryStore
    private let notificationManager: NotificationManager
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private let tickInterval: Duration
    private var repeatableStartMode: RepeatableStartMode?
    private var animationStep = 0
    private var tickTask: Task<Void, Never>?

    init(
        presenter: StatusBarPresenter = StatusBarPresenter(),
        historyStore: HistoryStore = HistoryStore(),
        notificationManager: NotificationManager = NotificationManager(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        tickInterval: Duration = .seconds(1)
    ) {
        self.presenter = presenter
        self.historyStore = historyStore
        self.notificationManager = notificationManager
        self.now = now
        self.sleep = sleep
        self.tickInterval = tickInterval
        repeatableStartMode = nil
        activeSession = nil
        latestEvent = nil
        latestHistoryError = nil
        statusPresentation = presenter.presentation(for: .idle, animationStep: 0)
    }

    func startCountdown(duration: TimeInterval) {
        let currentTime = now()
        repeatableStartMode = .countdown(duration: duration)
        send(.startCountdown(duration: duration, now: currentTime), referenceTime: currentTime)
    }

    func startCountUp() {
        let currentTime = now()
        repeatableStartMode = .countUp
        send(.startCountUp(now: currentTime), referenceTime: currentTime)
    }

    func toggleStartPause() {
        let currentTime = now()

        guard let session = stateMachine.session else {
            startMostRecentMode(referenceTime: currentTime)
            return
        }

        switch session.phase {
        case .runningCountdown, .runningCountUp:
            send(.pause(now: currentTime), referenceTime: currentTime)
        case .pausedCountdown, .pausedCountUp:
            send(.resume(now: currentTime), referenceTime: currentTime)
        }
    }

    func pause() {
        let currentTime = now()
        send(.pause(now: currentTime), referenceTime: currentTime)
    }

    func resume() {
        let currentTime = now()
        send(.resume(now: currentTime), referenceTime: currentTime)
    }

    func restart() {
        let currentTime = now()
        send(.restart(now: currentTime), referenceTime: currentTime)
    }

    func finish() {
        send(.finish, referenceTime: now())
    }

    private func startMostRecentMode(referenceTime: Date) {
        guard let repeatableStartMode else {
            return
        }

        switch repeatableStartMode {
        case let .countdown(duration):
            send(.startCountdown(duration: duration, now: referenceTime), referenceTime: referenceTime)
        case .countUp:
            send(.startCountUp(now: referenceTime), referenceTime: referenceTime)
        }
    }

    private func send(_ action: TimerStateMachine.Action, referenceTime: Date) {
        let previousSession = stateMachine.session
        let events = stateMachine.send(action)
        persistHistoryIfNeeded(previousSession: previousSession, events: events, completedAt: referenceTime)
        notifyIfNeeded(previousSession: previousSession, events: events)
        synchronizePresentation(referenceTime: referenceTime, events: events)
    }

    private func notifyIfNeeded(previousSession: TimerSession?, events: [TimerStateMachine.Event]) {
        guard events.contains(.countdownCompleted),
              let duration = previousSession?.originalDuration else {
            return
        }

        Task { @MainActor [notificationManager] in
            await notificationManager.notifyCountdownCompleted(duration: duration)
        }
    }

    private func persistHistoryIfNeeded(
        previousSession: TimerSession?,
        events: [TimerStateMachine.Event],
        completedAt: Date
    ) {
        guard events.contains(.countdownCompleted),
              let session = previousSession,
              let presetDuration = session.originalDuration else {
            return
        }

        let result = historyStore.recordCompletedCountdown(
            presetDuration: presetDuration,
            startedAt: session.startedAt,
            completedAt: completedAt
        )

        switch result {
        case .success:
            latestHistoryError = nil
        case let .failure(error):
            latestHistoryError = error
        }
    }

    private func synchronizePresentation(referenceTime: Date, events: [TimerStateMachine.Event] = []) {
        let session = stateMachine.session

        if session?.isRunning != true {
            animationStep = 0
        }

        activeSession = session
        latestEvent = events.last.map(Event.init)
        statusPresentation = presenter.presentation(for: snapshot(for: session, referenceTime: referenceTime), animationStep: animationStep)
        updateTickTask(for: session)
    }

    private func snapshot(for session: TimerSession?, referenceTime: Date) -> TimerStatusSnapshot {
        guard let session else {
            return .idle
        }

        switch session.phase {
        case .runningCountdown, .pausedCountdown:
            return .countdown(
                remaining: session.remainingTime(at: referenceTime) ?? 0,
                isRunning: session.isRunning
            )
        case .runningCountUp, .pausedCountUp:
            return .countUp(
                elapsed: session.elapsedTime(at: referenceTime),
                isRunning: session.isRunning
            )
        }
    }

    private func updateTickTask(for session: TimerSession?) {
        guard session?.isRunning == true else {
            tickTask?.cancel()
            tickTask = nil
            return
        }

        guard tickTask == nil else {
            return
        }

        tickTask = Task { @MainActor [weak self] in
            await self?.runTickLoop()
        }
    }

    private func runTickLoop() async {
        while !Task.isCancelled {
            do {
                try await sleep(tickInterval)
            } catch is CancellationError {
                break
            } catch {
                break
            }

            guard !Task.isCancelled else {
                break
            }

            let currentTime = now()
            animationStep += 1
            let previousSession = stateMachine.session
            let events = stateMachine.send(.tick(now: currentTime))
            persistHistoryIfNeeded(previousSession: previousSession, events: events, completedAt: currentTime)
            notifyIfNeeded(previousSession: previousSession, events: events)
            synchronizePresentation(referenceTime: currentTime, events: events)
        }

        tickTask = nil
    }
}

private extension TimerStore.Event {
    init(_ event: TimerStateMachine.Event) {
        switch event {
        case .countdownCompleted:
            self = .countdownCompleted
        }
    }
}

private extension TimerSession {
    var isRunning: Bool {
        switch phase {
        case .runningCountdown, .runningCountUp:
            return true
        case .pausedCountdown, .pausedCountUp:
            return false
        }
    }
}
