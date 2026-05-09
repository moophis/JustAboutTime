import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var notificationManager: NotificationManager

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PreferencesGroup(title: "COUNTDOWN") {
                    ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { index, _ in
                        PresetDurationRow(
                            title: "Preset \(index + 1)",
                            durationInMinutes: durationBinding(for: index)
                        )
                    }
                }

                PreferencesGroup(title: "SHORTCUTS") {
                    ForEach(preferencesStore.shortcutNames, id: \.rawValue) { name in
                        HStack(alignment: .firstTextBaseline) {
                            Text(AppShortcuts.title(for: name))
                                .font(.body.weight(.semibold))
                            Spacer()
                            KeyboardShortcuts.Recorder(for: name)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Conflicting or invalid shortcuts are rejected automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                PreferencesGroup(title: "NOTIFICATIONS") {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Alerts")
                                .font(.body.weight(.semibold))
                            Text(notificationManager.preferencesDetailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let errorText = notificationManager.preferencesErrorText {
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button(notificationManager.preferencesActionTitle) {
                            performNotificationAction()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
        .frame(minWidth: 520, minHeight: 420)
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            await notificationManager.refresh()
        }
    }

    private func performNotificationAction() {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            Task { await notificationManager.requestAuthorization() }
        case .denied:
            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(settingsURL)
            }
        case .authorized, .provisional, .ephemeral, .unknown:
            Task { await notificationManager.refresh() }
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

private struct PreferencesGroup<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PresetDurationRow: View {
    let title: String
    @Binding var durationInMinutes: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.body.weight(.semibold))
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
