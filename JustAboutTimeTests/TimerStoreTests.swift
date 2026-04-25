import Combine
import Foundation
import Testing

@testable import JustAboutTime

struct TimerStoreTests {
    @Test func statusBarPresenterFormatsIdleSnapshot() {
        let presenter = StatusBarPresenter()

        let presentation = presenter.presentation(for: .idle, animationStep: 0)

        #expect(presentation.text == "00:00")
        #expect(presentation.dotPhase == .hidden)
    }

    @Test func statusBarPresenterFormatsRunningCountdownSnapshot() {
        let presenter = StatusBarPresenter()

        let presentation = presenter.presentation(
            for: .countdown(remaining: 125, isRunning: true),
            animationStep: 1
        )

        #expect(presentation.text == "02:05")
        #expect(presentation.dotPhase == .trailing)
    }

    @Test func statusBarPresenterFormatsPausedCountUpSnapshot() {
        let presenter = StatusBarPresenter()

        let presentation = presenter.presentation(
            for: .countUp(elapsed: 45, isRunning: false),
            animationStep: 1
        )

        #expect(presentation.text == "00:45")
        #expect(presentation.dotPhase == .hidden)
    }

    @Test func statusBarPresenterOnlyAnimatesDotsWhileRunning() {
        let presenter = StatusBarPresenter()

        let runningA = presenter.presentation(for: .countUp(elapsed: 10, isRunning: true), animationStep: 0)
        let runningB = presenter.presentation(for: .countUp(elapsed: 10, isRunning: true), animationStep: 1)
        let pausedA = presenter.presentation(for: .countUp(elapsed: 10, isRunning: false), animationStep: 0)
        let pausedB = presenter.presentation(for: .countUp(elapsed: 10, isRunning: false), animationStep: 1)
        let idleA = presenter.presentation(for: .idle, animationStep: 0)
        let idleB = presenter.presentation(for: .idle, animationStep: 1)

        #expect(runningA.dotPhase != runningB.dotPhase)
        #expect(pausedA.dotPhase == pausedB.dotPhase)
        #expect(idleA.dotPhase == idleB.dotPhase)
    }

    @MainActor
    @Test func timerStoreStartsIdleAndUpdatesPresentationWhenCountdownStarts() {
        let store = TimerStore(now: { Date(timeIntervalSinceReferenceDate: 1_000) })

        #expect(store.statusPresentation.text == "00:00")

        store.startCountdown(duration: 90)

        #expect(store.statusPresentation.text == "01:30")
        #expect(store.statusPresentation.dotPhase == .leading)
    }

    @MainActor
    @Test func countdownStartUsesSameTimestampForInitialPresentation() {
        let clock = SteppingClock(times: [
            Date(timeIntervalSinceReferenceDate: 1_000),
            Date(timeIntervalSinceReferenceDate: 1_000.9)
        ])
        let store = TimerStore(now: { clock.now() })

        store.startCountdown(duration: 60)

        #expect(store.statusPresentation.text == "01:00")
    }

    @MainActor
    @Test func countdownStartAndRestartDoNotRequestNotificationsEarly() async {
        let center = TestNotificationCenter(initialStatus: .notDetermined)
        let notificationManager = NotificationManager(client: center.makeClient())
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let store = TimerStore(notificationManager: notificationManager, now: { clock.now })

        store.startCountdown(duration: 90)
        store.restart()
        await Task.yield()

        #expect(await center.authorizationRequestCount == 0)
        #expect(await center.requests.isEmpty)
    }

    @MainActor
    @Test func timerStoreSurfacesCountdownCompletionEvents() async throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let sleeper = TestSleeper()
        let store = TimerStore(now: { clock.now }, sleep: sleeper.sleep(for:))

        #expect(store.latestEvent == nil)

        store.startCountdown(duration: 1)
        clock.advance(by: 1)
        await sleeper.resumeOnce()

        while store.latestEvent == nil, store.activeSession != nil {
            await Task.yield()
        }

        #expect(store.latestEvent == .countdownCompleted)
        #expect(store.activeSession == nil)
    }

    @MainActor
    @Test func countdownCompletionSchedulesNotificationWhenAuthorized() async throws {
        let center = TestNotificationCenter(initialStatus: .authorized)
        let notificationManager = NotificationManager(client: center.makeClient())
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let sleeper = TestSleeper()
        let store = TimerStore(
            notificationManager: notificationManager,
            now: { clock.now },
            sleep: sleeper.sleep(for:)
        )

        await notificationManager.refresh()
        store.startCountdown(duration: 90)
        clock.advance(by: 90)
        await sleeper.resumeOnce()

        while store.latestEvent == nil {
            await Task.yield()
        }

        while await center.requests.isEmpty {
            await Task.yield()
        }

        let request = try #require(await center.requests.first)

        #expect(store.latestEvent == .countdownCompleted)
        #expect(request.title == "Countdown Complete")
        #expect(request.body == "Your 1m countdown finished.")
    }

    @MainActor
    @Test func deniedNotificationsDoNotBreakCountdownCompletionFlow() async throws {
        let center = TestNotificationCenter(initialStatus: .denied)
        let notificationManager = NotificationManager(client: center.makeClient())
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let store = TimerStore(notificationManager: notificationManager, now: { clock.now })

        await notificationManager.refresh()

        store.startCountdown(duration: 1)
        clock.advance(by: 2)
        store.pause()

        #expect(store.latestEvent == .countdownCompleted)
        #expect(store.activeSession == nil)
        #expect(await center.requests.isEmpty)
    }

    @MainActor
    @Test func timerStorePublishesTickUpdatesFromMainThread() async throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let sleeper = TestSleeper()
        let store = TimerStore(now: { clock.now }, sleep: sleeper.sleep(for:))
        let stream = AsyncStream.makeStream(of: (Bool, String).self)
        var cancellables = Set<AnyCancellable>()
        var iterator = stream.stream.makeAsyncIterator()

        store.$statusPresentation
            .dropFirst()
            .sink { presentation in
                stream.continuation.yield((Thread.isMainThread, presentation.text))
            }
            .store(in: &cancellables)

        store.startCountUp()
        clock.advance(by: 1)
        await sleeper.resumeOnce()

        var tickWasPublishedOnMainThread: Bool?

        while let event = await iterator.next() {
            if event.1 == "00:01" {
                tickWasPublishedOnMainThread = event.0
                break
            }
        }

        let publishedOnMainThread = try #require(tickWasPublishedOnMainThread as Bool?)

        #expect(publishedOnMainThread)
        #expect(store.statusPresentation.text == "00:01")
    }

    @MainActor
    @Test func timerStorePersistsCompletedCountdownsOnly() async throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let sleeper = TestSleeper()
        let directoryURL = try makeTemporaryDirectory()
        let historyStore = HistoryStore(fileURL: directoryURL.appendingPathComponent("history.json"))
        let store = TimerStore(historyStore: historyStore, now: { clock.now }, sleep: sleeper.sleep(for:))

        store.startCountUp()
        store.finish()
        #expect(historyStore.loadEntries().isEmpty)

        store.startCountdown(duration: 90)
        clock.advance(by: 90)
        await sleeper.resumeOnce()

        while store.latestEvent == nil, store.activeSession != nil {
            await Task.yield()
        }

        let entries = historyStore.loadEntries()
        let entry = try #require(entries.first)

        #expect(entries.count == 1)
        #expect(entry.presetDuration == 90)
        #expect(entry.startedAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(entry.completedAt == Date(timeIntervalSinceReferenceDate: 1_090))
        #expect(store.latestHistoryError == nil)
    }

    @MainActor
    @Test func overduePausePersistsCompletedCountdown() throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let directoryURL = try makeTemporaryDirectory()
        let historyStore = HistoryStore(fileURL: directoryURL.appendingPathComponent("history.json"))
        let store = TimerStore(historyStore: historyStore, now: { clock.now })

        store.startCountdown(duration: 90)
        clock.advance(by: 95)
        store.pause()

        let entry = try #require(historyStore.loadEntries().first)

        #expect(store.latestEvent == .countdownCompleted)
        #expect(entry.presetDuration == 90)
        #expect(entry.startedAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(entry.completedAt == Date(timeIntervalSinceReferenceDate: 1_095))
    }

    @MainActor
    @Test func finishAndRestartDoNotPersistCountdownHistory() throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let directoryURL = try makeTemporaryDirectory()
        let historyStore = HistoryStore(fileURL: directoryURL.appendingPathComponent("history.json"))
        let store = TimerStore(historyStore: historyStore, now: { clock.now })

        store.startCountdown(duration: 90)
        clock.advance(by: 30)
        store.restart()
        #expect(historyStore.loadEntries().isEmpty)

        clock.advance(by: 10)
        store.finish()
        #expect(historyStore.loadEntries().isEmpty)
    }

    @MainActor
    @Test func timerStoreSurfacesHistoryPersistenceFailures() throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let directoryURL = try makeTemporaryDirectory()
        let blockingFileURL = directoryURL.appendingPathComponent("blocked")
        try Data().write(to: blockingFileURL)
        let historyStore = HistoryStore(fileURL: blockingFileURL.appendingPathComponent("history.json"))
        let store = TimerStore(historyStore: historyStore, now: { clock.now })

        store.startCountdown(duration: 1)
        clock.advance(by: 2)
        store.pause()

        #expect(store.latestEvent == .countdownCompleted)
        #expect(store.latestHistoryError == .failedToPersistHistory)
    }

    @MainActor
    @Test func corruptHistoryFileDoesNotBreakCompletedCountdownFlow() throws {
        let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: fileURL)
        let historyStore = HistoryStore(fileURL: fileURL)
        let store = TimerStore(historyStore: historyStore, now: { clock.now })

        store.startCountdown(duration: 1)
        clock.advance(by: 2)
        store.pause()

        let loadResult = historyStore.loadResult()

        #expect(store.latestEvent == .countdownCompleted)
        #expect(store.activeSession == nil)
        #expect(store.latestHistoryError == .unreadableExistingHistory)
        #expect(loadResultFailure(loadResult) == .unreadableExistingHistory)
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private actor TestNotificationCenter {
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
        requests.append(request)
    }
}

private final class SteppingClock: @unchecked Sendable {
    private var times: [Date]

    init(times: [Date]) {
        self.times = times
    }

    func now() -> Date {
        guard times.count > 1 else {
            return times[0]
        }

        return times.removeFirst()
    }
}

private actor TestSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for _: Duration) async throws {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeOnce() async {
        while continuations.isEmpty {
            await Task.yield()
        }

        let continuation = continuations.removeFirst()
        continuation.resume()
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}

private func loadResultFailure(
    _ result: Result<[HistoryEntry], HistoryStore.HistoryError>
) -> HistoryStore.HistoryError? {
    if case let .failure(error) = result {
        return error
    }

    return nil
}
