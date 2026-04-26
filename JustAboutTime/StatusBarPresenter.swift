import Foundation

enum TimerStatusSnapshot: Equatable {
    case idle
    case countdown(remaining: TimeInterval, isRunning: Bool)
    case countUp(elapsed: TimeInterval, isRunning: Bool)
    case countdownCompleted
}

enum DotPhase: Equatable {
    case hidden
    case leading
    case trailing
    case leadingRed
}

struct TimerStatusPresentation: Equatable {
    let text: String
    let dotPhase: DotPhase
}

struct StatusBarPresenter {
    func presentation(for snapshot: TimerStatusSnapshot, animationStep: Int) -> TimerStatusPresentation {
        switch snapshot {
        case .idle:
            return TimerStatusPresentation(text: format(0), dotPhase: .hidden)
        case let .countdown(remaining, isRunning):
            return TimerStatusPresentation(text: format(remaining), dotPhase: dotPhase(isRunning: isRunning, animationStep: animationStep))
        case let .countUp(elapsed, isRunning):
            return TimerStatusPresentation(text: format(elapsed), dotPhase: dotPhase(isRunning: isRunning, animationStep: animationStep))
        case .countdownCompleted:
            let dotPhase: DotPhase = animationStep.isMultiple(of: 2) ? .leadingRed : .hidden
            return TimerStatusPresentation(text: "00:00", dotPhase: dotPhase)
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func dotPhase(isRunning: Bool, animationStep: Int) -> DotPhase {
        guard isRunning else {
            return .hidden
        }

        return animationStep.isMultiple(of: 2) ? .leading : .hidden
    }
}
