import AppIntents
import SwiftUI
import WidgetKit

struct TimerWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Timer Widget"
    static let description = IntentDescription("Choose the timer shown in a small widget.")
    @Parameter(title: "Role") var role: WidgetTimerRole
    init() { role = .primary }
}

struct TimerWidgetEntry: TimelineEntry {
    let date: Date
    let snapshots: [TimerRole: SharedTimerSnapshot]
    let configuration: TimerWidgetConfigurationIntent
}

struct TimerWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TimerWidgetEntry { TimerWidgetEntry(date: .now, snapshots: [:], configuration: TimerWidgetConfigurationIntent()) }

    func snapshot(for configuration: TimerWidgetConfigurationIntent, in context: Context) async -> TimerWidgetEntry {
        makeEntry(configuration: configuration, date: .now)
    }

    func timeline(for configuration: TimerWidgetConfigurationIntent, in context: Context) async -> Timeline<TimerWidgetEntry> {
        let now = Date()
        let entry = makeEntry(configuration: configuration, date: now)
        var entries = [entry]
        for target in Set(entry.snapshots.values.compactMap(\.targetDate).filter({ $0 > now })).sorted() {
            entries.append(makeEntry(configuration: configuration, date: target))
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(60)))
    }

    private func makeEntry(configuration: TimerWidgetConfigurationIntent, date: Date) -> TimerWidgetEntry {
        let snapshots = SharedTimerSnapshotStore.load().mapValues { $0.reconciled(at: date) }
        return TimerWidgetEntry(date: date, snapshots: snapshots, configuration: configuration)
    }
}

struct TimerWidgetView: View {
  let entry: TimerWidgetEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    Group {
      if family == .systemMedium {
        HStack(spacing: 16) {
          timer(.primary)
          Divider()
          timer(.secondary)
        }
      } else {
        timer(entry.configuration.role.timerRole)
      }
    }
    .widgetURL(setupURL(for: family == .systemMedium ? .primary : entry.configuration.role.timerRole))
  }

  private func setupURL(for role: TimerRole) -> URL {
    URL(string: "justabouttime://setup/\(role.rawValue)")!
  }

  @ViewBuilder private func timer(_ role: TimerRole) -> some View {
    let snapshot = entry.snapshots[role]
    VStack(alignment: .leading, spacing: 8) {
      Text(role.displayName.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
      if let snapshot, snapshot.state != .idle {
        timeView(snapshot)
          .font(.system(size: 32, weight: .medium, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.55)
        Text(snapshot.statusLabel).font(.caption2).foregroundStyle(.secondary)
        if let progress = snapshot.progress(at: entry.date) {
          if snapshot.state == .running, let target = snapshot.targetDate, let duration = snapshot.originalDuration {
            ProgressView(timerInterval: target.addingTimeInterval(-duration)...target, countsDown: true)
              .labelsHidden()
              .tint(.accentColor)
          } else {
            ProgressView(value: progress, total: 1).tint(.accentColor)
          }
        }
      } else {
        Text("Ready").font(.system(.title2, design: .rounded, weight: .medium))
        Text(role == .secondary && snapshot == nil ? "Add a second timer" : "Start your next timer")
          .font(.caption2).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if let snapshot, !snapshot.availableActions.isEmpty {
        HStack(spacing: 6) {
          ForEach(snapshot.availableActions, id: \.rawValue) { action in
            actionButton(role: role, snapshot: snapshot, action: action)
          }
        }
      } else {
        Link(destination: setupURL(for: role)) {
          Label("Set timer", systemImage: "plus")
        }
        .font(.caption)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(role.displayName) timer")
  }

  private func actionButton(role: TimerRole, snapshot: SharedTimerSnapshot, action: SharedTimerCommand.Action) -> some View {
    let title: String
    let image: String
    switch action {
    case .pause: title = "Pause"; image = "pause.fill"
    case .resume: title = "Resume"; image = "play.fill"
    case .finish: title = "Finish"; image = "checkmark"
    case .repeatLast: title = "Repeat"; image = "arrow.clockwise"
    }
    return Button(intent: TimerActionIntent(role: role == .primary ? .primary : .secondary, sessionID: snapshot.sessionID, action: action)) {
      if action == .finish {
        Image(systemName: image)
      } else {
        Label(title, systemImage: image)
      }
    }
    .font(.caption)
    .buttonStyle(.bordered)
    .accessibilityLabel("\(title) \(role.displayName) timer")
  }

  @ViewBuilder private func timeView(_ snapshot: SharedTimerSnapshot) -> some View {
    if (snapshot.state == .running || snapshot.state == .overdue), snapshot.frozenSeconds == nil, let date = snapshot.displayDate {
      Text(date, style: .timer)
    } else {
      Text(snapshot.formattedValue(at: entry.date))
    }
  }
}

struct JustAboutTimeWidget: Widget {
    let kind = "JustAboutTimeWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: TimerWidgetConfigurationIntent.self, provider: TimerWidgetProvider()) { entry in
            TimerWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Timers")
        .description("Primary and Secondary timers")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct JustAboutTimeWidgetBundle: WidgetBundle {
    var body: some Widget { JustAboutTimeWidget() }
}
