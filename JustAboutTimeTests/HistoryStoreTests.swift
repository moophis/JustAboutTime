import Foundation
import Testing

@testable import JustAboutTime

@MainActor
struct HistoryStoreTests {
    @Test func historyFileCreatesOnFirstWrite() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: fileURL)

        let result = store.recordCompletedCountdown(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            presetDuration: 300,
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            completedAt: Date(timeIntervalSinceReferenceDate: 400)
        )

        #expect(result.isSuccess)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(store.loadEntries().count == 1)
    }

    @Test func loadEntriesReturnsNewestFirst() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: fileURL)

        #expect(store.recordCompletedCountdown(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            presetDuration: 300,
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            completedAt: Date(timeIntervalSinceReferenceDate: 400)
        ).isSuccess)
        #expect(store.recordCompletedCountdown(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            presetDuration: 600,
            startedAt: Date(timeIntervalSinceReferenceDate: 500),
            completedAt: Date(timeIntervalSinceReferenceDate: 900)
        ).isSuccess)

        let entries = store.loadEntries()

        #expect(entries.map(\.id) == [
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        ])
    }

    @Test func loadResultSurfacesUnreadableHistory() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: fileURL)
        let store = HistoryStore(fileURL: fileURL)

        let result = store.loadResult()

        #expect(result.entries == nil)
        #expect(result.failure == .unreadableExistingHistory)
    }

    @Test func corruptHistoryFileFailsSoft() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: fileURL)
        let store = HistoryStore(fileURL: fileURL)

        #expect(store.loadEntries().isEmpty)
    }

    @Test func corruptHistoryFileRefusesDestructiveWrites() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let originalData = Data("not-json".utf8)
        try originalData.write(to: fileURL)
        let store = HistoryStore(fileURL: fileURL)

        let result = store.recordCompletedCountdown(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            presetDuration: 1_500,
            startedAt: Date(timeIntervalSinceReferenceDate: 50),
            completedAt: Date(timeIntervalSinceReferenceDate: 1_550)
        )

        #expect(result.failure == .unreadableExistingHistory)
        #expect(try Data(contentsOf: fileURL) == originalData)
    }

    @Test func failedPersistReturnsFailure() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let blockingFileURL = directoryURL.appendingPathComponent("blocked")
        try Data().write(to: blockingFileURL)
        let store = HistoryStore(fileURL: blockingFileURL.appendingPathComponent("history.json"))

        let result = store.recordCompletedCountdown(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            presetDuration: 300,
            startedAt: Date(timeIntervalSinceReferenceDate: 100),
            completedAt: Date(timeIntervalSinceReferenceDate: 400)
        )

        #expect(result.failure == .failedToPersistHistory)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}

private extension Result where Success == Void {
    var isSuccess: Bool {
        if case .success = self {
            return true
        }

        return false
    }

    var failure: Failure? {
        if case let .failure(error) = self {
            return error
        }

        return nil
    }
}

private extension Result where Success == [HistoryEntry], Failure == HistoryStore.HistoryError {
    var entries: [HistoryEntry]? {
        if case let .success(entries) = self {
            return entries
        }

        return nil
    }

    var failure: Failure? {
        if case let .failure(error) = self {
            return error
        }

        return nil
    }
}
