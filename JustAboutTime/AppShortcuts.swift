import KeyboardShortcuts

enum AppShortcuts {
    static let startPauseTimer = KeyboardShortcuts.Name("startPauseTimer")
    static let restartTimer = KeyboardShortcuts.Name("restartTimer")
    static let finishTimer = KeyboardShortcuts.Name("finishTimer")

    static let allNames: [KeyboardShortcuts.Name] = [
        startPauseTimer,
        restartTimer,
        finishTimer
    ]
}
