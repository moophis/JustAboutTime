import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var historyStore: HistoryStore
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var preferencesStore = PreferencesStore()
    @StateObject private var timerStore: TimerStore
    @StateObject private var shortcutManager: ShortcutManager

    init() {
        let historyStore = HistoryStore()
        let notificationManager = NotificationManager()
        let preferencesStore = PreferencesStore()
        let timerStore = TimerStore(historyStore: historyStore, notificationManager: notificationManager, preferencesStore: preferencesStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _timerStore = StateObject(wrappedValue: timerStore)
        _shortcutManager = StateObject(wrappedValue: ShortcutManager(timerStore: timerStore))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerStore: timerStore, preferencesStore: preferencesStore)
        } label: {
            StatusBarLabelView(presentation: timerStore.statusPresentation)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: HistoryWindow.id) {
            HistoryView(historyStore: historyStore, timerStore: timerStore)
        }

        Settings {
            PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)
        }
    }
}

enum HistoryWindow {
    static let id = "history"
}

private struct StatusBarLabelView: View {
    let presentation: TimerStatusPresentation

    var body: some View {
        HStack(spacing: 4) {
            dotSlot(isVisible: presentation.dotPhase == .leading)

            Text(presentation.text)
                .monospacedDigit()

            dotSlot(isVisible: presentation.dotPhase == .trailing)
        }
    }

    private func dotSlot(isVisible: Bool) -> some View {
        Circle()
            .frame(width: 6, height: 6)
            .opacity(isVisible ? 1 : 0)
    }
}
