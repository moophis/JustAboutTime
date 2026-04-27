import KeyboardShortcuts
import Foundation

enum AppConfiguration {
    static let appDisplayName = "Just About Time"
    static let menuBarSystemImage = "timer"
    static let defaultPresetDurations: [TimeInterval] = [5 * 60, 25 * 60, 45 * 60]
    static let minimumPresetDuration: TimeInterval = 1
    static let maximumPresetDuration: TimeInterval = 24 * 60 * 60
    static let startPauseShortcutName = AppShortcuts.startPauseTimer
    static let restartShortcutName = AppShortcuts.restartTimer
    static let finishShortcutName = AppShortcuts.finishTimer
}
