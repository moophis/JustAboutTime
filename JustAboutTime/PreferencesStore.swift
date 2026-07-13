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
        static let secondaryPresetDurationsKey = "secondaryPresetDurations"
        static let lastTimerTypeKey = "lastTimerType"
        static let secondaryLastTimerTypeKey = "secondaryLastTimerType"
        static let openOnRestartKey = "openOnRestart"
        static let pauseOnScreenLockedKey = "pauseOnScreenLocked"
        static let resumeOnReloginKey = "resumeOnRelogin"
        static let countUpAfterCountdownKey = "countUpAfterCountdown"
    }

    private let userDefaults: UserDefaults
    private var isApplyingOpenOnRestart = false

    @Published private(set) var presetDurations: [TimeInterval]
    @Published private(set) var secondaryPresetDurations: [TimeInterval]
    @Published private(set) var lastTimerType: TimerMode?
    @Published private(set) var secondaryLastTimerType: TimerMode?
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
    @Published var countUpAfterCountdown: Bool {
        didSet { userDefaults.set(countUpAfterCountdown, forKey: Storage.countUpAfterCountdownKey) }
    }
    let shortcutNames: [KeyboardShortcuts.Name]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        presetDurations = Self.loadPresetDurations(from: userDefaults, key: Storage.presetDurationsKey)
        secondaryPresetDurations = Self.loadPresetDurations(from: userDefaults, key: Storage.secondaryPresetDurationsKey)
        lastTimerType = Self.loadLastTimerType(from: userDefaults, key: Storage.lastTimerTypeKey)
        secondaryLastTimerType = Self.loadLastTimerType(from: userDefaults, key: Storage.secondaryLastTimerTypeKey)
        openOnRestart = userDefaults.bool(forKey: Storage.openOnRestartKey)
        pauseOnScreenLocked = userDefaults.bool(forKey: Storage.pauseOnScreenLockedKey)
        resumeOnRelogin = userDefaults.bool(forKey: Storage.resumeOnReloginKey)
        countUpAfterCountdown = userDefaults.bool(forKey: Storage.countUpAfterCountdownKey)
        shortcutNames = AppShortcuts.allNames
        persistPresetDurations(presetDurations, for: .primary)
        persistPresetDurations(secondaryPresetDurations, for: .secondary)
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
        try setPresetDurations(durations, for: .primary)
    }

    func presetDurations(for role: TimerRole) -> [TimeInterval] {
        switch role {
        case .primary:
            return presetDurations
        case .secondary:
            return secondaryPresetDurations
        }
    }

    func setPresetDurations(_ durations: [TimeInterval], for role: TimerRole) throws {
        let sanitizedDurations = try Self.validatePresetDurations(durations)
        switch role {
        case .primary:
            presetDurations = sanitizedDurations
        case .secondary:
            secondaryPresetDurations = sanitizedDurations
        }
        persistPresetDurations(sanitizedDurations, for: role)
    }

    func shortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        KeyboardShortcuts.getShortcut(for: name)
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.setShortcut(shortcut, for: name)
    }

    func setLastTimerType(_ mode: TimerMode?) {
        setLastTimerType(mode, for: .primary)
    }

    func lastTimerType(for role: TimerRole) -> TimerMode? {
        switch role {
        case .primary:
            return lastTimerType
        case .secondary:
            return secondaryLastTimerType
        }
    }

    func setLastTimerType(_ mode: TimerMode?, for role: TimerRole) {
        switch role {
        case .primary:
            lastTimerType = mode
        case .secondary:
            secondaryLastTimerType = mode
        }
        persistLastTimerType(mode, for: role)
    }

    func swapTimerProfiles() {
        let primaryDurations = presetDurations
        let primaryLastTimerType = lastTimerType

        presetDurations = secondaryPresetDurations
        lastTimerType = secondaryLastTimerType
        secondaryPresetDurations = primaryDurations
        secondaryLastTimerType = primaryLastTimerType

        persistPresetDurations(presetDurations, for: .primary)
        persistPresetDurations(secondaryPresetDurations, for: .secondary)
        persistLastTimerType(lastTimerType, for: .primary)
        persistLastTimerType(secondaryLastTimerType, for: .secondary)
    }

    private func persistPresetDurations(_ durations: [TimeInterval], for role: TimerRole) {
        userDefaults.set(durations, forKey: presetDurationsKey(for: role))
    }

    private func persistLastTimerType(_ mode: TimerMode?, for role: TimerRole) {
        let key = lastTimerTypeKey(for: role)
        if let mode {
            switch mode {
            case let .countdown(duration):
                userDefaults.set(duration, forKey: key)
            case .countUp:
                userDefaults.set(0, forKey: key)
            }
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func presetDurationsKey(for role: TimerRole) -> String {
        role == .primary ? Storage.presetDurationsKey : Storage.secondaryPresetDurationsKey
    }

    private func lastTimerTypeKey(for role: TimerRole) -> String {
        role == .primary ? Storage.lastTimerTypeKey : Storage.secondaryLastTimerTypeKey
    }

    private static func loadPresetDurations(from userDefaults: UserDefaults, key: String) -> [TimeInterval] {
        guard let storedValues = userDefaults.array(forKey: key) else {
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

    private static func loadLastTimerType(from userDefaults: UserDefaults, key: String) -> TimerMode? {
        guard userDefaults.object(forKey: key) != nil else {
            return nil
        }

        let value = userDefaults.double(forKey: key)
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
