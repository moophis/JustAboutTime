import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var timerStore: TimerStore

    var body: some View {
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
