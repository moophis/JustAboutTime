import Foundation

struct TimerSession: Equatable {
    enum Phase: Equatable {
        case runningCountdown(targetDate: Date)
        case pausedCountdown(remaining: TimeInterval)
        case runningCountUp(startedAt: Date, accumulated: TimeInterval)
        case pausedCountUp(accumulated: TimeInterval)
    }

    let mode: TimerMode
    var phase: Phase

    var originalDuration: TimeInterval? {
        mode.originalDuration
    }

    func remainingTime(at now: Date) -> TimeInterval? {
        switch phase {
        case let .runningCountdown(targetDate):
            return max(0, targetDate.timeIntervalSince(now))
        case let .pausedCountdown(remaining):
            return max(0, remaining)
        case .runningCountUp, .pausedCountUp:
            return nil
        }
    }

    func elapsedTime(at now: Date) -> TimeInterval {
        switch phase {
        case let .runningCountdown(targetDate):
            guard let originalDuration else {
                return 0
            }

            return max(0, originalDuration - targetDate.timeIntervalSince(now))
        case let .pausedCountdown(remaining):
            guard let originalDuration else {
                return 0
            }

            return max(0, originalDuration - remaining)
        case let .runningCountUp(startedAt, accumulated):
            return accumulated + now.timeIntervalSince(startedAt)
        case let .pausedCountUp(accumulated):
            return accumulated
        }
    }
}
