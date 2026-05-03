import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var timerStore: TimerStore
    @ObservedObject var preferencesStore: PreferencesStore

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if timerStore.activeSession != nil {
            activeMenu
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
        aboutButton
        historyButton
        preferencesButton

        Divider()
        quitButton
    }

    @ViewBuilder
    private var activeMenu: some View {
        pauseButton

        Button("Restart") {
            timerStore.restart()
        }

        Button("Finish") {
            timerStore.finish()
        }

        Divider()
        timerInfo
        StableTimerStatusView(timerStore: timerStore)

        Divider()
        aboutButton
        historyButton
        preferencesButton

        Divider()
        quitButton
    }

    private var pauseButton: some View {
        let isRunning = timerStore.activeSession.map { session in
            switch session.phase {
            case .runningCountdown, .runningCountUp:
                return true
            case .pausedCountdown, .pausedCountUp:
                return false
            }
        } ?? false

        return Button(isRunning ? "Pause" : "Resume") {
            if isRunning {
                timerStore.pause()
            } else {
                timerStore.resume()
            }
        }
    }

    private var timerInfo: some View {
        Group {
            if let session = timerStore.activeSession {
                switch session.mode {
                case let .countdown(duration):
                    Text("Countdown • \(formattedDuration(duration))")
                case .countUp:
                    Text("Count Up")
                }
            }
        }
    }

    private var historyButton: some View {
        Button("Open History…") {
            activateApp()
            openWindow(id: HistoryWindow.id)
            activateAppOnNextRunLoop()
        }
    }

    private var aboutButton: some View {
        Button("About JustAboutTime") {
            activateApp()
            openWindow(id: AboutWindow.id)
            activateAppOnNextRunLoop()
        }
    }

    private var preferencesButton: some View {
        Button("Preferences…") {
            activateApp()
            openSettings()
            activateAppOnNextRunLoop()
        }
        .keyboardShortcut(",")
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

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration.rounded(.down)) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func activateAppOnNextRunLoop() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct StableTimerStatusView: NSViewRepresentable {
    @ObservedObject var timerStore: TimerStore

    func makeCoordinator() -> Coordinator {
        Coordinator(timerStore: timerStore)
    }

    func makeNSView(context: Context) -> NSView {
        let view = StableStatusTextView()
        context.coordinator.textView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateStatusText()
    }

    @MainActor
    class Coordinator: NSObject {
        let timerStore: TimerStore
        weak var textView: StableStatusTextView?

        init(timerStore: TimerStore) {
            self.timerStore = timerStore
            super.init()
        }

        func updateStatusText() {
            let isRunning = timerStore.activeSession.map { session in
                switch session.phase {
                case .runningCountdown, .runningCountUp:
                    return true
                case .pausedCountdown, .pausedCountUp:
                    return false
                }
            } ?? false

            let status = isRunning ? "Running" : "Paused"
            textView?.updateText("\(status) • \(timerStore.statusText)")
        }
    }
}

@MainActor
private class StableStatusTextView: NSView {
    private let textField: NSTextField

    override init(frame frameRect: NSRect) {
        textField = NSTextField(labelWithString: "")
        textField.textColor = .secondaryLabelColor
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        super.init(frame: frameRect)
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateText(_ text: String) {
        textField.stringValue = text
    }
}
