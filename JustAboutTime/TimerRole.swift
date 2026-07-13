import Foundation

enum TimerRole: String, Codable, CaseIterable, Equatable {
    case primary
    case secondary

    var displayName: String {
        switch self {
        case .primary:
            return "Primary"
        case .secondary:
            return "Secondary"
        }
    }
}
