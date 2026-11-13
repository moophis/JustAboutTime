import Foundation

struct SharedTimerCommand: Codable, Equatable {
    let role: TimerRole
    let sessionID: UUID
    let action: Action

    enum Action: String, Codable {
        case pause, resume, finish, repeatLast
    }
}

struct SharedTimerSnapshot: Codable, Equatable {
    enum State: String, Codable { case idle, running, paused, due, overdue }

    let role: TimerRole
    let sessionID: UUID
    let state: State
    let mode: TimerMode
    let startedAt: Date?
    let targetDate: Date?
    let frozenSeconds: TimeInterval?
    let originalDuration: TimeInterval?
    let lastUpdated: Date
    let hasLastTimer: Bool
    var sessionStartedAt: Date?

    var isValidForRestoration: Bool {
        guard lastUpdated.timeIntervalSince1970.isFinite,
              [startedAt, targetDate, sessionStartedAt].compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              frozenSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true,
              originalDuration.map({ $0.isFinite && $0 > 0 }) ?? true else { return false }
        if case let .countdown(duration) = mode {
            guard duration.isFinite, duration > 0 else { return false }
            switch state {
            case .running: return startedAt != nil && targetDate != nil && frozenSeconds == nil
            case .paused: return startedAt != nil && targetDate == nil && frozenSeconds.map({ $0 <= duration }) == true
            case .due, .idle: return true
            case .overdue: return false
            }
        }
        switch state {
        case .running: return startedAt != nil && targetDate == nil && frozenSeconds == nil
        case .paused: return frozenSeconds != nil && targetDate == nil
        case .overdue: return startedAt != nil && targetDate == nil
        case .idle: return true
        case .due: return false
        }
    }

    var availableActions: [SharedTimerCommand.Action] {
        switch state {
        case .running: return [.pause, .finish]
        case .paused: return [.resume, .finish]
        case .overdue: return [frozenSeconds == nil ? .pause : .resume, .finish]
        case .due: return hasLastTimer ? [.finish, .repeatLast] : [.finish]
        case .idle: return hasLastTimer ? [.repeatLast] : []
        }
    }

    var statusLabel: String {
        switch state {
        case .running: return mode == .countUp ? "Elapsed" : "Remaining"
        case .paused: return "Paused"
        case .overdue: return frozenSeconds == nil ? "Overdue" : "Paused · Overdue"
        case .due: return "Time’s up"
        case .idle: return "Ready"
        }
    }

    func formattedValue(at date: Date) -> String {
        let total = max(0, Int(value(at: date).rounded(.up)))
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func reconciled(at date: Date) -> SharedTimerSnapshot {
        guard state == .running, case .countdown = mode, let targetDate, targetDate <= date else { return self }
        var copy = self
        copy = SharedTimerSnapshot(role: role, sessionID: sessionID, state: .due, mode: mode, startedAt: startedAt, targetDate: targetDate, frozenSeconds: nil, originalDuration: originalDuration, lastUpdated: date, hasLastTimer: hasLastTimer, sessionStartedAt: sessionStartedAt)
        return copy
    }

    var displayDate: Date? {
        switch mode {
        case .countdown: return targetDate
        case .countUp: return startedAt.map { $0.addingTimeInterval(-(frozenSeconds ?? 0)) }
        }
    }

    func value(at date: Date = Date()) -> TimeInterval {
        switch mode {
        case .countdown:
            return max(0, frozenSeconds ?? (targetDate ?? date).timeIntervalSince(date))
        case .countUp:
            guard let startedAt else { return frozenSeconds ?? 0 }
            return frozenSeconds ?? max(0, date.timeIntervalSince(startedAt))
        }
    }

    var value: TimeInterval { value(at: Date()) }

    func progress(at date: Date = Date()) -> Double? {
        guard let originalDuration, originalDuration > 0, case .countdown = mode else { return nil }
        return min(1, max(0, value(at: date) / originalDuration))
    }

    var progress: Double? { progress(at: Date()) }
}

struct SharedTimerSnapshotStore {
    static let suiteName: String = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "JustAboutTimeTests.\(ProcessInfo.processInfo.processIdentifier)"
        }
        return "group.com.liqiangw.JustAboutTime"
    }()
    static let commandNotificationName: Notification.Name = {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return Notification.Name("JustAboutTimeTests.\(ProcessInfo.processInfo.processIdentifier).widgetCommand")
        }
        return Notification.Name("JustAboutTime.widgetCommand")
    }()
    private static let snapshotKey = "timer-widget-snapshots"
    private static let commandKey = "timer-widget-command"

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private static func decodeSnapshots(_ data: Data) -> [String: SharedTimerSnapshot]? {
        guard let values = try? decoder().decode([String: SharedTimerSnapshot].self, from: data) else { return nil }
        // Snapshots written before the explicit epoch used Foundation's reference-date encoding.
        guard values.values.contains(where: { $0.lastUpdated < Date(timeIntervalSinceReferenceDate: 0) }) else { return values }
        return try? JSONDecoder().decode([String: SharedTimerSnapshot].self, from: data)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func load() -> [TimerRole: SharedTimerSnapshot] {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: snapshotKey), let values = decodeSnapshots(data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.compactMap { key, value in TimerRole(rawValue: key).map { ($0, value) } })
    }

    static func save(_ snapshots: [TimerRole: SharedTimerSnapshot]) {
        let values = snapshots.reduce(into: [String: SharedTimerSnapshot]()) { $0[$1.key.rawValue] = $1.value }
        guard let data = try? encoder().encode(values) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: snapshotKey)
    }

    static func enqueue(_ command: SharedTimerCommand) {
        guard let data = try? encoder().encode(command) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: commandKey)
        DistributedNotificationCenter.default().post(name: commandNotificationName, object: nil)
    }

    static func takeCommand() -> SharedTimerCommand? {
        let defaults = UserDefaults(suiteName: suiteName)
        defer { defaults?.removeObject(forKey: commandKey) }
        guard let data = defaults?.data(forKey: commandKey) else { return nil }
        return try? decoder().decode(SharedTimerCommand.self, from: data)
    }
}

extension TimerMode: Codable {
    private enum CodingKeys: String, CodingKey { case kind, duration }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(String.self, forKey: .kind) == "countUp" { self = .countUp } else { self = .countdown(duration: try container.decode(TimeInterval.self, forKey: .duration)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self { case .countUp: try container.encode("countUp", forKey: .kind); case let .countdown(duration): try container.encode("countdown", forKey: .kind); try container.encode(duration, forKey: .duration) }
    }
}
