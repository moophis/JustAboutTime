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

    static func title(for name: KeyboardShortcuts.Name) -> String {
        switch name {
        case startPauseTimer:
            return "Start or Pause Primary Timer"
        case restartTimer:
            return "Restart Primary Timer"
        case finishTimer:
            return "Finish Primary Timer"
        default:
            return name.rawValue
        }
    }
}
