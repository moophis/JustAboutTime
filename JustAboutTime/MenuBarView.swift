import AppKit
import SwiftUI

struct MenuBarView: View {
    let timerStore: TimerStore

    var body: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
