import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let startPauseTimer = Self("startPauseTimer")
    static let restartTimer = Self("restartTimer")
    static let finishTimer = Self("finishTimer")
}

extension KeyboardShortcuts.Name: CaseIterable {
    public static let allCases: [Self] = [
        .startPauseTimer,
        .restartTimer,
        .finishTimer
    ]
}
