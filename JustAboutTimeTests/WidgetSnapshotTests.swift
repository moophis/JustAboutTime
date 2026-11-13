import XCTest
@testable import JustAboutTime

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testMenuActionsPublishCommittedSnapshotsAndRequestWidgetReloads() throws {
        let timer = TimerStore(tickInterval: .seconds(3600))
        var reloadedStates: [SharedTimerSnapshot.State] = []
        let coordinator = TimerCoordinator(
            primaryTimer: timer,
            secondaryTimer: TimerStore(role: .secondary),
            preferencesStore: PreferencesStore(),
            reloadWidgets: {
                if let snapshot = SharedTimerSnapshotStore.load()[.primary] { reloadedStates.append(snapshot.state) }
            }
        )
        timer.startCountdown(duration: 300)
        XCTAssertEqual(try XCTUnwrap(SharedTimerSnapshotStore.load()[.primary]).sessionID, timer.sessionID)
        timer.pause()
        XCTAssertEqual(SharedTimerSnapshotStore.load()[.primary]?.availableActions, [.resume, .finish])
        timer.resume()
        XCTAssertEqual(Array(reloadedStates.suffix(3)), [.running, .paused, .running])
        withExtendedLifetime(coordinator) {}
    }

    func testRapidPauseResumeAlwaysPublishesFinalCommittedState() {
        let timer = TimerStore(tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore(), reloadWidgets: {})
        timer.startCountUp()
        for _ in 0..<5 { timer.pause(); timer.resume() }
        XCTAssertEqual(SharedTimerSnapshotStore.load()[.primary]?.state, .running)
        XCTAssertEqual(SharedTimerSnapshotStore.load()[.primary]?.sessionID, timer.sessionID)
        withExtendedLifetime(coordinator) {}
    }

    func testSwapPublishesBothTimersUnderTheirNewRoles() {
        let coordinator = TimerCoordinator(primaryTimer: TimerStore(), secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore(), reloadWidgets: {})
        coordinator.primaryTimer.startCountdown(duration: 300)
        coordinator.activateSecondary()
        coordinator.secondaryTimer.startCountUp()
        let oldPrimary = coordinator.primaryTimer.sessionID
        let oldSecondary = coordinator.secondaryTimer.sessionID
        coordinator.swapTimers()
        let snapshots = SharedTimerSnapshotStore.load()
        XCTAssertEqual(snapshots[.primary]?.sessionID, oldSecondary)
        XCTAssertEqual(snapshots[.primary]?.role, .primary)
        XCTAssertEqual(snapshots[.secondary]?.sessionID, oldPrimary)
        XCTAssertEqual(snapshots[.secondary]?.role, .secondary)
    }

    func testFinishInvalidatesDuplicateCommandsAndRepeatCreatesNewSession() {
        let timer = TimerStore(tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore(), reloadWidgets: {})
        timer.startCountdown(duration: 300)
        let finish = SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .finish)
        coordinator.applyWidgetCommand(finish)
        let acknowledged = timer.sharedSnapshot()
        coordinator.applyWidgetCommand(finish)
        XCTAssertEqual(timer.sessionID, acknowledged.sessionID)
        XCTAssertEqual(timer.sharedSnapshot().state, acknowledged.state)
        coordinator.applyWidgetCommand(SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .repeatLast))
        XCTAssertNotEqual(timer.sessionID, acknowledged.sessionID)
        XCTAssertEqual(timer.sharedSnapshot().state, .running)
    }

    func testOldWidgetCommandCannotPauseReplacementTimer() {
        let timer = TimerStore(tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore(), reloadWidgets: {})
        timer.startCountdown(duration: 300)
        let oldCommand = SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .pause)
        timer.startCountUp()
        coordinator.applyWidgetCommand(oldCommand)
        XCTAssertEqual(timer.sharedSnapshot().state, .running)
        XCTAssertEqual(SharedTimerSnapshotStore.load()[.primary]?.sessionID, timer.sessionID)
    }

    func testWidgetStateFormattingAndActionsAreBounded() {
        let now = Date()
        let running = SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .running, mode: .countdown(duration: 300), startedAt: now, targetDate: now.addingTimeInterval(300), frozenSeconds: nil, originalDuration: 300, lastUpdated: now, hasLastTimer: true)
        XCTAssertEqual(running.formattedValue(at: now), "05:00")
        XCTAssertEqual(running.availableActions, [.pause, .finish])
        XCTAssertEqual(running.reconciled(at: now.addingTimeInterval(301)).state, .due)
        let pausedOverdue = SharedTimerSnapshot(role: .secondary, sessionID: UUID(), state: .overdue, mode: .countUp, startedAt: now, targetDate: nil, frozenSeconds: 30, originalDuration: nil, lastUpdated: now, hasLastTimer: true)
        XCTAssertEqual(pausedOverdue.availableActions, [.resume, .finish])
        XCTAssertEqual(pausedOverdue.formattedValue(at: now.addingTimeInterval(100)), "00:30")
    }

    func testSessionStartedAtSurvivesRestorationAndDueReconciliation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionStartedAt = now.addingTimeInterval(-30)
        let snapshot = SharedTimerSnapshot(
            role: .primary, sessionID: UUID(), state: .running,
            mode: .countdown(duration: 300), startedAt: sessionStartedAt,
            targetDate: now.addingTimeInterval(300), frozenSeconds: nil,
            originalDuration: 300, lastUpdated: now, hasLastTimer: true,
            sessionStartedAt: sessionStartedAt
        )
        XCTAssertEqual(snapshot.reconciled(at: now.addingTimeInterval(301)).sessionStartedAt, sessionStartedAt)
        let timer = TimerStore(now: { now }, tickInterval: .seconds(3600))
        XCTAssertTrue(timer.restoreWidgetSnapshot(snapshot))
        XCTAssertEqual(timer.sharedSnapshot(at: now).sessionStartedAt, sessionStartedAt)
    }

    func testWidgetTestsUseIsolatedSnapshotStore() {
        XCTAssertNotEqual(SharedTimerSnapshotStore.suiteName, "group.com.liqiangw.JustAboutTime")
        XCTAssertTrue(SharedTimerSnapshotStore.suiteName.contains(String(ProcessInfo.processInfo.processIdentifier)))
    }

    func testAllActivePhasesRestoreTheirTimeAndSessionIdentity() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = [
            SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .running, mode: .countdown(duration: 300), startedAt: now.addingTimeInterval(-60), targetDate: now.addingTimeInterval(240), frozenSeconds: nil, originalDuration: 300, lastUpdated: now, hasLastTimer: true),
            SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .paused, mode: .countdown(duration: 300), startedAt: now.addingTimeInterval(-60), targetDate: nil, frozenSeconds: 240, originalDuration: 300, lastUpdated: now, hasLastTimer: true),
            SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .running, mode: .countUp, startedAt: now.addingTimeInterval(-60), targetDate: nil, frozenSeconds: nil, originalDuration: nil, lastUpdated: now, hasLastTimer: true),
            SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .paused, mode: .countUp, startedAt: now.addingTimeInterval(-60), targetDate: nil, frozenSeconds: 60, originalDuration: nil, lastUpdated: now, hasLastTimer: true),
            SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .overdue, mode: .countUp, startedAt: now.addingTimeInterval(-60), targetDate: nil, frozenSeconds: nil, originalDuration: 300, lastUpdated: now, hasLastTimer: true),
            SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .overdue, mode: .countUp, startedAt: now.addingTimeInterval(-60), targetDate: nil, frozenSeconds: 60, originalDuration: 300, lastUpdated: now, hasLastTimer: true)
        ]
        for snapshot in snapshots {
            let timer = TimerStore(now: { now }, tickInterval: .seconds(3600))
            XCTAssertTrue(timer.restoreWidgetSnapshot(snapshot))
            let restored = timer.sharedSnapshot(at: now)
            XCTAssertEqual(restored.sessionID, snapshot.sessionID)
            XCTAssertEqual(restored.state, snapshot.state)
            XCTAssertEqual(restored.value(at: now), snapshot.value(at: now), accuracy: 0.001)
            XCTAssertEqual(restored.availableActions, snapshot.availableActions)
        }
    }

    func testRestorePrecedesPublicationAndColdCommandConsumption() {
        let now = Date()
        let snapshot = SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .running, mode: .countdown(duration: 300), startedAt: now, targetDate: now.addingTimeInterval(300), frozenSeconds: nil, originalDuration: 300, lastUpdated: now, hasLastTimer: true)
        SharedTimerSnapshotStore.save([.primary: snapshot])
        SharedTimerSnapshotStore.enqueue(SharedTimerCommand(role: .primary, sessionID: snapshot.sessionID, action: .pause))
        let coordinator = TimerCoordinator(historyStore: HistoryStore(), notificationManager: NotificationManager(), preferencesStore: PreferencesStore())
        XCTAssertEqual(coordinator.primaryTimer.sessionID, snapshot.sessionID)
        coordinator.consumeWidgetCommand()
        XCTAssertEqual(coordinator.primaryTimer.sharedSnapshot().state, .paused)
        XCTAssertEqual(SharedTimerSnapshotStore.load()[.primary]?.state, .paused)
        XCTAssertNil(SharedTimerSnapshotStore.takeCommand())
    }

    func testRestoreKeepsSecondaryActivationAndRejectsInvalidSnapshots() {
        let now = Date()
        let snapshot = SharedTimerSnapshot(role: .secondary, sessionID: UUID(), state: .paused, mode: .countUp, startedAt: now, targetDate: nil, frozenSeconds: 42, originalDuration: nil, lastUpdated: now, hasLastTimer: true)
        let coordinator = TimerCoordinator(primaryTimer: TimerStore(), secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore(), reloadWidgets: {}, restoring: [.secondary: snapshot])
        XCTAssertTrue(coordinator.isSecondaryActivated)
        XCTAssertEqual(coordinator.secondaryTimer.sessionID, snapshot.sessionID)
        let invalid = SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .running, mode: .countdown(duration: -5), startedAt: now, targetDate: now, frozenSeconds: nil, originalDuration: -5, lastUpdated: now, hasLastTimer: false)
        XCTAssertFalse(coordinator.primaryTimer.restoreWidgetSnapshot(invalid))
        XCTAssertNil(coordinator.primaryTimer.activeSession)
    }

    func testWidgetMetadataUsesWidgetKitExtensionEntryPoint() throws {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("JustAboutTime/WidgetInfo.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: plistURL)) as! [String: Any]
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "$(EXECUTABLE_NAME)")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        let extensionInfo = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
        XCTAssertNil(plist["NSExtensionPrincipalClass"])
    }

    func testSandboxedAppAllowsSparkleDownloads() throws {
        let entitlementsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("JustAboutTime/JustAboutTime.entitlements")
        let entitlements = try XCTUnwrap(NSDictionary(contentsOf: entitlementsURL)) as! [String: Any]
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] as? [String], [
            "$(PRODUCT_BUNDLE_IDENTIFIER)-spks",
            "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"
        ])

        let appInfoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("JustAboutTime/Info.plist")
        let appInfo = try XCTUnwrap(NSDictionary(contentsOf: appInfoURL)) as! [String: Any]
        XCTAssertEqual(appInfo["SUEnableInstallerLauncherService"] as? Bool, true)
    }

    func testWidgetTimerIntentIsIncludedInBothHostTargets() throws {
        let projectPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("JustAboutTime.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectPath)
        XCTAssertTrue(project.contains("WidgetTimerIntents.swift in Sources"))
        XCTAssertTrue(project.contains("WidgetTimerIntents.swift in Widget Sources"))
    }

    func testTimerActionIntentEnqueuesPauseInIsolatedTransport() async throws {
        let sessionID = UUID()
        let intent = TimerActionIntent(role: .primary, sessionID: sessionID, action: .pause)
        _ = try await intent.perform()

        let command = SharedTimerSnapshotStore.takeCommand()
        XCTAssertEqual(command, SharedTimerCommand(role: .primary, sessionID: sessionID, action: .pause))
        XCTAssertEqual(SharedTimerSnapshotStore.commandNotificationName.rawValue, "JustAboutTimeTests.\(ProcessInfo.processInfo.processIdentifier).widgetCommand")
    }

    func testRunningCountUpSnapshotUsesDateRenderingAndNoFrozenValue() {
        let store = TimerStore(tickInterval: .seconds(3600))
        store.startCountUp()
        let snapshot = store.sharedSnapshot()
        XCTAssertEqual(snapshot.state, .running)
        XCTAssertNil(snapshot.frozenSeconds)
        XCTAssertNotNil(snapshot.displayDate)
    }

    func testWidgetSetupRouteRequestsTimerControlsWithoutChangingTimerState() {
        let timer = TimerStore(tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())

        coordinator.handleWidgetURL(URL(string: "justabouttime://setup/primary")!)

        XCTAssertEqual(coordinator.widgetSetupRole, .primary)
        XCTAssertNil(timer.activeSession)
        XCTAssertEqual(coordinator.consumeWidgetSetupRequest(), .primary)
        XCTAssertNil(coordinator.widgetSetupRole)
    }

    func testWidgetBodyOpenRequestsControlsEvenWithStaleSessionToken() {
        let timer = TimerStore(tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())

        coordinator.handleWidgetURL(URL(string: "justabouttime://timer/primary/open?session=00000000-0000-0000-0000-000000000000")!)

        XCTAssertEqual(coordinator.widgetSetupRole, .primary)
        XCTAssertNil(timer.activeSession)
    }

    func testStaleWidgetActionDoesNotPauseNewSession() {
        let store = TimerStore(tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: store, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())
        store.startCountUp()
        let stale = store.sessionID
        store.startCountUp()
        let url = URL(string: "justabouttime://timer/primary/pause?session=\(stale.uuidString)")!
        coordinator.handleWidgetURL(url)
        if case .runningCountUp = store.activeSession?.phase { } else { XCTFail("stale action changed the current session") }
    }

    func testCommandHandoffPausesAuthoritativeTimer() {
        let timer = TimerStore()
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())
        timer.startCountUp()
        SharedTimerSnapshotStore.enqueue(SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .pause))
        coordinator.consumeWidgetCommand()
        if case .pausedCountUp = timer.activeSession?.phase { } else { XCTFail("command did not pause timer") }
    }

    func testQueuedCommandIsConsumedWhenAppCoordinatorStarts() {
        let timer = TimerStore(tickInterval: .seconds(3600))
        timer.startCountUp()
        SharedTimerSnapshotStore.enqueue(SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .pause))

        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())
        coordinator.consumeWidgetCommand()

        if case .pausedCountUp = timer.activeSession?.phase { } else { XCTFail("queued command was not consumed at coordinator startup") }
    }

    func testSecondaryFinishDeactivatesThroughWidgetRoute() {
        let coordinator = TimerCoordinator(primaryTimer: TimerStore(), secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())
        coordinator.activateSecondary()
        coordinator.secondaryTimer.startCountUp()
        let token = coordinator.secondaryTimer.sessionID
        coordinator.handleWidgetURL(URL(string: "justabouttime://timer/secondary/finish?session=\(token.uuidString)")!)
        XCTAssertFalse(coordinator.isSecondaryActivated)
    }
    func testIdleSnapshotRendersZeroAndDateRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = TimerStore(now: { now }, tickInterval: .seconds(3600))
        let idle = store.sharedSnapshot(at: now)
        XCTAssertEqual(idle.value(at: now), 0)

        let snapshot = SharedTimerSnapshot(role: .primary, sessionID: UUID(), state: .running, mode: .countUp, startedAt: now.addingTimeInterval(-12), targetDate: nil, frozenSeconds: nil, originalDuration: nil, lastUpdated: now, hasLastTimer: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(SharedTimerSnapshot.self, from: encoder.encode(snapshot)), snapshot)
    }

    func testWidgetCommandPropagatesPauseAndResume() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timer = TimerStore(now: { now }, tickInterval: .seconds(3600))
        let coordinator = TimerCoordinator(primaryTimer: timer, secondaryTimer: TimerStore(role: .secondary), preferencesStore: PreferencesStore())
        timer.startCountUp()
        SharedTimerSnapshotStore.enqueue(SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .pause))
        coordinator.consumeWidgetCommand()
        if case .pausedCountUp = timer.activeSession?.phase { } else { XCTFail("pause command did not propagate") }
        SharedTimerSnapshotStore.enqueue(SharedTimerCommand(role: .primary, sessionID: timer.sessionID, action: .resume))
        coordinator.consumeWidgetCommand()
        if case .runningCountUp = timer.activeSession?.phase { } else { XCTFail("resume command did not propagate") }
    }

    func testResumedCountUpSnapshotPreservesAccumulatedElapsedTime() {
        final class Clock: @unchecked Sendable { var value = Date(timeIntervalSince1970: 1_700_000_000) }
        let clock = Clock()
        let timer = TimerStore(now: { clock.value }, tickInterval: .seconds(3600))
        timer.startCountUp()
        clock.value.addTimeInterval(30)
        timer.pause()
        clock.value.addTimeInterval(10)
        timer.resume()
        let snapshot = timer.sharedSnapshot(at: clock.value)
        XCTAssertEqual(snapshot.value(at: clock.value), 30, accuracy: 0.001)
    }
}
