import AppKit
import Combine
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var timerCoordinator: TimerCoordinator
    @ObservedObject var preferencesStore: PreferencesStore

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Section("Primary Timer") {
            TimerMenuStatusRows(timerStore: timerCoordinator.primaryTimer)
                .id(ObjectIdentifier(timerCoordinator.primaryTimer))
            timerSection(timer: timerCoordinator.primaryTimer, role: .primary)
        }

        Section("Secondary Timer") {
            if timerCoordinator.isSecondaryActivated {
                TimerMenuStatusRows(timerStore: timerCoordinator.secondaryTimer)
                    .id(ObjectIdentifier(timerCoordinator.secondaryTimer))
                timerSection(timer: timerCoordinator.secondaryTimer, role: .secondary)
            } else {
                Button {
                    timerCoordinator.activateSecondary()
                } label: {
                    Label("Activate Secondary Timer", systemImage: "plus.circle")
                }
                .keyboardShortcut("a", modifiers: [.option])
            }
        }

        Divider()
        aboutButton
        historyButton
        preferencesButton

        Divider()
        quitButton
    }

    @ViewBuilder
    private func timerSection(timer: TimerStore, role: TimerRole) -> some View {
        if timer.activeSession == nil {
            startActions(timer: timer, role: role)
        } else {
            activeActions(timer: timer, role: role)
        }

        if role == .secondary {
            Divider()
            if timer.activeSession == nil {
                Button {
                    timerCoordinator.deactivateSecondary()
                } label: {
                    Label("Deactivate Secondary Timer", systemImage: "minus.circle")
                }
                .keyboardShortcut("f", modifiers: [.option])
            }

            Button {
                timerCoordinator.swapTimers()
            } label: {
                Label("Swap Timers", systemImage: "arrow.up.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.option])
        }
    }

    @ViewBuilder
    private func startActions(timer: TimerStore, role: TimerRole) -> some View {
        ForEach(Array(preferencesStore.presetDurations(for: role).enumerated()), id: \.offset) { index, duration in
            Button(countdownTitle(for: duration)) {
                timer.startCountdown(duration: duration)
            }
            .keyboardShortcut(
                KeyEquivalent(Character(String(index + 1))),
                modifiers: shortcutModifiers(for: role)
            )
        }

        Button("Count Up") {
            timer.startCountUp()
        }
        .keyboardShortcut("4", modifiers: shortcutModifiers(for: role))
    }

    @ViewBuilder
    private func activeActions(timer: TimerStore, role: TimerRole) -> some View {
        pauseButton(timer: timer, role: role)

        Button("Restart") {
            timer.restart()
        }
        .keyboardShortcut("r", modifiers: shortcutModifiers(for: role))

        ForEach(Array(preferencesStore.presetDurations(for: role).enumerated()), id: \.offset) { index, duration in
            Button(indentedCountdownTitle(for: duration)) {
                timer.startCountdown(duration: duration)
            }
            .keyboardShortcut(
                KeyEquivalent(Character(String(index + 1))),
                modifiers: shortcutModifiers(for: role)
            )
        }

        Button("  Count Up") {
            timer.startCountUp()
        }
        .keyboardShortcut("4", modifiers: shortcutModifiers(for: role))

        Button {
            if role == .secondary {
                timerCoordinator.deactivateSecondary()
            } else {
                timer.finish()
            }
        } label: {
            Label("Finish", systemImage: "checkmark.circle")
        }
        .keyboardShortcut("f", modifiers: shortcutModifiers(for: role))
    }

    private func pauseButton(timer: TimerStore, role: TimerRole) -> some View {
        let isRunning = timer.activeSession?.isRunning == true

        return Button {
            if isRunning {
                timer.pause()
            } else {
                timer.resume()
            }
        } label: {
            Label(isRunning ? "Pause" : "Resume", systemImage: isRunning ? "pause.fill" : "play.fill")
        }
        .keyboardShortcut("p", modifiers: shortcutModifiers(for: role))
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

    private func shortcutModifiers(for role: TimerRole) -> EventModifiers {
        role == .secondary ? [.option] : []
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

@MainActor
private final class MenuTrackingMonitor: ObservableObject {
    static let shared = MenuTrackingMonitor()

    @Published private(set) var trackingDepth = 0

    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in
                self?.trackingDepth += 1
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                trackingDepth = max(0, trackingDepth - 1)
            }
            .store(in: &cancellables)
    }

    var isTracking: Bool {
        trackingDepth > 0
    }
}

@MainActor
private final class TimerMenuStatusObserver: ObservableObject {
    let timerStore: TimerStore

    @Published private(set) var refreshRevision = 0

    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var hasPendingRefresh = false

    init(timerStore: TimerStore) {
        self.timerStore = timerStore
        let trackingMonitor = MenuTrackingMonitor.shared

        timerStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
            .store(in: &cancellables)

        trackingMonitor.$trackingDepth
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] trackingDepth in
                guard trackingDepth == 0 else { return }
                self?.flushPendingRefresh()
            }
            .store(in: &cancellables)
    }

    private func scheduleRefresh() {
        guard refreshTask == nil else { return }

        refreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            refreshTask = nil

            if MenuTrackingMonitor.shared.isTracking {
                hasPendingRefresh = true
            } else {
                refreshRevision &+= 1
            }
        }
    }

    private func flushPendingRefresh() {
        guard hasPendingRefresh else { return }
        hasPendingRefresh = false
        refreshRevision &+= 1
    }
}

private struct TimerMenuStatusRows: View {
    @StateObject private var statusObserver: TimerMenuStatusObserver

    init(timerStore: TimerStore) {
        _statusObserver = StateObject(wrappedValue: TimerMenuStatusObserver(timerStore: timerStore))
    }

    private var timerStore: TimerStore {
        statusObserver.timerStore
    }

    private enum Layout {
        static let menuIconGutterWidth = 22.0
        static let progressSegmentCount = 24
        static let statusCharacterCount = 40
    }

    var body: some View {
        Text(statusLine)
            .font(.system(.body, design: .monospaced))
            .padding(.leading, -Layout.menuIconGutterWidth)
            .accessibilityLabel(unpaddedStatusLine)

        progressBar
            .padding(.leading, -Layout.menuIconGutterWidth)
    }

    private var statusLine: String {
        rightPadded(unpaddedStatusLine, to: Layout.statusCharacterCount)
    }

    private var unpaddedStatusLine: String {
        "\(summaryText) • \(stateText) • \(timerStore.statusText)"
    }

    private func rightPadded(_ text: String, to characterCount: Int) -> String {
        text + String(repeating: "\u{00A0}", count: max(0, characterCount - text.count))
    }

    @ViewBuilder
    private var progressBar: some View {
        let bar = Text(progressBarText)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .accessibilityLabel(progressAccessibilityLabel)

        if timerStore.countdownProgress?.fillStyle == .appIconGradient {
            bar.foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.44, blue: 1.0),
                        Color(red: 1.0, green: 0.25, blue: 0.82)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else if timerStore.countdownProgress?.isWarning == true {
            bar.foregroundStyle(.red)
        } else {
            bar.foregroundStyle(.secondary)
        }
    }

    private var progressBarText: String {
        guard let progress = timerStore.countdownProgress, progress.isFillVisible else {
            return String(repeating: "▱", count: Layout.progressSegmentCount)
        }

        let fraction = min(1, max(0, progress.fractionComplete))
        let filledCount = Int((fraction * Double(Layout.progressSegmentCount)).rounded())
        return String(repeating: "▰", count: filledCount) +
            String(repeating: "▱", count: Layout.progressSegmentCount - filledCount)
    }

    private var progressAccessibilityLabel: String {
        guard let progress = timerStore.countdownProgress else {
            return "No progress"
        }
        return "Progress \(Int((min(1, max(0, progress.fractionComplete)) * 100).rounded())) percent"
    }

    private var summaryText: String {
        guard let session = timerStore.activeSession else {
            return "Ready"
        }

        switch session.mode {
        case let .countdown(duration):
            return "Countdown • \(formattedDuration(duration))"
        case .countUp:
            return "Count Up"
        }
    }

    private var stateText: String {
        if let session = timerStore.activeSession {
            return session.isRunning ? "Running" : "Paused"
        }
        return timerStore.latestEvent == .countdownCompleted ? "Completed" : "Idle"
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
