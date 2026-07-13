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

    private let timerCoordinator: TimerCoordinator
    private let client: Client

    init(timerCoordinator: TimerCoordinator, client: Client = .live) {
        self.timerCoordinator = timerCoordinator
        self.client = client
        registerHandlers()
    }

    private func registerHandlers() {
        client.onKeyUp(AppConfiguration.startPauseShortcutName) { [timerCoordinator] in
            timerCoordinator.primaryTimer.toggleStartPause()
        }

        client.onKeyUp(AppConfiguration.restartShortcutName) { [timerCoordinator] in
            timerCoordinator.primaryTimer.restart()
        }

        client.onKeyUp(AppConfiguration.finishShortcutName) { [timerCoordinator] in
            timerCoordinator.primaryTimer.finish()
        }
    }
}
