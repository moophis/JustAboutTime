import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var timerStore = TimerStore()
    private let preferencesStore = PreferencesStore()

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
            if presentation.dotPhase == .leading {
                dot
            }

            Text(presentation.text)
                .monospacedDigit()

            if presentation.dotPhase == .trailing {
                dot
            }
        }
    }

    private var dot: some View {
        Circle()
            .frame(width: 6, height: 6)
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
