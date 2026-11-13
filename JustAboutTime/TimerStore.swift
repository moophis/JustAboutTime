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

    struct HistoryFailure: Equatable {
        let timerRole: TimerRole
        let error: HistoryStore.HistoryError
    }

    private(set) var role: TimerRole
    private(set) var sessionID = UUID()
    let widgetStateDidChange = PassthroughSubject<Void, Never>()
    @Published private(set) var activeSession: TimerSession?
    @Published private(set) var statusText: String = "00:00"
    @Published private(set) var statusPresentation: TimerStatusPresentation
    @Published private(set) var countdownProgress: CountdownProgressPresentation?
    @Published private(set) var latestEvent: Event?
    @Published private(set) var latestHistoryFailure: HistoryFailure?

    var latestHistoryError: HistoryStore.HistoryError? {
        latestHistoryFailure?.error
    }

    var isOvertime: Bool {
        isCountingUpAfterCountdown
    }

    var isCompleted: Bool {
        latestEvent == .countdownCompleted || finishedCountdownDuration != nil
    }

    var canRepeatLastTimer: Bool {
        repeatableStartMode != nil
    }

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
    private var finishedCountdownDuration: TimeInterval?
    private var isCountingUpAfterCountdown = false

    private(set) var wasSystemPaused = false

    init(
        role: TimerRole = .primary,
        presenter: StatusBarPresenter = StatusBarPresenter(),
        historyStore: HistoryStore = HistoryStore(),
        notificationManager: NotificationManager = NotificationManager(),
        preferencesStore: PreferencesStore = PreferencesStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        tickInterval: Duration = .seconds(1)
    ) {
        self.role = role
        self.presenter = presenter
        self.historyStore = historyStore
        self.notificationManager = notificationManager
        self.preferencesStore = preferencesStore
        self.now = now
        self.sleep = sleep
        self.tickInterval = tickInterval
        repeatableStartMode = nil
        activeSession = nil
        countdownProgress = Self.hollowProgress
        latestEvent = nil
        latestHistoryFailure = nil
        statusPresentation = presenter.presentation(for: .idle, animationStep: 0)
        loadLastTimerType()
    }

    func sharedSnapshot(at now: Date? = nil) -> SharedTimerSnapshot {
      let now = now ?? self.now()
      let available = preferencesStore.lastTimerType(for: role) != nil
      guard let session = activeSession else {
        let duration = isCompleted ? (finishedCountdownDuration ?? lastCompletedCountdownDuration) : nil
        return SharedTimerSnapshot(role: role, sessionID: sessionID, state: isCompleted ? .due : .idle, mode: duration.map { .countdown(duration: $0) } ?? .countUp, startedAt: nil, targetDate: nil, frozenSeconds: 0, originalDuration: duration, lastUpdated: now, hasLastTimer: available)
      }
      let state: SharedTimerSnapshot.State
      let anchor: Date
      let target: Date?
      let frozen: TimeInterval?
      switch session.phase {
      case let .runningCountdown(targetDate):
        state = .running
        anchor = session.startedAt
        target = targetDate
        frozen = nil
      case let .pausedCountdown(remaining):
        state = .paused
        anchor = session.startedAt
        target = nil
        frozen = remaining
      case let .runningCountUp(startedAt, accumulated):
        state = isOvertime ? .overdue : .running
        anchor = startedAt.addingTimeInterval(-accumulated)
        target = nil
        frozen = nil
      case .pausedCountUp:
        state = isOvertime ? .overdue : .paused
        anchor = session.startedAt
        target = nil
        frozen = session.elapsedTime(at: now)
      }
      return SharedTimerSnapshot(role: role, sessionID: sessionID, state: state, mode: session.mode, startedAt: anchor, targetDate: target, frozenSeconds: frozen, originalDuration: session.originalDuration ?? (isOvertime ? lastCompletedCountdownDuration : nil), lastUpdated: now, hasLastTimer: available, sessionStartedAt: session.startedAt)
    }

    @discardableResult
    func restoreWidgetSnapshot(_ snapshot: SharedTimerSnapshot) -> Bool {
      guard snapshot.role == role, snapshot.isValidForRestoration else { return false }
      let phase: TimerSession.Phase?
      switch (snapshot.state, snapshot.mode) {
      case (.running, .countdown):
        phase = snapshot.targetDate.map { .runningCountdown(targetDate: $0) }
      case (.paused, .countdown):
        phase = snapshot.frozenSeconds.map { .pausedCountdown(remaining: $0) }
      case (.running, .countUp), (.overdue, .countUp):
        if let frozen = snapshot.frozenSeconds {
          phase = .pausedCountUp(accumulated: frozen)
        } else {
          phase = snapshot.startedAt.map { .runningCountUp(startedAt: $0, accumulated: 0) }
        }
      case (.paused, .countUp):
        phase = snapshot.frozenSeconds.map { .pausedCountUp(accumulated: $0) }
      default:
        phase = nil
      }
      let session = phase.map {
        TimerSession(startedAt: snapshot.sessionStartedAt ?? snapshot.startedAt ?? now(), mode: snapshot.mode, phase: $0)
      }
      stateMachine = TimerStateMachine(restoring: session)
      sessionID = snapshot.sessionID
      isCountingUpAfterCountdown = snapshot.state == .overdue
      lastCompletedCountdownDuration = isCountingUpAfterCountdown ? snapshot.originalDuration : nil
      finishedCountdownDuration = snapshot.state == .due ? snapshot.originalDuration : nil
      latestEvent = snapshot.state == .due ? .countdownCompleted : nil
      synchronizePresentation(referenceTime: now())
      return true
    }

    private func loadLastTimerType() {
        guard let lastTimerType = preferencesStore.lastTimerType(for: role) else {
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
        sessionID = UUID()
        wasSystemPaused = false
        finishedCountdownDuration = nil
        isCountingUpAfterCountdown = false
        let currentTime = now()
        repeatableStartMode = .countdown(duration: duration)
        preferencesStore.setLastTimerType(.countdown(duration: duration), for: role)
        send(.startCountdown(duration: duration, now: currentTime), referenceTime: currentTime)
    }

    func startCountUp() {
        sessionID = UUID()
        wasSystemPaused = false
        finishedCountdownDuration = nil
        isCountingUpAfterCountdown = false
        let currentTime = now()
        repeatableStartMode = .countUp
        preferencesStore.setLastTimerType(.countUp, for: role)
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

    func repeatLastTimer() {
        wasSystemPaused = false
        finishedCountdownDuration = nil
        isCountingUpAfterCountdown = false
        startMostRecentMode(referenceTime: now())
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
        sessionID = UUID()
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
        if activeSession != nil || isCompleted { sessionID = UUID() }
        wasSystemPaused = false
        finishedCountdownDuration = stateMachine.session?.originalDuration
        isCountingUpAfterCountdown = false
        let currentTime = now()
        send(.finish(now: currentTime), referenceTime: currentTime)
        latestEvent = nil
        synchronizePresentation(referenceTime: currentTime)
        widgetStateDidChange.send()
    }

    func deactivate() {
        finish()
        latestEvent = nil
        finishedCountdownDuration = nil
        lastCompletedCountdownDuration = nil
        isCountingUpAfterCountdown = false
        animationStep = 0
        synchronizePresentation(referenceTime: now())
        widgetStateDidChange.send()
    }

    func assignRole(_ role: TimerRole) {
        self.role = role
    }

    private func startMostRecentMode(referenceTime: Date) {
        guard let repeatableStartMode else {
            return
        }
        sessionID = UUID()

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
        if case .finish = action {
            // Finishing acknowledges completion instead of starting an overdue count-up.
        } else {
            handleCountdownCompletion(previousSession: previousSession, events: events, referenceTime: referenceTime)
        }
        persistHistoryIfNeeded(previousSession: previousSession, events: events, completedAt: referenceTime)
        notifyIfNeeded(previousSession: previousSession, events: events)
        synchronizePresentation(referenceTime: referenceTime, events: events)
        widgetStateDidChange.send()
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

        let timerRole = role
        Task { @MainActor [notificationManager] in
            await notificationManager.notifyCountdownCompleted(duration: duration, timerRole: timerRole)
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
            timerRole: role,
            presetDuration: presetDuration,
            startedAt: session.startedAt,
            completedAt: completedAt
        )

        switch result {
        case .success:
            latestHistoryFailure = nil
        case let .failure(error):
            latestHistoryFailure = HistoryFailure(timerRole: role, error: error)
        }
    }

    private func synchronizePresentation(referenceTime: Date, events: [TimerStateMachine.Event] = []) {
        let session = stateMachine.session
        let isShowingCompletedIndicator = latestEvent == .countdownCompleted || finishedCountdownDuration != nil

        if !isShowingCompletedIndicator && session?.isRunning != true {
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

        if session == nil {
            return Self.hollowProgress
        }

        guard let session,
              let duration = session.originalDuration else {
            return countUpProgress()
        }

        guard duration > 0,
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
            isBlinking: false,
            isFillVisible: true
        )
    }

    private func countUpProgress() -> CountdownProgressPresentation {
        CountdownProgressPresentation(
            fractionComplete: 1.0,
            isWarning: false,
            fillStyle: .appIconGradient
        )
    }

    private static var hollowProgress: CountdownProgressPresentation {
        CountdownProgressPresentation(
            fractionComplete: 1.0,
            isWarning: false,
            isBlinking: false,
            isFillVisible: false
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

        if finishedCountdownDuration != nil {
            return .idle
        }

        return .idle
    }

    private func updateTickTask(for session: TimerSession?) {
        if session?.isRunning == true {
            tickTask?.cancel()
            tickTask = nil
            currentTickTaskGeneration = nil
        }

        guard session?.isRunning == true else {
            tickTask?.cancel()
            tickTask = nil
            currentTickTaskGeneration = nil
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
            if !events.isEmpty { widgetStateDidChange.send() }
        }

        guard currentTickTaskGeneration == generation else {
            return
        }

        tickTask = nil
        currentTickTaskGeneration = nil
    }
}

enum ProgressFillStyle: Equatable {
    case solid
    case appIconGradient
}

struct CountdownProgressPresentation: Equatable {
    let fractionComplete: Double
    let isWarning: Bool
    let isBlinking: Bool
    let isFillVisible: Bool
    let fillStyle: ProgressFillStyle

    init(
        fractionComplete: Double,
        isWarning: Bool,
        isBlinking: Bool = false,
        isFillVisible: Bool = true,
        fillStyle: ProgressFillStyle = .solid
    ) {
        self.fractionComplete = fractionComplete
        self.isWarning = isWarning
        self.isBlinking = isBlinking
        self.isFillVisible = isFillVisible
        self.fillStyle = fillStyle
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
