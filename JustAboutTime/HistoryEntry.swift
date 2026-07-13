import Foundation

struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timerRole: TimerRole
    let presetDuration: TimeInterval
    let startedAt: Date
    let completedAt: Date

    init(
        id: UUID,
        timerRole: TimerRole = .primary,
        presetDuration: TimeInterval,
        startedAt: Date,
        completedAt: Date
    ) {
        self.id = id
        self.timerRole = timerRole
        self.presetDuration = presetDuration
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timerRole
        case presetDuration
        case startedAt
        case completedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timerRole = try container.decodeIfPresent(TimerRole.self, forKey: .timerRole) ?? .primary
        presetDuration = try container.decode(TimeInterval.self, forKey: .presetDuration)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timerRole, forKey: .timerRole)
        try container.encode(presetDuration, forKey: .presetDuration)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(completedAt, forKey: .completedAt)
    }
}
