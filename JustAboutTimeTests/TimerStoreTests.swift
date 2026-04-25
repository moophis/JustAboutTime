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
