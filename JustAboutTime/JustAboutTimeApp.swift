import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var timerStore = TimerStore()

    var body: some Scene {
        MenuBarExtra(timerStore.statusPresentation.text, systemImage: AppConfiguration.menuBarSystemImage) {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)
    }
}
