import Foundation

final class HistoryStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL = HistoryStore.defaultFileURL(),
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadEntries() -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        guard let entries = try? decoder.decode([HistoryEntry].self, from: data) else {
            return []
        }

        return Self.sortNewestFirst(entries)
    }

    func recordCompletedCountdown(id: UUID = UUID(), presetDuration: TimeInterval, startedAt: Date, completedAt: Date) {
        var entries = loadEntries()
        entries.insert(
            HistoryEntry(
                id: id,
                presetDuration: presetDuration,
                startedAt: startedAt,
                completedAt: completedAt
            ),
            at: 0
        )

        persist(Self.sortNewestFirst(entries))
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupportURL
            .appendingPathComponent("com.liqiangw.JustAboutTime", isDirectory: true)
            .appendingPathComponent("countdown-history.json", isDirectory: false)
    }

    private func persist(_ entries: [HistoryEntry]) {
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
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
