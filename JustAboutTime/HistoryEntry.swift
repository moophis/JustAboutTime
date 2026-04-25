import Foundation

struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let presetDuration: TimeInterval
    let startedAt: Date
    let completedAt: Date
}
