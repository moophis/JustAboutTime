import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var updateManager: UpdateManager

    private let githubURL = URL(string: "https://github.com/moophis/JustAboutTime")!

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .frame(width: 64, height: 64)

            Text("JustAboutTime")
                .font(.title3.bold())

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            updateSection
                .font(.callout)

            Link("GitHub", destination: githubURL)
                .font(.callout)
        }
        .padding(24)
        .frame(width: 260)
    }

    @ViewBuilder
    private var updateSection: some View {
        switch updateManager.status {
        case .unknown:
            Button("Check for Updates\u{2026}") {
                updateManager.checkForUpdates()
            }
            .disabled(updateManager.isBusy)

        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("Checking for updates\u{2026}")
                    .foregroundStyle(.secondary)
            }

        case .upToDate:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("JustAboutTime is up to date.")
                    .foregroundStyle(.secondary)
            }
            Button("Check for Updates\u{2026}") {
                updateManager.checkForUpdates()
            }
            .disabled(updateManager.isBusy)

        case .updateAvailable(let version, let downloadURL):
            VStack(spacing: 8) {
                Text("New version \(version) available")
                    .foregroundStyle(.secondary)
                Button("Install & Restart") {
                    updateManager.downloadAndInstall(url: downloadURL)
                }
                .disabled(updateManager.isBusy)
            }

        case .downloading(let progress):
            VStack(spacing: 8) {
                ProgressView(value: progress) {
                    Text("Downloading\u{2026}")
                }
                .frame(width: 180)
                Text("\(Int(progress * 100))%")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

        case .downloadFailed(let message):
            VStack(spacing: 6) {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    updateManager.checkForUpdates()
                }
                .disabled(updateManager.isBusy)
            }

        case .checkFailed(let message):
            VStack(spacing: 6) {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    updateManager.checkForUpdates()
                }
                .disabled(updateManager.isBusy)
            }
        }
    }

    private var appVersion: String {
        Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.1"
    }
}
