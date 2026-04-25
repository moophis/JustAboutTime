import Foundation

struct TimerStateMachine: Equatable {
    enum State: Equatable {
        case idle
        case active(TimerSession)
    }

    enum Action: Equatable {
        case startCountdown(duration: TimeInterval, now: Date)
        case startCountUp(now: Date)
        case pause(now: Date)
        case resume(now: Date)
        case restart(now: Date)
        case finish(now: Date)
        case tick(now: Date)
    }

    enum Event: Equatable {
        case countdownCompleted
    }

    private(set) var state: State = .idle

    var session: TimerSession? {
        guard case let .active(session) = state else {
            return nil
        }

        return session
    }

    @discardableResult
    mutating func send(_ action: Action) -> [Event] {
        switch action {
        case let .startCountdown(duration, now):
            if duration <= 0 {
                state = .idle
                return [.countdownCompleted]
            }

            state = .active(
                TimerSession(
                    startedAt: now,
                    mode: .countdown(duration: duration),
                    phase: .runningCountdown(targetDate: now.addingTimeInterval(duration))
                )
            )
            return []

        case let .startCountUp(now):
            state = .active(TimerSession(startedAt: now, mode: .countUp, phase: .runningCountUp(startedAt: now, accumulated: 0)))
            return []

        case let .pause(now):
            guard case let .active(session) = state else {
                return []
            }

            switch session.phase {
            case let .runningCountdown(targetDate):
                let remaining = max(0, targetDate.timeIntervalSince(now))
                if remaining == 0 {
                    state = .idle
                    return [.countdownCompleted]
                }

                state = .active(TimerSession(startedAt: session.startedAt, mode: session.mode, phase: .pausedCountdown(remaining: remaining)))
                return []

            case let .runningCountUp(startedAt, accumulated):
                state = .active(
                    TimerSession(
                        startedAt: session.startedAt,
                        mode: session.mode,
                        phase: .pausedCountUp(accumulated: max(0, accumulated + max(0, now.timeIntervalSince(startedAt))))
                    )
                )
                return []

            case .pausedCountdown, .pausedCountUp:
                return []
            }

        case let .resume(now):
            guard case let .active(session) = state else {
                return []
            }

            switch session.phase {
            case let .pausedCountdown(remaining):
                state = .active(
                    TimerSession(
                        startedAt: session.startedAt,
                        mode: session.mode,
                        phase: .runningCountdown(targetDate: now.addingTimeInterval(remaining))
                    )
                )
                return []

            case let .pausedCountUp(accumulated):
                state = .active(
                    TimerSession(
                        startedAt: session.startedAt,
                        mode: session.mode,
                        phase: .runningCountUp(startedAt: now, accumulated: accumulated)
                    )
                )
                return []

            case .runningCountdown, .runningCountUp:
                return []
            }

        case let .restart(now):
            guard case let .active(session) = state else {
                return []
            }

            let events = overdueCompletionEvents(for: session, now: now)

            switch session.mode {
            case let .countdown(duration):
                state = .active(
                    TimerSession(
                        startedAt: now,
                        mode: session.mode,
                        phase: .runningCountdown(targetDate: now.addingTimeInterval(duration))
                    )
                )
            case .countUp:
                state = .active(TimerSession(startedAt: now, mode: .countUp, phase: .runningCountUp(startedAt: now, accumulated: 0)))
            }

            return events

        case let .finish(now):
            let events: [Event]
            if case let .active(session) = state {
                events = overdueCompletionEvents(for: session, now: now)
            } else {
                events = []
            }

            state = .idle
            return events

        case let .tick(now):
            guard case let .active(session) = state else {
                return []
            }

            switch session.phase {
            case let .runningCountdown(targetDate) where targetDate <= now:
                state = .idle
                return [.countdownCompleted]
            case .runningCountdown, .pausedCountdown, .runningCountUp, .pausedCountUp:
                return []
            }
        }
    }

    private func overdueCompletionEvents(for session: TimerSession, now: Date) -> [Event] {
        switch session.phase {
        case let .runningCountdown(targetDate) where targetDate <= now:
            return [.countdownCompleted]
        case .runningCountdown, .pausedCountdown, .runningCountUp, .pausedCountUp:
            return []
        }
    }
}
