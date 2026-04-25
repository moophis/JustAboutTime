import SwiftUI

@main
struct JustAboutTimeApp: App {
    var body: some Scene {
        MenuBarExtra(AppConfiguration.appDisplayName, systemImage: AppConfiguration.menuBarSystemImage) {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
