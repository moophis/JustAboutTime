import Testing
@testable import JustAboutTime
import Foundation

struct JustAboutTimeTests {
    struct TestError: Error {}

    @Test func appConfigurationDefinesExpectedDefaults() {
        #expect(AppConfiguration.appDisplayName == "Just About Time")
        #expect(AppConfiguration.menuBarSystemImage == "timer")
        #expect(AppConfiguration.toggleTimerShortcutName.rawValue == "toggleTimer")
    }

    @Test func infoPlistEnablesAgentMode() throws {
        let plist = try projectDictionary(at: projectFilePath("JustAboutTime/Info.plist"))

        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
    }

    @Test func appEntrypointUsesMenuBarExtraWithoutWindowGroup() throws {
        let appSource = try source(at: projectFilePath("JustAboutTime/JustAboutTimeApp.swift"))

        #expect(appSource.contains("MenuBarExtra("))
        #expect(appSource.contains("WindowGroup") == false)
    }

    @Test func menuBarViewKeepsQuitPath() throws {
        let menuSource = try source(at: projectFilePath("JustAboutTime/MenuBarView.swift"))

        #expect(menuSource.contains("Button(\"Quit"))
        #expect(menuSource.contains("NSApplication.shared.terminate(nil)"))
    }

    @Test func projectKeepsKeyboardShortcutsPackageAndNoAppIconSetting() throws {
        let projectSource = try source(at: projectFilePath("JustAboutTime.xcodeproj/project.pbxproj"))

        #expect(projectSource.contains("https://github.com/sindresorhus/KeyboardShortcuts.git"))
        #expect(projectSource.contains("ASSETCATALOG_COMPILER_APPICON_NAME") == false)
    }

    private func projectFilePath(_ relativePath: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: relativePath)
    }

    private func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func projectDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw TestError()
        }
        return plist
    }
}
