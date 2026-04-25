import AppKit
import KeyboardShortcuts
import SwiftUI
import UserNotifications

struct PreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @StateObject private var notificationPermissions = NotificationPermissionModel()

    var body: some View {
        Form {
            Section("Countdown Presets") {
                ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { index, _ in
                    PresetDurationRow(
                        title: "Preset \(index + 1)",
                        durationInMinutes: durationBinding(for: index)
                    )
                }
            }

            Section("Global Shortcuts") {
                ForEach(preferencesStore.shortcutNames, id: \.rawValue) { name in
                    HStack {
                        Text(AppShortcuts.title(for: name))
                        Spacer()
                        KeyboardShortcuts.Recorder(for: name)
                    }
                }
            }

            Section("Notifications") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alerts")
                        Text(notificationPermissions.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let action = notificationPermissions.action {
                        Button(action.title) {
                            action.handler()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 420, minHeight: 320)
        .task {
            await notificationPermissions.refresh()
        }
    }

    private func durationBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                Int((preferencesStore.presetDurations[index] / 60).rounded(.down))
            },
            set: { newValue in
                let clampedMinutes = max(1, min(newValue, 1_440))
                let updatedDurations = preferencesStore.presetDurations.enumerated().map { currentIndex, currentDuration in
                    currentIndex == index ? TimeInterval(clampedMinutes * 60) : currentDuration
                }

                try? preferencesStore.setPresetDurations(updatedDurations)
            }
        )
    }
}

private struct PresetDurationRow: View {
    let title: String
    @Binding var durationInMinutes: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Minutes", value: $durationInMinutes, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Stepper("", value: $durationInMinutes, in: 1...1_440)
                .labelsHidden()
            Text(durationLabel)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var durationLabel: String {
        let hours = durationInMinutes / 60
        let minutes = durationInMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }
}

@MainActor
private final class NotificationPermissionModel: ObservableObject {
    struct Action {
        let title: String
        let handler: () -> Void
    }

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined

    var detailText: String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "Notification access is enabled for countdown alerts."
        case .denied:
            return "Notification access is turned off. Open System Settings to enable alerts later."
        case .notDetermined:
            return "Countdown alerts are not allowed yet. Grant access so completed timers can notify you."
        @unknown default:
            return "Notification access status is unavailable."
        }
    }

    var action: Action? {
        switch status {
        case .notDetermined:
            return Action(title: "Allow Notifications") { [weak self] in
                Task { await self?.requestAuthorization() }
            }
        case .denied:
            return Action(title: "Open System Settings") {
                if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        case .authorized, .provisional, .ephemeral:
            return Action(title: "Refresh") { [weak self] in
                Task { await self?.refresh() }
            }
        @unknown default:
            return Action(title: "Refresh") { [weak self] in
                Task { await self?.refresh() }
            }
        }
    }

    func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = settings.authorizationStatus
    }

    private func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }
}
