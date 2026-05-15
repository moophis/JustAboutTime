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
    @Published private(set) var statusText: String = "00:00"
    @Published private(set) var statusPresentation: TimerStatusPresentation
    @Published private(set) var countdownProgress: CountdownProgressPresentation?
    @Published private(set) var latestEvent: Event?
    @Published private(set) var latestHistoryError: HistoryStore.HistoryError?

    private var stateMachine = TimerStateMachine()
    private let presenter: StatusBarPresenter
    private let historyStore: HistoryStore
    private let notificationManager: NotificationManager
    private let preferencesStore: PreferencesStore
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private let tickInterval: Duration
    private var repeatableStartMode: RepeatableStartMode?
    private var animationStep = 0
    private var tickTaskGeneration = 0
    private var currentTickTaskGeneration: Int?
    private var tickTask: Task<Void, Never>?
    private var lastCompletedCountdownDuration: TimeInterval?
    private var isCountingUpAfterCountdown = false

    private(set) var wasSystemPaused = false

    init(
        presenter: StatusBarPresenter = StatusBarPresenter(),
        historyStore: HistoryStore = HistoryStore(),
        notificationManager: NotificationManager = NotificationManager(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        tickInterval: Duration = .seconds(1)
    ) {
        self.presenter = presenter
        self.historyStore = historyStore
        self.notificationManager = notificationManager
        self.preferencesStore = preferencesStore
        self.now = now
        self.sleep = sleep
        self.tickInterval = tickInterval
        repeatableStartMode = nil
        activeSession = nil
        countdownProgress = nil
        latestEvent = nil
        latestHistoryError = nil
        statusPresentation = presenter.presentation(for: .idle, animationStep: 0)
        loadLastTimerType()
    }

    private func loadLastTimerType() {
        guard let lastTimerType = preferencesStore.lastTimerType else {
            return
        }

        switch lastTimerType {
        case let .countdown(duration):
            repeatableStartMode = .countdown(duration: duration)
        case .countUp:
            repeatableStartMode = .countUp
        }
    }

    func systemPause() {
        let currentTime = now()
        guard let session = stateMachine.session, session.isRunning else { return }
        send(.pause(now: currentTime), referenceTime: currentTime)
        wasSystemPaused = true
    }

    func systemResume() {
        guard wasSystemPaused else { return }
        wasSystemPaused = false
        let currentTime = now()
        send(.resume(now: currentTime), referenceTime: currentTime)
    }

    func startCountdown(duration: TimeInterval) {
        wasSystemPaused = false
        isCountingUpAfterCountdown = false
        let currentTime = now()
        repeatableStartMode = .countdown(duration: duration)
        preferencesStore.setLastTimerType(.countdown(duration: duration))
        send(.startCountdown(duration: duration, now: currentTime), referenceTime: currentTime)
    }

    func startCountUp() {
        wasSystemPaused = false
        isCountingUpAfterCountdown = false
        let currentTime = now()
        repeatableStartMode = .countUp
        preferencesStore.setLastTimerType(.countUp)
        send(.startCountUp(now: currentTime), referenceTime: currentTime)
    }

    func toggleStartPause() {
        wasSystemPaused = false
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
        wasSystemPaused = false
        let currentTime = now()

        guard stateMachine.session != nil else {
            startMostRecentMode(referenceTime: currentTime)
            return
        }

        if isCountingUpAfterCountdown, let duration = lastCompletedCountdownDuration {
            send(.finish(now: currentTime), referenceTime: currentTime)
            startCountdown(duration: duration)
            return
        }

        send(.restart(now: currentTime), referenceTime: currentTime)
    }

    func finish() {
        wasSystemPaused = false
        isCountingUpAfterCountdown = false
        let currentTime = now()
        send(.finish(now: currentTime), referenceTime: currentTime)
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
        handleCountdownCompletion(previousSession: previousSession, events: events, referenceTime: referenceTime)
        persistHistoryIfNeeded(previousSession: previousSession, events: events, completedAt: referenceTime)
        notifyIfNeeded(previousSession: previousSession, events: events)
        synchronizePresentation(referenceTime: referenceTime, events: events)
    }

    private func handleCountdownCompletion(
        previousSession: TimerSession?,
        events: [TimerStateMachine.Event],
        referenceTime: Date
    ) {
        guard events.contains(.countdownCompleted) else {
            return
        }

        lastCompletedCountdownDuration = previousSession?.originalDuration
        guard preferencesStore.countUpAfterCountdown else {
            return
        }

        let countUpStartTime: Date
        if case let .runningCountdown(targetDate) = previousSession?.phase {
            countUpStartTime = targetDate
        } else {
            countUpStartTime = referenceTime
        }
        stateMachine.send(.startCountUp(now: countUpStartTime))
        isCountingUpAfterCountdown = true
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
        let isShowingCompletedDot = latestEvent == .countdownCompleted

        if !isShowingCompletedDot && session?.isRunning != true {
            animationStep = 0
        }

        activeSession = session
        if let lastEvent = events.last {
            latestEvent = Event(lastEvent)
        }
        let snapshot = snapshot(for: session, referenceTime: referenceTime)
        let presentation = presenter.presentation(for: snapshot, animationStep: animationStep)
        statusText = presentation.text
        statusPresentation = presentation
        countdownProgress = countdownProgress(for: session, referenceTime: referenceTime, animationStep: animationStep)
        updateTickTask(for: session)
    }

    private func countdownProgress(
        for session: TimerSession?,
        referenceTime: Date,
        animationStep: Int
    ) -> CountdownProgressPresentation? {
        if session != nil, isCountingUpAfterCountdown, lastCompletedCountdownDuration != nil {
            return dueCountdownProgress(animationStep: animationStep)
        }

        if session == nil, latestEvent == .countdownCompleted, let duration = lastCompletedCountdownDuration, duration > 0 {
            return dueCountdownProgress(animationStep: animationStep)
        }

        guard let session,
              let duration = session.originalDuration,
              duration > 0,
              let remaining = session.remainingTime(at: referenceTime) else {
            return nil
        }

        return CountdownProgressPresentation(
            fractionComplete: min(1, max(0, remaining / duration)),
            isWarning: isCountdownWarning(remaining: remaining, duration: duration)
        )
    }

    private func dueCountdownProgress(animationStep: Int) -> CountdownProgressPresentation {
        CountdownProgressPresentation(
            fractionComplete: 1.0,
            isWarning: true,
            isBlinking: true,
            isFillVisible: animationStep.isMultiple(of: 2)
        )
    }

    private func isCountdownWarning(remaining: TimeInterval, duration: TimeInterval) -> Bool {
        remaining <= duration * 0.1
    }

    private func snapshot(for session: TimerSession?, referenceTime: Date) -> TimerStatusSnapshot {
        if let session {
            switch session.phase {
            case .runningCountdown, .pausedCountdown:
                let remaining = session.remainingTime(at: referenceTime) ?? 0
                let duration = session.originalDuration ?? 0
                return .countdown(
                    remaining: remaining,
                    isRunning: session.isRunning,
                    isWarning: duration > 0 && isCountdownWarning(remaining: remaining, duration: duration)
                )
            case .runningCountUp, .pausedCountUp:
                return .countUp(
                    elapsed: session.elapsedTime(at: referenceTime),
                    isRunning: session.isRunning,
                    isOverdue: isCountingUpAfterCountdown
                )
            }
        }

        if latestEvent == .countdownCompleted {
            return .countdownCompleted
        }

        return .idle
    }

    private func updateTickTask(for session: TimerSession?) {
        let isShowingCompletedDot = latestEvent == .countdownCompleted

        if session?.isRunning == true {
            tickTask?.cancel()
            tickTask = nil
            currentTickTaskGeneration = nil
        }

        guard session?.isRunning == true || isShowingCompletedDot else {
            return
        }

        guard tickTask == nil else {
            return
        }

        tickTaskGeneration += 1
        let generation = tickTaskGeneration
        currentTickTaskGeneration = generation

        tickTask = Task { @MainActor [weak self] in
            await self?.runTickLoop(generation: generation)
        }
    }

    private func runTickLoop(generation: Int) async {
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
            handleCountdownCompletion(previousSession: previousSession, events: events, referenceTime: currentTime)
            persistHistoryIfNeeded(previousSession: previousSession, events: events, completedAt: currentTime)
            notifyIfNeeded(previousSession: previousSession, events: events)
            synchronizePresentation(referenceTime: currentTime, events: events)
        }

        guard currentTickTaskGeneration == generation else {
            return
        }

        tickTask = nil
        currentTickTaskGeneration = nil
    }
}

struct CountdownProgressPresentation: Equatable {
    let fractionComplete: Double
    let isWarning: Bool
    let isBlinking: Bool
    let isFillVisible: Bool

    init(
        fractionComplete: Double,
        isWarning: Bool,
        isBlinking: Bool = false,
        isFillVisible: Bool = true
    ) {
        self.fractionComplete = fractionComplete
        self.isWarning = isWarning
        self.isBlinking = isBlinking
        self.isFillVisible = isFillVisible
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
