import Foundation

struct StatusBarPresenter {
    enum Snapshot: Equatable {
        case idle
        case countdown(remaining: TimeInterval, isRunning: Bool)
        case countUp(elapsed: TimeInterval, isRunning: Bool)
    }

    struct Presentation: Equatable {
        enum DotPhase: Equatable {
            case hidden
            case leading
            case trailing
        }

        let text: String
        let dotPhase: DotPhase
    }

    func presentation(for snapshot: Snapshot, animationStep: Int) -> Presentation {
        switch snapshot {
        case .idle:
            return Presentation(text: format(0), dotPhase: .hidden)
        case let .countdown(remaining, isRunning):
            return Presentation(text: format(remaining), dotPhase: dotPhase(isRunning: isRunning, animationStep: animationStep))
        case let .countUp(elapsed, isRunning):
            return Presentation(text: format(elapsed), dotPhase: dotPhase(isRunning: isRunning, animationStep: animationStep))
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func dotPhase(isRunning: Bool, animationStep: Int) -> Presentation.DotPhase {
        guard isRunning else {
            return .hidden
        }

        return animationStep.isMultiple(of: 2) ? .leading : .trailing
    }
}
