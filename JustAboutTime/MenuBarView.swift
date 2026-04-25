import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var timerStore: TimerStore
    let preferencesStore: PreferencesStore

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let session = timerStore.activeSession {
            activeMenu(for: session)
        } else {
            idleMenu
        }
    }

    @ViewBuilder
    private var idleMenu: some View {
        ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { index, duration in
            Button(countdownTitle(for: duration)) {
                timerStore.startCountdown(duration: duration)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [])
        }

        Button("Count Up") {
            timerStore.startCountUp()
        }

        Divider()
        historyButton
        SettingsLink {
            Text("Preferences…")
        }

        Divider()
        quitButton
    }

    @ViewBuilder
    private func activeMenu(for session: TimerSession) -> some View {
        Button(isRunning(session) ? "Pause" : "Resume") {
            if isRunning(session) {
                timerStore.pause()
            } else {
                timerStore.resume()
            }
        }

        Button("Restart") {
            timerStore.restart()
        }

        Button("Finish") {
            timerStore.finish()
        }

        Divider()
        Text(summaryTitle(for: session))
        Text(summarySubtitle(for: session))
            .foregroundStyle(.secondary)

        Divider()
        historyButton
        SettingsLink {
            Text("Preferences…")
        }

        Divider()
        quitButton
    }

    private var historyButton: some View {
        Button("Open History…") {
            openWindow(id: HistoryWindow.id)
        }
    }

    private var quitButton: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func countdownTitle(for duration: TimeInterval) -> String {
        "Start \(formattedDuration(duration)) Countdown"
    }

    private func summaryTitle(for session: TimerSession) -> String {
        switch session.mode {
        case let .countdown(duration):
            return "Countdown • \(formattedDuration(duration))"
        case .countUp:
            return "Count Up"
        }
    }

    private func summarySubtitle(for session: TimerSession) -> String {
        let status = isRunning(session) ? "Running" : "Paused"
        return "\(status) • \(timerStore.statusPresentation.text)"
    }

    private func isRunning(_ session: TimerSession) -> Bool {
        switch session.phase {
        case .runningCountdown, .runningCountUp:
            return true
        case .pausedCountdown, .pausedCountUp:
            return false
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration.rounded(.down)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}
