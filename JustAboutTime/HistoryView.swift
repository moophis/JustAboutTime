import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    @ObservedObject var timerStore: TimerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let saveError = timerStore.latestHistoryError {
                HistoryErrorBanner(
                    title: "Latest Countdown Was Not Saved",
                    message: saveErrorMessage(for: saveError)
                )
            }

            Group {
                if let loadError = historyStore.latestLoadError {
                    ContentUnavailableView {
                        Label("History Unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadErrorMessage(for: loadError))
                    } actions: {
                        Button("Retry") {
                            historyStore.refresh()
                        }
                    }
                } else if historyStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No Completed Countdowns",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Finished countdowns show up here so you can review what you completed most recently.")
                    )
                } else {
                    Table(historyStore.entries) {
                        TableColumn("Duration") { entry in
                            Text(formattedDuration(entry.presetDuration))
                        }

                        TableColumn("Started") { entry in
                            Text(entry.startedAt, style: .time)
                        }

                        TableColumn("Completed") { entry in
                            Text(entry.completedAt, style: .time)
                        }

                        TableColumn("Date") { entry in
                            Text(entry.completedAt, style: .date)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 260)
        .task {
            historyStore.refresh()
        }
    }

    private func loadErrorMessage(for error: HistoryStore.HistoryError) -> String {
        switch error {
        case .unreadableExistingHistory:
            return "The saved history file could not be read. Fix or remove the file, then retry loading history."
        case .failedToPersistHistory:
            return "History could not be saved."
        }
    }

    private func saveErrorMessage(for error: HistoryStore.HistoryError) -> String {
        switch error {
        case .unreadableExistingHistory:
            return "The existing history file is unreadable, so the completed countdown could not be appended."
        case .failedToPersistHistory:
            return "The completed countdown finished, but writing the updated history file failed."
        }
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

private struct HistoryErrorBanner: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
