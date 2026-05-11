import Foundation
import Testing

@testable import JustAboutTime

@MainActor
struct UpdateManagerTests {
    // MARK: - Version Comparison

    @Test func newerPatchVersion() {
        let manager = UpdateManager()
        #expect(manager.isVersion("1.0.3", newerThan: "1.0.2"))
    }

    @Test func newerMinorVersion() {
        let manager = UpdateManager()
        #expect(manager.isVersion("1.1.0", newerThan: "1.0.9"))
    }

    @Test func newerMajorVersion() {
        let manager = UpdateManager()
        #expect(manager.isVersion("2.0.0", newerThan: "1.9.9"))
    }

    @Test func sameVersionNotNewer() {
        let manager = UpdateManager()
        #expect(!manager.isVersion("1.0.2", newerThan: "1.0.2"))
    }

    @Test func olderVersionNotNewer() {
        let manager = UpdateManager()
        #expect(!manager.isVersion("1.0.1", newerThan: "1.0.2"))
    }

    @Test func vPrefixStripped() {
        let manager = UpdateManager()
        #expect(manager.isVersion("v1.0.3", newerThan: "1.0.2"))
    }

    @Test func vPrefixOnBoth() {
        let manager = UpdateManager()
        #expect(manager.isVersion("v1.0.3", newerThan: "v1.0.2"))
    }

    @Test func capitalVPrefix() {
        let manager = UpdateManager()
        #expect(manager.isVersion("V2.0.0", newerThan: "1.9.9"))
    }

    @Test func fewerComponentsInLatest() {
        let manager = UpdateManager()
        #expect(!manager.isVersion("1.0", newerThan: "1.0.2"))
    }

    @Test func fewerComponentsInCurrent() {
        let manager = UpdateManager()
        #expect(manager.isVersion("1.0.3", newerThan: "1.0"))
    }

    @Test func doubleDigitComponents() {
        let manager = UpdateManager()
        #expect(manager.isVersion("1.10.0", newerThan: "1.9.9"))
    }

    @Test func preReleaseSuffixIgnored() {
        let manager = UpdateManager()
        #expect(manager.isVersion("1.0.3-beta", newerThan: "1.0.2"))
    }
}
