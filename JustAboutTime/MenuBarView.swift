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

        restartSection

        Button {
            timerStore.finish()
        } label: {
            Label("Finish", systemImage: "checkmark.circle")
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

        return Button {
            if isRunning {
                timerStore.pause()
            } else {
                timerStore.resume()
            }
        } label: {
            Label(isRunning ? "Pause" : "Resume", systemImage: isRunning ? "pause.fill" : "play.fill")
        }
    }

    @ViewBuilder
    private var restartSection: some View {
        Text("Restart")
            .disabled(true)

        ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { _, duration in
            Button(indentedCountdownTitle(for: duration)) {
                timerStore.startCountdown(duration: duration)
            }
        }

        Button("  Count Up") {
            timerStore.startCountUp()
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
        Button {
            activateApp()
            openWindow(id: HistoryWindow.id)
            activateAppOnNextRunLoop()
        } label: {
            Label("Open History…", systemImage: "clock.arrow.circlepath")
        }
    }

    private var aboutButton: some View {
        Button {
            activateApp()
            openWindow(id: AboutWindow.id)
            activateAppOnNextRunLoop()
        } label: {
            Label("About JustAboutTime", systemImage: "info.circle")
        }
    }

    private var preferencesButton: some View {
        Button {
            activateApp()
            openSettings()
            activateAppOnNextRunLoop()
        } label: {
            Label("Preferences…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    private func countdownTitle(for duration: TimeInterval) -> String {
        "Start \(formattedDuration(duration)) Countdown"
    }

    private func indentedCountdownTitle(for duration: TimeInterval) -> String {
        "  \(formattedDuration(duration)) Countdown"
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if seconds > 0 {
                return minutes > 0 ? "\(hours)h \(minutes)m \(seconds)s" : "\(hours)h \(seconds)s"
            }
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
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
