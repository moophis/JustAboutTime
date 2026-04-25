import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var timerStore = TimerStore()
    @StateObject private var preferencesStore = PreferencesStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerStore: timerStore, preferencesStore: preferencesStore)
        } label: {
            StatusBarLabelView(presentation: timerStore.statusPresentation)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: HistoryWindow.id) {
            PlaceholderWindowView(
                title: "History",
                message: "History view arrives in Task 7. This window exists so the menu entry point is already wired."
            )
            .frame(minWidth: 320, minHeight: 180)
        }

        Settings {
            PlaceholderWindowView(
                title: "Preferences",
                message: "Preferences UI arrives in Task 7. This window exists so the menu entry point is already wired."
            )
            .frame(minWidth: 360, minHeight: 220)
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

private struct PlaceholderWindowView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
    }
}
