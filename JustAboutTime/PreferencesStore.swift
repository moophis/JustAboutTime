import Combine
import Foundation
import KeyboardShortcuts
import ServiceManagement

@MainActor
final class PreferencesStore: ObservableObject {
    enum PreferencesError: Error, Equatable {
        case invalidPresetCount(Int)
        case invalidPresetDuration(index: Int, value: TimeInterval)
    }

    private enum Storage {
        static let presetDurationsKey = "presetDurations"
        static let lastTimerTypeKey = "lastTimerType"
        static let openOnRestartKey = "openOnRestart"
        static let pauseOnScreenLockedKey = "pauseOnScreenLocked"
        static let resumeOnReloginKey = "resumeOnRelogin"
    }

    private let userDefaults: UserDefaults
    private var isApplyingOpenOnRestart = false

    @Published private(set) var presetDurations: [TimeInterval]
    @Published var lastTimerType: TimerMode?
    @Published var openOnRestart: Bool {
        didSet {
            userDefaults.set(openOnRestart, forKey: Storage.openOnRestartKey)
            guard !isApplyingOpenOnRestart else {
                return
            }

            applyOpenOnRestart()
        }
    }
    @Published var pauseOnScreenLocked: Bool {
        didSet { userDefaults.set(pauseOnScreenLocked, forKey: Storage.pauseOnScreenLockedKey) }
    }
    @Published var resumeOnRelogin: Bool {
        didSet { userDefaults.set(resumeOnRelogin, forKey: Storage.resumeOnReloginKey) }
    }
    let shortcutNames: [KeyboardShortcuts.Name]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        presetDurations = Self.loadPresetDurations(from: userDefaults)
        lastTimerType = Self.loadLastTimerType(from: userDefaults)
        openOnRestart = userDefaults.bool(forKey: Storage.openOnRestartKey)
        pauseOnScreenLocked = userDefaults.bool(forKey: Storage.pauseOnScreenLockedKey)
        resumeOnRelogin = userDefaults.bool(forKey: Storage.resumeOnReloginKey)
        shortcutNames = AppShortcuts.allNames
        persistPresetDurations(presetDurations)
    }

    private func applyOpenOnRestart() {
        isApplyingOpenOnRestart = true
        defer { isApplyingOpenOnRestart = false }

        do {
            if openOnRestart {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            openOnRestart = (SMAppService.mainApp.status == .enabled)
            userDefaults.set(openOnRestart, forKey: Storage.openOnRestartKey)
        }
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
