import Combine
import Foundation
import KeyboardShortcuts

@MainActor
final class PreferencesStore: ObservableObject {
    enum PreferencesError: Error, Equatable {
        case invalidPresetCount(Int)
        case invalidPresetDuration(index: Int, value: TimeInterval)
    }

    private enum Storage {
        static let presetDurationsKey = "presetDurations"
        static let lastTimerTypeKey = "lastTimerType"
    }

    private let userDefaults: UserDefaults

    @Published private(set) var presetDurations: [TimeInterval]
    @Published var lastTimerType: TimerMode?
    let shortcutNames: [KeyboardShortcuts.Name]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        presetDurations = Self.loadPresetDurations(from: userDefaults)
        lastTimerType = Self.loadLastTimerType(from: userDefaults)
        shortcutNames = AppShortcuts.allNames
        persistPresetDurations(presetDurations)
    }

    func setPresetDurations(_ durations: [TimeInterval]) throws {
        let sanitizedDurations = try Self.validatePresetDurations(durations)
        presetDurations = sanitizedDurations
        persistPresetDurations(sanitizedDurations)
    }

    func shortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.setShortcut(shortcut, for: name)
    }

    func setLastTimerType(_ mode: TimerMode?) {
        lastTimerType = mode
        persistLastTimerType(mode)
    }

    private func persistPresetDurations(_ durations: [TimeInterval]) {
        userDefaults.set(durations, forKey: Storage.presetDurationsKey)
    }

    private func persistLastTimerType(_ mode: TimerMode?) {
        if let mode {
            switch mode {
            case let .countdown(duration):
                userDefaults.set(duration, forKey: Storage.lastTimerTypeKey)
            case .countUp:
                userDefaults.set(0, forKey: Storage.lastTimerTypeKey)
            }
        } else {
            userDefaults.removeObject(forKey: Storage.lastTimerTypeKey)
        }
    }

    private static func loadPresetDurations(from userDefaults: UserDefaults) -> [TimeInterval] {
        guard let storedValues = userDefaults.array(forKey: Storage.presetDurationsKey) else {
            return AppConfiguration.defaultPresetDurations
        }

        var sanitizedDurations = AppConfiguration.defaultPresetDurations

        for index in sanitizedDurations.indices {
            guard index < storedValues.count else {
                break
            }

            guard let duration = (storedValues[index] as? NSNumber)?.doubleValue else {
                continue
            }

            guard duration.isFinite, duration >= AppConfiguration.minimumPresetDuration else {
                continue
            }

            sanitizedDurations[index] = min(duration, AppConfiguration.maximumPresetDuration)
        }

        return sanitizedDurations
    }

    private static func loadLastTimerType(from userDefaults: UserDefaults) -> TimerMode? {
        guard userDefaults.object(forKey: Storage.lastTimerTypeKey) != nil else {
            return nil
        }

        let value = userDefaults.double(forKey: Storage.lastTimerTypeKey)
        if value > 0 {
            return .countdown(duration: value)
        } else {
            return .countUp
        }
    }

    private static func validatePresetDurations(_ durations: [TimeInterval]) throws -> [TimeInterval] {
        guard durations.count == AppConfiguration.defaultPresetDurations.count else {
            throw PreferencesError.invalidPresetCount(durations.count)
        }

        return try durations.enumerated().map { index, duration in
            guard duration.isFinite, duration >= AppConfiguration.minimumPresetDuration else {
                throw PreferencesError.invalidPresetDuration(index: index, value: duration)
            }

            return min(duration, AppConfiguration.maximumPresetDuration)
        }
    }
}
