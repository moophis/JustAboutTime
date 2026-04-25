import Foundation
import KeyboardShortcuts

final class PreferencesStore {
    enum PreferencesError: Error, Equatable {
        case invalidPresetCount(Int)
        case invalidPresetDuration(index: Int, value: TimeInterval)
    }

    private enum Storage {
        static let presetDurationsKey = "presetDurations"
    }

    private let userDefaults: UserDefaults

    private(set) var presetDurations: [TimeInterval]
    let shortcutNames: [KeyboardShortcuts.Name]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        presetDurations = Self.loadPresetDurations(from: userDefaults)
        shortcutNames = KeyboardShortcuts.Name.allCases
        persistPresetDurations(presetDurations)
    }

    func setPresetDurations(_ durations: [TimeInterval]) throws {
        let sanitizedDurations = try Self.validatePresetDurations(durations)
        presetDurations = sanitizedDurations
        persistPresetDurations(sanitizedDurations)
    }

    private func persistPresetDurations(_ durations: [TimeInterval]) {
        userDefaults.set(durations, forKey: Storage.presetDurationsKey)
    }

    private static func loadPresetDurations(from userDefaults: UserDefaults) -> [TimeInterval] {
        guard let storedValues = userDefaults.array(forKey: Storage.presetDurationsKey) else {
            return AppConfiguration.defaultPresetDurations
        }

        guard storedValues.count == AppConfiguration.defaultPresetDurations.count else {
            return AppConfiguration.defaultPresetDurations
        }

        var sanitizedDurations: [TimeInterval] = []
        sanitizedDurations.reserveCapacity(storedValues.count)

        for storedValue in storedValues {
            guard let duration = (storedValue as? NSNumber)?.doubleValue else {
                return AppConfiguration.defaultPresetDurations
            }

            guard duration.isFinite, duration >= AppConfiguration.minimumPresetDuration else {
                return AppConfiguration.defaultPresetDurations
            }

            let clampedDuration = min(duration, AppConfiguration.maximumPresetDuration)
            sanitizedDurations.append(clampedDuration)
        }

        return sanitizedDurations
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
