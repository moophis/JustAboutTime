import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var historyStore: HistoryStore
    @StateObject private var timerStore: TimerStore
    @StateObject private var preferencesStore = PreferencesStore()

    init() {
        let historyStore = HistoryStore()
        _historyStore = StateObject(wrappedValue: historyStore)
        _timerStore = StateObject(wrappedValue: TimerStore(historyStore: historyStore))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerStore: timerStore, preferencesStore: preferencesStore)
        } label: {
            StatusBarLabelView(presentation: timerStore.statusPresentation)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: HistoryWindow.id) {
            HistoryView(historyStore: historyStore)
        }

        Settings {
            PreferencesView(preferencesStore: preferencesStore)
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
