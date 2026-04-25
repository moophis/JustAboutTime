import Combine
import Foundation

@MainActor
final class TimerStore: ObservableObject {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    @Published private(set) var activeSession: TimerSession?
    @Published private(set) var statusPresentation: StatusBarPresenter.Presentation

    private var stateMachine = TimerStateMachine()
    private let presenter: StatusBarPresenter
    private let now: @Sendable () -> Date
    private let sleep: Sleep
    private let tickInterval: Duration
    private var animationStep = 0
    private var tickTask: Task<Void, Never>?

    init(
        presenter: StatusBarPresenter = StatusBarPresenter(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        tickInterval: Duration = .seconds(1)
    ) {
        self.presenter = presenter
        self.now = now
        self.sleep = sleep
        self.tickInterval = tickInterval
        activeSession = nil
        statusPresentation = presenter.presentation(for: .idle, animationStep: 0)
    }

    func startCountdown(duration: TimeInterval) {
        send(.startCountdown(duration: duration, now: now()))
    }

    func startCountUp() {
        send(.startCountUp(now: now()))
    }

    func pause() {
        send(.pause(now: now()))
    }

    func resume() {
        send(.resume(now: now()))
    }

    func restart() {
        send(.restart(now: now()))
    }

    func finish() {
        send(.finish)
    }

    private func send(_ action: TimerStateMachine.Action) {
        _ = stateMachine.send(action)
        synchronizePresentation()
    }

    private func synchronizePresentation() {
        let session = stateMachine.session

        if session?.isRunning != true {
            animationStep = 0
        }

        activeSession = session
        statusPresentation = presenter.presentation(for: snapshot(for: session), animationStep: animationStep)
        updateTickTask(for: session)
    }

    private func snapshot(for session: TimerSession?) -> StatusBarPresenter.Snapshot {
        guard let session else {
            return .idle
        }

        switch session.phase {
        case .runningCountdown, .pausedCountdown:
            return .countdown(
                remaining: session.remainingTime(at: now()) ?? 0,
                isRunning: session.isRunning
            )
        case .runningCountUp, .pausedCountUp:
            return .countUp(
                elapsed: session.elapsedTime(at: now()),
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

            animationStep += 1
            _ = stateMachine.send(.tick(now: now()))
            synchronizePresentation()
        }

        tickTask = nil
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
