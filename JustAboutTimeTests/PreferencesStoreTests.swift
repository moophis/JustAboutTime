import Combine
import Foundation
import KeyboardShortcuts
import Testing

@testable import JustAboutTime

@MainActor
struct PreferencesStoreTests {
    @Test func presetDurationsArePublishedWhenChanged() async throws {
        let userDefaults = makeUserDefaults()
        let store = PreferencesStore(userDefaults: userDefaults)
        let stream = AsyncStream.makeStream(of: [TimeInterval].self)
        var cancellables = Set<AnyCancellable>()
        var iterator = stream.stream.makeAsyncIterator()

        store.$presetDurations
            .dropFirst()
            .sink { durations in
                stream.continuation.yield(durations)
            }
            .store(in: &cancellables)

        try store.setPresetDurations([60, 120, 180])

        let publishedDurations = try #require(await iterator.next())

        #expect(publishedDurations == [60, 120, 180])
    }

    @Test func firstLaunchLoadsDefaultPresetDurations() {
        let userDefaults = makeUserDefaults()
        let store = PreferencesStore(userDefaults: userDefaults)

        #expect(store.presetDurations == AppConfiguration.defaultPresetDurations)
        #expect(storedPresetDurations(in: userDefaults) == AppConfiguration.defaultPresetDurations)
        #expect(store.shortcutNames.map(\.rawValue) == ["startPauseTimer", "restartTimer", "finishTimer"])
    }

    @Test func shortcutsRoundTripAcrossStoreReloads() {
        resetShortcuts()
        defer { resetShortcuts() }

        let firstLaunchStore = PreferencesStore(userDefaults: makeUserDefaults())
        let shortcut = KeyboardShortcuts.Shortcut(.a, modifiers: [.command, .option])

        firstLaunchStore.setShortcut(shortcut, for: AppConfiguration.startPauseShortcutName)

        let relaunchedStore = PreferencesStore(userDefaults: makeUserDefaults())

        #expect(relaunchedStore.shortcut(for: AppConfiguration.startPauseShortcutName) == shortcut)
        #expect(KeyboardShortcuts.getShortcut(for: AppConfiguration.startPauseShortcutName) == shortcut)
    }

    @Test func editedPresetDurationsPersistAcrossStoreReloads() throws {
        let userDefaults = makeUserDefaults()
        let firstLaunchStore = PreferencesStore(userDefaults: userDefaults)

        try firstLaunchStore.setPresetDurations([60, 120, 180])

        let relaunchedStore = PreferencesStore(userDefaults: userDefaults)

        #expect(relaunchedStore.presetDurations == [60, 120, 180])
        #expect(storedPresetDurations(in: userDefaults) == [60, 120, 180])
    }

    @Test func oversizedPresetDurationsClampBeforePersisting() throws {
        let userDefaults = makeUserDefaults()
        let store = PreferencesStore(userDefaults: userDefaults)

        try store.setPresetDurations([60, 120, 90_000])

        #expect(store.presetDurations == [60, 120, AppConfiguration.maximumPresetDuration])
        #expect(storedPresetDurations(in: userDefaults) == [60, 120, AppConfiguration.maximumPresetDuration])
    }

    @Test func invalidPresetDurationsAreRejectedWithoutCorruptingStoredValues() throws {
        let userDefaults = makeUserDefaults()
        let store = PreferencesStore(userDefaults: userDefaults)
        try store.setPresetDurations([60, 120, 180])

        #expect(throws: PreferencesStore.PreferencesError.invalidPresetDuration(index: 0, value: 0)) {
            try store.setPresetDurations([0, 120, 180])
        }

        #expect(store.presetDurations == [60, 120, 180])
        #expect(storedPresetDurations(in: userDefaults) == [60, 120, 180])
    }

    @Test func malformedStoredPresetDurationsPreserveValidEntries() {
        let userDefaults = makeUserDefaults()
        userDefaults.set([300, -1, 3_000], forKey: "presetDurations")

        let store = PreferencesStore(userDefaults: userDefaults)

        #expect(store.presetDurations == [300, 1_500, 3_000])
        #expect(storedPresetDurations(in: userDefaults) == [300, 1_500, 3_000])
    }

    @Test func missingStoredPresetDurationsFillFromDefaults() {
        let userDefaults = makeUserDefaults()
        userDefaults.set([600], forKey: "presetDurations")

        let store = PreferencesStore(userDefaults: userDefaults)

        #expect(store.presetDurations == [600, 1_500, 3_000])
        #expect(storedPresetDurations(in: userDefaults) == [600, 1_500, 3_000])
    }

    @Test func extraStoredPresetDurationsAreIgnored() {
        let userDefaults = makeUserDefaults()
        userDefaults.set([600, 1_200, 1_800, 2_400], forKey: "presetDurations")

        let store = PreferencesStore(userDefaults: userDefaults)

        #expect(store.presetDurations == [600, 1_200, 1_800])
        #expect(storedPresetDurations(in: userDefaults) == [600, 1_200, 1_800])
    }

    private func makeUserDefaults() -> UserDefaults {
        let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    private func storedPresetDurations(in userDefaults: UserDefaults) -> [TimeInterval]? {
        userDefaults.array(forKey: "presetDurations") as? [TimeInterval]
    }

    private func resetShortcuts() {
        KeyboardShortcuts.reset(AppShortcuts.allNames)
    }
}
