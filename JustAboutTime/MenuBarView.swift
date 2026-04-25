import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Text("No timers yet")

        KeyboardShortcuts.Recorder("Toggle Timer Shortcut", name: AppConfiguration.toggleTimerShortcutName)

        Divider()

        Button("Quit \(AppConfiguration.appDisplayName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
