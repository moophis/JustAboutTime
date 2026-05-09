import AppKit
import KeyboardShortcuts
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore
    @ObservedObject var notificationManager: NotificationManager

    var body: some View {
        TabView {
            GeneralPreferencesView(preferencesStore: preferencesStore)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ShortcutPreferencesView(preferencesStore: preferencesStore)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            NotificationPreferencesView(notificationManager: notificationManager)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct GeneralPreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        PreferencesPage {
            PreferencesGroup(title: "COUNTDOWN") {
                ForEach(Array(preferencesStore.presetDurations.enumerated()), id: \.offset) { index, _ in
                    PresetDurationRow(
                        title: "Preset \(index + 1)",
                        duration: durationBinding(for: index)
                    )
                }
            }

            PreferencesGroup(title: "BEHAVIOR") {
                Toggle("Open on restart", isOn: $preferencesStore.openOnRestart)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Pause on screen locked", isOn: $preferencesStore.pauseOnScreenLocked)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("Resume on unlock", isOn: $preferencesStore.resumeOnRelogin)
                    .font(.body.weight(.semibold))
                    .disabled(!preferencesStore.pauseOnScreenLocked)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func durationBinding(for index: Int) -> Binding<TimeInterval> {
        Binding(
            get: {
                preferencesStore.presetDurations[index]
            },
            set: { newValue in
                let clampedDuration = max(AppConfiguration.minimumPresetDuration, min(newValue, AppConfiguration.maximumPresetDuration))
                let updatedDurations = preferencesStore.presetDurations.enumerated().map { currentIndex, currentDuration in
                    currentIndex == index ? clampedDuration : currentDuration
                }
                try? preferencesStore.setPresetDurations(updatedDurations)
            }
        )
    }
}

private struct ShortcutPreferencesView: View {
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        PreferencesPage {
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
        }
    }
}

private struct NotificationPreferencesView: View {
    @ObservedObject var notificationManager: NotificationManager

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PreferencesPage {
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
}

private struct PreferencesPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @Binding var duration: TimeInterval

    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var seconds: Int = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.body.weight(.semibold))
            Spacer()
            TextField("", value: $hours, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 32)
                .onChange(of: hours) { _, newValue in
                    let h = max(0, min(newValue, 24))
                    if h != newValue { hours = h }
                    duration = TimeInterval(h * 3600 + minutes * 60 + seconds)
                }
            Text("h")
                .foregroundStyle(.secondary)
            TextField("", value: $minutes, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 32)
                .onChange(of: minutes) { _, newValue in
                    let m = max(0, min(newValue, 59))
                    if m != newValue { minutes = m }
                    duration = TimeInterval(hours * 3600 + m * 60 + seconds)
                }
            Text("m")
                .foregroundStyle(.secondary)
            TextField("", value: $seconds, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 32)
                .onChange(of: seconds) { _, newValue in
                    let s = max(0, min(newValue, 59))
                    if s != newValue { seconds = s }
                    duration = TimeInterval(hours * 3600 + minutes * 60 + s)
                }
            Text("s")
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
            Text(durationLabel)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            updateComponents()
        }
        .onChange(of: duration) { _, _ in
            updateComponents()
        }
    }

    private func updateComponents() {
        let totalSeconds = Int(duration.rounded(.down))
        hours = totalSeconds / 3600
        minutes = (totalSeconds % 3600) / 60
        seconds = totalSeconds % 60
    }

    private var durationLabel: String {
        let totalSeconds = Int(duration.rounded(.down))
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60

        if h > 0 {
            if m > 0 && s > 0 {
                return "\(h)h \(m)m \(s)s"
            } else if m > 0 {
                return "\(h)h \(m)m"
            } else if s > 0 {
                return "\(h)h \(s)s"
            } else {
                return "\(h)h"
            }
        } else if m > 0 {
            if s > 0 {
                return "\(m)m \(s)s"
            } else {
                return "\(m)m"
            }
        } else {
            return "\(s)s"
        }
    }
}
