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
    @Test func notifyCountdownCompletedDoesNothingWhenDenied() async {
        let center = TestNotificationManagerCenter(initialStatus: .denied)
        let manager = NotificationManager(client: center.makeClient())

        await manager.refresh()
        await manager.notifyCountdownCompleted(duration: 25 * 60)

        #expect(await center.requests.isEmpty)
    }
}

private actor TestNotificationManagerCenter {
    private(set) var status: NotificationManager.AuthorizationStatus
    private(set) var requests: [NotificationManager.Request] = []
    private(set) var authorizationRequestCount = 0

    init(initialStatus: NotificationManager.AuthorizationStatus) {
        status = initialStatus
    }

    nonisolated func makeClient() -> NotificationManager.Client {
        NotificationManager.Client(
            authorizationStatus: { [weak self] in
                await self?.status ?? .unknown
            },
            requestAuthorization: { [weak self] _ in
                await self?.recordAuthorizationRequest()
                await self?.setStatus(.authorized)
                return true
            },
            add: { [weak self] request in
                await self?.appendRequest(request)
            }
        )
    }

    func recordAuthorizationRequest() {
        authorizationRequestCount += 1
    }

    func setStatus(_ newStatus: NotificationManager.AuthorizationStatus) {
        status = newStatus
    }

    func appendRequest(_ request: NotificationManager.Request) {
        requests.append(request)
    }
}
