import Combine
import KeyboardShortcuts

@MainActor
final class ShortcutManager: ObservableObject {
    struct Client {
        var onKeyUp: @MainActor (_ name: KeyboardShortcuts.Name, _ handler: @escaping @MainActor () -> Void) -> Void

        static let live = Self { name, handler in
            KeyboardShortcuts.onKeyUp(for: name) {
                handler()
            }
        }
    }

    private let timerStore: TimerStore
    private let client: Client

    init(timerStore: TimerStore, client: Client = .live) {
        self.timerStore = timerStore
        self.client = client
        registerHandlers()
    }

    private func registerHandlers() {
        client.onKeyUp(AppConfiguration.startPauseShortcutName) { [timerStore] in
            timerStore.toggleStartPause()
        }

        client.onKeyUp(AppConfiguration.restartShortcutName) { [timerStore] in
            timerStore.restart()
        }

        client.onKeyUp(AppConfiguration.finishShortcutName) { [timerStore] in
            timerStore.finish()
        }
    }
}
