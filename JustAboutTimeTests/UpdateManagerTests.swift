import Foundation
import Testing

struct UpdateManagerTests {
    @Test func updaterUsesSparkleInsteadOfCustomInstaller() throws {
        let source = try String(contentsOf: updateManagerSourceURL, encoding: .utf8)

        #expect(source.contains("SPUStandardUpdaterController"))
        #expect(source.contains("checkForUpdatesInBackground"))
        #expect(!source.contains("api.github.com"))
        #expect(!source.contains("hdiutil"))
        #expect(!source.contains("rsync"))
    }

    private var updateManagerSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("JustAboutTime/UpdateManager.swift")
    }
}
