import Foundation
import Sparkle
import Testing

@testable import JustAboutTime

struct UpdateManagerTests {
    @Test func noUpdateIsSuccessful() {
        let error = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))

        #expect(UpdateManager.status(for: error) == .upToDate)
    }

    @Test func genuineErrorsRemainFailures() {
        let error = NSError(domain: SUSparkleErrorDomain, code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Connection failed"])

        #expect(UpdateManager.status(for: error) == .failed("Connection failed"))
    }

    @Test func matchingCodeFromAnotherDomainRemainsFailure() {
        let error = NSError(domain: NSURLErrorDomain, code: Int(SUError.noUpdateError.rawValue),
                            userInfo: [NSLocalizedDescriptionKey: "Network error"])

        #expect(UpdateManager.status(for: error) == .failed("Network error"))
    }

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
