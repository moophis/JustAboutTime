import AppKit
import SwiftUI

struct AboutView: View {
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

            Link("GitHub", destination: githubURL)
        }
        .padding(24)
        .frame(width: 220)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }
}
