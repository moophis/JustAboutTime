import Foundation

enum TimerStatusSnapshot: Equatable {
    case idle
    case countdown(remaining: TimeInterval, isRunning: Bool, isWarning: Bool)
    case countUp(elapsed: TimeInterval, isRunning: Bool, isOverdue: Bool)
    case countdownCompleted
}

enum DotPhase: Equatable {
    case hidden
    case leading
    case trailing
    case leadingRed
    case trailingRed
    case leadingSquare
    case leadingPause
}

struct TimerStatusPresentation: Equatable {
    let text: String
    let dotPhase: DotPhase
    var urgency: TimerUrgency = .neutral
}

enum TimerUrgency: Equatable {
    case neutral, warning, pausedWarning, overdue

    var opacity: Double {
        switch self {
        case .neutral: return 0
        case .warning, .pausedWarning: return 0.1
        case .overdue: return 1
        }
    }

    func opacity(at elapsed: TimeInterval, reduceMotion: Bool) -> Double {
        guard self == .warning, !reduceMotion else { return opacity }
        return 0.1 + 0.075 * (1 - cos(2 * .pi * elapsed / 3))
    }
}

struct TimerMenuStatusPresentation: Equatable {
    let text: String
    let accessibilityText: String

    static func make(
        timerRole: TimerRole,
        mode: TimerMode?,
        statusText: String,
        isRunning: Bool = false,
        isCompleted: Bool = false,
        isOvertime: Bool = false
    ) -> Self {
        guard let mode else {
            let stateText = isCompleted ? "Completed" : "Ready"
            return Self(
                text: stateText,
                accessibilityText: "\(timerRole.displayName) timer, \(stateText.lowercased())."
            )
        }

        let activityText = isRunning ? "running" : "paused"
        let statePrefix = isRunning ? "" : "Paused · "

        switch mode {
        case let .countdown(duration):
            let durationText = shortDuration(duration)
            return Self(
                text: "\(statePrefix)\(statusText) remaining · \(durationText) countdown",
                accessibilityText: "\(timerRole.displayName) timer, \(activityText), \(statusText) remaining, \(spokenDuration(duration)) countdown."
            )
        case .countUp:
            let unitText = isOvertime ? "overtime" : "elapsed"
            return Self(
                text: "\(statePrefix)\(statusText) \(unitText)",
                accessibilityText: "\(timerRole.displayName) timer, \(activityText), \(statusText) \(unitText)."
            )
        }
    }

    private static func shortDuration(_ duration: TimeInterval) -> String {
        let components = durationComponents(duration)
        var parts = [String]()
        if components.hours > 0 { parts.append("\(components.hours)h") }
        if components.minutes > 0 { parts.append("\(components.minutes)m") }
        if components.seconds > 0 || parts.isEmpty { parts.append("\(components.seconds)s") }
        return parts.joined(separator: " ")
    }

    private static func spokenDuration(_ duration: TimeInterval) -> String {
        let components = durationComponents(duration)
        var parts = [String]()
        if components.hours > 0 {
            parts.append("\(components.hours) \(components.hours == 1 ? "hour" : "hours")")
        }
        if components.minutes > 0 {
            parts.append("\(components.minutes) \(components.minutes == 1 ? "minute" : "minutes")")
        }
        if components.seconds > 0 || parts.isEmpty {
            parts.append("\(components.seconds) \(components.seconds == 1 ? "second" : "seconds")")
        }
        return parts.joined(separator: " ")
    }

    private static func durationComponents(_ duration: TimeInterval) -> (hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        return (
            hours: totalSeconds / 3600,
            minutes: (totalSeconds % 3600) / 60,
            seconds: totalSeconds % 60
        )
    }
}

struct StatusBarPresenter {
    func presentation(for snapshot: TimerStatusSnapshot, animationStep: Int) -> TimerStatusPresentation {
        switch snapshot {
        case .idle:
            return TimerStatusPresentation(text: format(0), dotPhase: .leadingSquare)
        case let .countdown(remaining, isRunning, isWarning):
            return TimerStatusPresentation(
                text: format(remaining),
                dotPhase: countdownDotPhase(isRunning: isRunning, isWarning: isWarning, animationStep: animationStep),
                urgency: isWarning ? (isRunning ? .warning : .pausedWarning) : .neutral
            )
        case let .countUp(elapsed, isRunning, isOverdue):
            return TimerStatusPresentation(
                text: format(elapsed),
                dotPhase: countUpDotPhase(isRunning: isRunning, isOverdue: isOverdue, animationStep: animationStep),
                urgency: isOverdue ? .overdue : .neutral
            )
        case .countdownCompleted:
            return TimerStatusPresentation(text: "00:00", dotPhase: .leadingSquare, urgency: .overdue)
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func countdownDotPhase(isRunning: Bool, isWarning: Bool, animationStep: Int) -> DotPhase {
        guard isRunning else {
            return .leadingPause
        }

        guard isWarning else {
            return dotPhase(isRunning: isRunning, animationStep: animationStep)
        }

        return redAlternatingDotPhase(animationStep: animationStep)
    }

    private func countUpDotPhase(isRunning: Bool, isOverdue: Bool, animationStep: Int) -> DotPhase {
        // Count-up is elapsed time, not a deadline: it never rotates the indicator.
        // Keep the ordinary running blink even when the associated countdown is overdue.
        guard isRunning else {
            return .leadingPause
        }
        return dotPhase(isRunning: true, animationStep: animationStep)
    }

    private func dotPhase(isRunning: Bool, animationStep: Int) -> DotPhase {
        guard isRunning else {
            return .hidden
        }

        return animationStep.isMultiple(of: 2) ? .leading : .hidden
    }

    private func redAlternatingDotPhase(animationStep: Int) -> DotPhase {
        animationStep.isMultiple(of: 2) ? .leadingRed : .trailingRed
    }

}
