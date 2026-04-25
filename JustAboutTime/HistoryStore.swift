import Combine
import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    enum HistoryError: Error, Equatable {
        case unreadableExistingHistory
        case failedToPersistHistory
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @Published private(set) var entries: [HistoryEntry]

    init(
        fileURL: URL = HistoryStore.defaultFileURL(),
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        let initialEntries: [HistoryEntry]

        if case let .success(loadedEntries) = Self.readEntriesForLoad(fileURL: fileURL, fileManager: fileManager, decoder: decoder) {
            initialEntries = Self.sortNewestFirst(loadedEntries)
        } else {
            initialEntries = []
        }

        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        _entries = Published(initialValue: initialEntries)
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadEntries() -> [HistoryEntry] {
        guard case let .success(entries) = loadResult() else {
            return []
        }

        self.entries = entries
        return entries
    }

    func loadResult() -> Result<[HistoryEntry], HistoryError> {
        Self.readEntriesForLoad(fileURL: fileURL, fileManager: fileManager, decoder: decoder).map(Self.sortNewestFirst)
    }

    @discardableResult
    func recordCompletedCountdown(
        id: UUID = UUID(),
        presetDuration: TimeInterval,
        startedAt: Date,
        completedAt: Date
    ) -> Result<Void, HistoryError> {
        let existingEntries: [HistoryEntry]

        switch readEntriesForWrite() {
        case let .success(loadedEntries):
            existingEntries = loadedEntries
        case let .failure(error):
            return .failure(error)
        }

        var updatedEntries = existingEntries
        updatedEntries.insert(
            HistoryEntry(
                id: id,
                presetDuration: presetDuration,
                startedAt: startedAt,
                completedAt: completedAt
            ),
            at: 0
        )

        let sortedEntries = Self.sortNewestFirst(updatedEntries)

        guard persist(sortedEntries) else {
            return .failure(.failedToPersistHistory)
        }

        entries = sortedEntries

        return .success(())
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupportURL
            .appendingPathComponent("com.liqiangw.JustAboutTime", isDirectory: true)
            .appendingPathComponent("countdown-history.json", isDirectory: false)
    }

    private static func readEntriesForLoad(
        fileURL: URL,
        fileManager: FileManager,
        decoder: JSONDecoder
    ) -> Result<[HistoryEntry], HistoryError> {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .success([])
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return .failure(.unreadableExistingHistory)
        }

        guard let entries = try? decoder.decode([HistoryEntry].self, from: data) else {
            return .failure(.unreadableExistingHistory)
        }

        return .success(entries)
    }

    private func readEntriesForWrite() -> Result<[HistoryEntry], HistoryError> {
        Self.readEntriesForLoad(fileURL: fileURL, fileManager: fileManager, decoder: decoder)
    }

    private func persist(_ entries: [HistoryEntry]) -> Bool {
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func sortNewestFirst(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.completedAt != rhs.completedAt {
                return lhs.completedAt > rhs.completedAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
