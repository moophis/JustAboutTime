import AppIntents
import WidgetKit

/// Shared by the app and widget extension so macOS registers widget actions in both bundles.
enum WidgetTimerRole: String, AppEnum {
  case primary, secondary

  static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer")
  static let caseDisplayRepresentations: [WidgetTimerRole: DisplayRepresentation] = [
    .primary: "Primary",
    .secondary: "Secondary"
  ]

  var timerRole: TimerRole { self == .primary ? .primary : .secondary }
}

struct TimerActionIntent: AppIntent {
  static let title: LocalizedStringResource = "Timer action"
  static let openAppWhenRun = true

  @Parameter(title: "Role") var role: WidgetTimerRole
  @Parameter(title: "Session") var sessionID: String
  @Parameter(title: "Action") var action: String

  init() {
    role = .primary
    sessionID = ""
    action = "pause"
  }

  init(role: WidgetTimerRole, sessionID: UUID, action: SharedTimerCommand.Action) {
    self.role = role
    self.sessionID = sessionID.uuidString
    self.action = action.rawValue
  }

  func perform() async throws -> some IntentResult {
    guard let sessionID = UUID(uuidString: sessionID),
      let action = SharedTimerCommand.Action(rawValue: action) else {
      return .result()
    }
    SharedTimerSnapshotStore.enqueue(SharedTimerCommand(role: role.timerRole, sessionID: sessionID, action: action))
    WidgetCenter.shared.reloadTimelines(ofKind: "JustAboutTimeWidget")
    return .result()
  }
}
