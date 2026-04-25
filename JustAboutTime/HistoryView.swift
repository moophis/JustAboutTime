import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore

    var body: some View {
        Group {
            if historyStore.entries.isEmpty {
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
        .padding(20)
        .frame(minWidth: 520, minHeight: 260)
        .task {
            _ = historyStore.loadEntries()
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
