import Testing
@testable import JustAboutTime

struct JustAboutTimeTests {
    @Test func appConfigurationDefinesExpectedDefaults() {
        #expect(AppConfiguration.appDisplayName == "Just About Time")
        #expect(AppConfiguration.menuBarSystemImage == "timer")
        #expect(AppConfiguration.toggleTimerShortcutName.rawValue == "toggleTimer")
    }
}
