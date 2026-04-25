import Foundation

enum TimerMode: Equatable {
    case countdown(duration: TimeInterval)
    case countUp

    var originalDuration: TimeInterval? {
        guard case let .countdown(duration) = self else {
            return nil
        }

        return duration
    }
}
