import Testing

@testable import JustAboutTime

struct NotificationManagerTests {
    @MainActor
    @Test func refreshPublishesCurrentAuthorizationStatus() async {
        let center = TestNotificationManagerCenter(initialStatus: .provisional)
        let manager = NotificationManager(client: center.makeClient())

        await manager.refresh()

        #expect(manager.authorizationStatus == .provisional)
    }

    @MainActor
    @Test func prepareRequestsAuthorizationOnlyWhenUndetermined() async {
        let center = TestNotificationManagerCenter(initialStatus: .notDetermined)
        let manager = NotificationManager(client: center.makeClient())

        await manager.prepareForCountdownAlertsIfNeeded()

        #expect(await center.authorizationRequestCount == 1)
        #expect(manager.authorizationStatus == .authorized)
    }

    @MainActor
    @Test func authorizationRequestsAreCoalescedAcrossConcurrentCallers() async {
        let center = TestNotificationManagerCenter(initialStatus: .notDetermined, authorizationDelay: .milliseconds(50))
        let manager = NotificationManager(client: center.makeClient())

        async let first: Void = manager.requestAuthorization()
        async let second: Void = manager.requestAuthorization()
        _ = await (first, second)

        #expect(await center.authorizationRequestCount == 1)
        #expect(manager.authorizationStatus == .authorized)
    }

    @MainActor
    @Test func notifyCountdownCompletedRequestsAuthorizationWhenFirstNeeded() async {
        let center = TestNotificationManagerCenter(initialStatus: .notDetermined)
        let manager = NotificationManager(client: center.makeClient())

        await manager.notifyCountdownCompleted(duration: 25 * 60)

        #expect(await center.authorizationRequestCount == 1)
        #expect(await center.requests.count == 1)
        #expect(manager.authorizationStatus == .authorized)
    }

    @MainActor
    @Test func notifyCountdownCompletedRefreshesBeforeDeliveryGating() async {
        let center = TestNotificationManagerCenter(initialStatus: .denied)
        let manager = NotificationManager(client: center.makeClient())

        await manager.refresh()
        await center.setStatus(.authorized)

        await manager.notifyCountdownCompleted(duration: 25 * 60)

        #expect(await center.authorizationRequestCount == 0)
        #expect(await center.requests.count == 1)
        #expect(manager.authorizationStatus == .authorized)
    }

    @MainActor
    @Test func notifyCountdownCompletedDoesNothingWhenDenied() async {
        let center = TestNotificationManagerCenter(initialStatus: .denied)
        let manager = NotificationManager(client: center.makeClient())

        await manager.refresh()
        await manager.notifyCountdownCompleted(duration: 25 * 60)

        #expect(await center.requests.isEmpty)
    }

    @MainActor
    @Test func schedulingFailuresSurfaceOnSharedPreferencesState() async {
        let center = TestNotificationManagerCenter(initialStatus: .authorized, addShouldFail: true)
        let manager = NotificationManager(client: center.makeClient())

        await manager.notifyCountdownCompleted(duration: 25 * 60)

        #expect(manager.latestDeliveryError == .failedToSchedule)
        #expect(manager.preferencesErrorText == "The last countdown alert could not be scheduled.")
    }

    @MainActor
    @Test func preferencesStateReflectsCurrentAuthorizationStatus() async {
        let center = TestNotificationManagerCenter(initialStatus: .denied)
        let manager = NotificationManager(client: center.makeClient())

        await manager.refresh()

        #expect(manager.preferencesDetailText == "Notification access is turned off. Open System Settings to enable alerts later.")
        #expect(manager.preferencesActionTitle == "Open System Settings")
    }
}

private actor TestNotificationManagerCenter {
    private(set) var status: NotificationManager.AuthorizationStatus
    private(set) var requests: [NotificationManager.Request] = []
    private(set) var authorizationRequestCount = 0
    private let authorizationDelay: Duration?
    private let addShouldFail: Bool

    init(
        initialStatus: NotificationManager.AuthorizationStatus,
        authorizationDelay: Duration? = nil,
        addShouldFail: Bool = false
    ) {
        status = initialStatus
        self.authorizationDelay = authorizationDelay
        self.addShouldFail = addShouldFail
    }

    nonisolated func makeClient() -> NotificationManager.Client {
        NotificationManager.Client(
            authorizationStatus: { [weak self] in
                await self?.status ?? .unknown
            },
            requestAuthorization: { [weak self] _ in
                await self?.delayAuthorizationIfNeeded()
                await self?.recordAuthorizationRequest()
                await self?.setStatus(.authorized)
                return true
            },
            add: { [weak self] request in
                try await self?.add(request)
            }
        )
    }

    func recordAuthorizationRequest() {
        authorizationRequestCount += 1
    }

    func setStatus(_ newStatus: NotificationManager.AuthorizationStatus) {
        status = newStatus
    }

    func add(_ request: NotificationManager.Request) throws {
        if addShouldFail {
            throw TestError.failedToSchedule
        }

        requests.append(request)
    }

    private func delayAuthorizationIfNeeded() async {
        guard let authorizationDelay else {
            return
        }

        try? await Task.sleep(for: authorizationDelay)
    }

    private enum TestError: Error {
        case failedToSchedule
    }
}
