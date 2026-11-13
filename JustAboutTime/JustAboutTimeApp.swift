import AppKit
import CoreText
import SwiftUI

@main
struct JustAboutTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var historyStore: HistoryStore
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var preferencesStore = PreferencesStore()
    @StateObject private var timerCoordinator: TimerCoordinator
    @StateObject private var shortcutManager: ShortcutManager
    @StateObject private var updateManager = UpdateManager()
    private let windows: TimerWindows

    init() {
        let historyStore = HistoryStore()
        let notificationManager = NotificationManager()
        let preferencesStore = PreferencesStore()
        let timerCoordinator = TimerCoordinator(
            historyStore: historyStore,
            notificationManager: notificationManager,
            preferencesStore: preferencesStore
        )
        let updateManager = UpdateManager()
        let windows = TimerWindows(
            timerCoordinator: timerCoordinator,
            preferencesStore: preferencesStore,
            historyStore: historyStore,
            updateManager: updateManager
        )
        self.windows = windows
        _updateManager = StateObject(wrappedValue: updateManager)
        _historyStore = StateObject(wrappedValue: historyStore)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _timerCoordinator = StateObject(wrappedValue: timerCoordinator)
        _shortcutManager = StateObject(wrappedValue: ShortcutManager(timerCoordinator: timerCoordinator))
        NotificationCenter.default.addObserver(forName: .widgetURLRequested, object: nil, queue: .main) { notification in
            guard let url = notification.object as? URL else { return }
            Task { @MainActor in
                timerCoordinator.handleWidgetURL(url)
                if let role = timerCoordinator.consumeWidgetSetupRequest() {
                    windows.showControls(for: role)
                }
            }
        }
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            DistributedNotificationCenter.default().addObserver(forName: SharedTimerSnapshotStore.commandNotificationName, object: nil, queue: .main) { _ in
                timerCoordinator.consumeWidgetCommand()
            }
            timerCoordinator.consumeWidgetCommand()
        }

        Task { @MainActor [timerCoordinator, preferencesStore, updateManager] in
            Self.setupSystemObservers(timerCoordinator: timerCoordinator, preferencesStore: preferencesStore)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            updateManager.checkForUpdatesIfNeeded()
        }
    }

    @MainActor
    private static func setupSystemObservers(timerCoordinator: TimerCoordinator, preferencesStore: PreferencesStore) {
        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak timerCoordinator, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerCoordinator, let preferencesStore, preferencesStore.pauseOnScreenLocked else { return }
                timerCoordinator.systemPause()
            }
        }

        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak timerCoordinator, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerCoordinator, let preferencesStore, preferencesStore.resumeOnRelogin else { return }
                timerCoordinator.systemResume()
            }
        }

        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak timerCoordinator, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerCoordinator, let preferencesStore, preferencesStore.pauseOnScreenLocked else { return }
                timerCoordinator.systemPause()
            }
        }

        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak timerCoordinator, weak preferencesStore] _ in
            Task { @MainActor in
                guard let timerCoordinator, let preferencesStore, preferencesStore.resumeOnRelogin else { return }
                timerCoordinator.systemResume()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerCoordinator: timerCoordinator, preferencesStore: preferencesStore)
                .environmentObject(windows)
        } label: {
            StatusBarLabelView(timerCoordinator: timerCoordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)
                .environmentObject(updateManager)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldRestoreState(_ application: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { NotificationCenter.default.post(name: .widgetURLRequested, object: url) }
    }
}

extension Notification.Name { static let widgetURLRequested = Notification.Name("JustAboutTime.widgetURLRequested") }

enum HistoryWindow {
    static let id = "history"
}

enum AboutWindow {
    static let id = "about"
}

enum TimerWindow {
    static let id = "timer-controls"
}

// Menu-bar apps must not let SwiftUI choose a default window on activation.
@MainActor
final class TimerWindows: ObservableObject {
  private let timerCoordinator: TimerCoordinator
  private let preferencesStore: PreferencesStore
  private let historyStore: HistoryStore
  private let updateManager: UpdateManager
  private var controls: NSWindow?
  private var history: NSWindow?
  private var about: NSWindow?

  init(timerCoordinator: TimerCoordinator, preferencesStore: PreferencesStore,
       historyStore: HistoryStore, updateManager: UpdateManager) {
    self.timerCoordinator = timerCoordinator
    self.preferencesStore = preferencesStore
    self.historyStore = historyStore
    self.updateManager = updateManager
  }

  func showControls(for role: TimerRole) {
    if controls == nil {
      controls = makeWindow(
        title: "Timer Controls",
        content: TimerControlsView(timerCoordinator: timerCoordinator, preferencesStore: preferencesStore)
      )
    }
    controls?.setAccessibilityIdentifier("timer-controls-\(role.rawValue)")
    present(controls)
  }

  func showHistory() {
    if history == nil {
      history = makeWindow(
        title: "History",
        content: HistoryView(historyStore: historyStore, timerCoordinator: timerCoordinator),
        resizable: true
      )
      history?.setContentSize(NSSize(width: 740, height: 420))
    }
    historyStore.refresh()
    present(history)
  }

  func showAbout() {
    if about == nil {
      about = makeWindow(title: "About JustAboutTime", content: AboutView().environmentObject(updateManager))
    }
    present(about)
  }

  private func makeWindow<Content: View>(title: String, content: Content, resizable: Bool = false) -> NSWindow {
    let host = NSHostingController(rootView: content)
    let window = NSWindow(contentViewController: host)
    window.title = title
    window.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    window.setContentSize(host.view.fittingSize)
    window.center()
    return window
  }

  private func present(_ window: NSWindow?) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

private struct TimerControlsView: View {
  @ObservedObject var timerCoordinator: TimerCoordinator
  @ObservedObject var preferencesStore: PreferencesStore

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      TimerControlCard(timer: timerCoordinator.primaryTimer, preferencesStore: preferencesStore) {
        timerCoordinator.primaryTimer.finish()
      }
      .id(ObjectIdentifier(timerCoordinator.primaryTimer))

      if timerCoordinator.isSecondaryActivated {
        TimerControlCard(timer: timerCoordinator.secondaryTimer, preferencesStore: preferencesStore) {
          timerCoordinator.deactivateSecondary()
        }
        .id(ObjectIdentifier(timerCoordinator.secondaryTimer))
      } else {
        Button {
          timerCoordinator.activateSecondary()
        } label: {
          Label("Add Secondary Timer", systemImage: "plus.circle")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 8)
      }
    }
    .padding(18)
    .frame(width: 400)
  }
}

private struct TimerControlCard: View {
  @ObservedObject var timer: TimerStore
  @ObservedObject var preferencesStore: PreferencesStore
  let finish: () -> Void

  private var snapshot: SharedTimerSnapshot { timer.sharedSnapshot() }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(timer.role.displayName, systemImage: "timer").font(.headline)
        Spacer()
        Text(snapshot.statusLabel).font(.caption).foregroundStyle(.secondary)
      }

      Text(snapshot.formattedValue(at: .now))
        .font(.system(size: 42, weight: .medium, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText())
        .lineLimit(1)
        .minimumScaleFactor(0.6)

      if let progress = snapshot.progress {
        ProgressView(value: progress, total: 1).tint(.accentColor)
      }

      HStack(spacing: 8) {
        if snapshot.availableActions.contains(.pause) {
          Button(action: timer.pause) { Label("Pause", systemImage: "pause.fill") }
            .buttonStyle(.borderedProminent)
        } else if snapshot.availableActions.contains(.resume) {
          Button(action: timer.resume) { Label("Resume", systemImage: "play.fill") }
            .buttonStyle(.borderedProminent)
        }
        if snapshot.availableActions.contains(.finish) {
          Button(action: finish) { Label("Finish", systemImage: "checkmark") }
        }
        if snapshot.availableActions.contains(.repeatLast) {
          Button(action: timer.repeatLastTimer) { Label("Repeat", systemImage: "arrow.clockwise") }
        }
        Spacer(minLength: 0)
        Menu {
          ForEach(preferencesStore.presetDurations(for: timer.role), id: \.self) { duration in
            Button("\(Int(duration / 60)) min countdown") { timer.startCountdown(duration: duration) }
          }
          Button("Count Up", action: timer.startCountUp)
        } label: {
          Label(snapshot.state == .idle ? "Start" : "New", systemImage: "plus")
        }
        .fixedSize()
      }
      .controlSize(.regular)
    }
    .padding(16)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(timer.role.displayName) timer")
  }
}

private struct StatusBarLabelView: View {
    @ObservedObject var timerCoordinator: TimerCoordinator

    var body: some View {
        statusLabel
    }

    private var statusLabel: some View {
        StatusBarTimerContentView(
            primaryTimer: timerCoordinator.primaryTimer,
            secondaryTimer: timerCoordinator.secondaryTimer,
            isSecondaryActivated: timerCoordinator.isSecondaryActivated
        )
    }
}

private struct StatusBarTimerContentView: View {
    @ObservedObject var primaryTimer: TimerStore
    @ObservedObject var secondaryTimer: TimerStore
    let isSecondaryActivated: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var primaryPillOpacity = 0.0
    @State private var secondaryPillOpacity = 0.0

    var body: some View {
        Image(nsImage: StatusBarLabelImageRenderer.image(
            primaryPresentation: primaryTimer.statusPresentation,
            primaryProgress: primaryTimer.countdownProgress,
            secondaryPresentation: isSecondaryActivated ? secondaryTimer.statusPresentation : nil,
            secondaryProgress: isSecondaryActivated ? secondaryTimer.countdownProgress : nil,
            colorScheme: colorScheme,
            primaryPillOpacity: primaryPillOpacity,
            secondaryPillOpacity: secondaryPillOpacity
        ))
            // MenuBarExtra hosts this label in an NSStatusBarButton whose native
            // content margins otherwise make the clickable/highlighted area wider
            // than the rendered pill. Keep the image canvas and pill geometry intact.
            .padding(.horizontal, -StatusBarLabelImageRenderer.statusButtonHorizontalInset)
            .accessibilityLabel(accessibilityLabel)
            .task(id: animationKey(primaryTimer.statusPresentation.urgency)) {
                await animatePill(primaryTimer.statusPresentation.urgency, opacity: $primaryPillOpacity)
            }
            .task(id: animationKey(isSecondaryActivated ? secondaryTimer.statusPresentation.urgency : .neutral)) {
                await animatePill(isSecondaryActivated ? secondaryTimer.statusPresentation.urgency : .neutral, opacity: $secondaryPillOpacity)
            }
    }

    private func animationKey(_ urgency: TimerUrgency) -> String {
        "\(urgency)-\(reduceMotion)"
    }

    @MainActor
    private func animatePill(_ urgency: TimerUrgency, opacity: Binding<Double>) async {
        let start = Date()
        let initialOpacity = opacity.wrappedValue
        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(start)
            let target = urgency.opacity(at: max(0, elapsed - 0.25), reduceMotion: reduceMotion)
            let fraction = min(1, elapsed / 0.25)
            let eased = (1 - cos(.pi * fraction)) / 2
            opacity.wrappedValue = initialOpacity + (target - initialOpacity) * eased
            if fraction == 1 && (urgency != .warning || reduceMotion) { return }
            do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
        }
    }

    private var accessibilityLabel: String {
        var descriptions = [timerDescription(primaryTimer, role: .primary)]
        if isSecondaryActivated {
            descriptions.append(timerDescription(secondaryTimer, role: .secondary))
        }
        return descriptions.joined(separator: ". ")
    }

    private func timerDescription(_ timer: TimerStore, role: TimerRole) -> String {
        let state: String
        if let session = timer.activeSession {
            switch session.phase {
            case .runningCountdown, .runningCountUp:
                state = "running"
            case .pausedCountdown, .pausedCountUp:
                state = "paused"
            }
        } else if timer.latestEvent == .countdownCompleted {
            state = "completed"
        } else {
            state = "idle"
        }
        return "\(role.displayName) timer \(state), \(timer.statusText)"
    }
}

enum StatusBarLabelImageRenderer {
    private enum Layout {
        static let dotDiameter = 6.0
        static let dotSpacing = 3.0
        static let pauseBarWidth = 2.0
        static let progressHeight = 3.0
        static let progressSpacing = 1.0
        static let progressInset = 1.0
        // Keep each dual pill separated after adding the rounded-end clearance.
        static let progressGap = 12.0
        static let secondarySpacing = 2.0
        // Keep progress track ends inside the compact rounded corners.
        static let pillHorizontalPadding = 4.0
        static let pillVerticalPadding = 1.0
    }

    // Match the native system size while keeping the existing compact row layout.
    static let timerFontSize = NSFont.systemFontSize
    // The native MenuBarExtra status button contributes this inset on each side.
    static let statusButtonHorizontalInset: CGFloat = 10

    static func image(
        primaryPresentation: TimerStatusPresentation,
        primaryProgress: CountdownProgressPresentation?,
        secondaryPresentation: TimerStatusPresentation?,
        secondaryProgress: CountdownProgressPresentation?,
        colorScheme: ColorScheme,
        primaryPillOpacity: Double = 0,
        secondaryPillOpacity: Double = 0
    ) -> NSImage {
        let needsOriginalColor = primaryPillOpacity > 0 || secondaryPillOpacity > 0 || usesOriginalColor(
            presentation: primaryPresentation,
            progress: primaryProgress
        ) || secondaryPresentation.map {
            usesOriginalColor(presentation: $0, progress: secondaryProgress)
        } == true
        let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor
        let primaryTextColor = primaryPresentation.urgency == .overdue ? NSColor.white : primaryColor
        let compactFontSize = timerFontSize
        let primaryAttributes = textAttributes(
            font: NSFont.monospacedDigitSystemFont(
                ofSize: compactFontSize,
                weight: .regular
            ),
            foregroundColor: primaryTextColor
        )
        let primaryTextSize = primaryPresentation.text.size(withAttributes: primaryAttributes)
        // Layout from actual glyph bounds. Dot slots remain reserved even when hidden,
        // so animation changes never move the text or adjacent status items.
        let primaryRowSize = rowGeometry(text: primaryPresentation.text, attributes: primaryAttributes, textSize: primaryTextSize).rowSize

        let secondaryAttributes: [NSAttributedString.Key: Any]?
        let secondaryTextSize: NSSize?
        let secondaryLayoutSize: NSSize?
        if let secondaryPresentation {
            let secondaryTextColor = secondaryPresentation.urgency == .overdue ? NSColor.white : primaryColor
            let attributes = textAttributes(
                font: NSFont.monospacedDigitSystemFont(ofSize: compactFontSize, weight: .regular),
                foregroundColor: secondaryTextColor
            )
            secondaryAttributes = attributes
            secondaryTextSize = secondaryPresentation.text.size(withAttributes: attributes)
            secondaryLayoutSize = secondaryTextSize
        } else {
            secondaryAttributes = nil
            secondaryTextSize = nil
            secondaryLayoutSize = nil
        }

        let dualCellWidth = secondaryLayoutSize.map {
            max(34, max(primaryRowSize.width, rowGeometry(text: secondaryPresentation?.text ?? "", attributes: secondaryAttributes ?? [:], textSize: $0).rowSize.width))
        }
        let combinedRowWidth = dualCellWidth.map {
            $0 * 2 + Layout.progressGap
        } ?? primaryRowSize.width
        let textRowHeight = max(primaryRowSize.height, secondaryTextSize?.height ?? 0)
        let hasProgress = primaryProgress != nil || secondaryProgress != nil
        let progressHeight = hasProgress ? Layout.progressSpacing + Layout.progressHeight : 0
        // The image and pill enclose one bounded content unit: text row, progress track,
        // and clearance on every side. This keeps the track from protruding below the pill.
        let imageSize = NSSize(
            width: combinedRowWidth + Layout.pillHorizontalPadding * 2,
            height: textRowHeight + progressHeight + Layout.pillVerticalPadding * 2
        )
        let image = NSImage(size: imageSize)
        image.isTemplate = !needsOriginalColor

        image.lockFocus()
        defer { image.unlockFocus() }

        let rowOriginX = (imageSize.width - combinedRowWidth) / 2
        let cellWidth = dualCellWidth ?? combinedRowWidth
        drawPill(opacity: primaryPillOpacity, in: NSRect(
            x: rowOriginX - Layout.pillHorizontalPadding,
            y: 0,
            width: cellWidth + Layout.pillHorizontalPadding * 2,
            height: imageSize.height
        ))
        if secondaryPresentation != nil {
            drawPill(opacity: secondaryPillOpacity, in: NSRect(
                x: rowOriginX + cellWidth + Layout.progressGap - Layout.pillHorizontalPadding,
                y: 0,
                width: cellWidth + Layout.pillHorizontalPadding * 2,
                height: imageSize.height
            ))
        }
        if let secondaryPresentation, let secondaryAttributes, let secondaryTextSize, let dualCellWidth {
            for (presentation, attributes, textSize, x) in [
                (primaryPresentation, primaryAttributes, primaryTextSize, rowOriginX),
                (secondaryPresentation, secondaryAttributes, secondaryTextSize, rowOriginX + dualCellWidth + Layout.progressGap)
            ] {
                drawStatusRow(presentation: presentation, attributes: attributes, textSize: textSize,
                              rowSize: NSSize(width: dualCellWidth, height: textRowHeight), rowOriginX: x,
                              rowHeight: textRowHeight, progressHeight: progressHeight,
                              textColor: presentation.urgency == .overdue ? .white : primaryColor)
            }
        } else {
            drawStatusRow(
                presentation: primaryPresentation,
                attributes: primaryAttributes,
                textSize: primaryTextSize,
                rowSize: primaryRowSize,
                rowOriginX: rowOriginX,
                rowHeight: textRowHeight,
                progressHeight: progressHeight,
                textColor: primaryTextColor
            )
        }

        if secondaryPresentation != nil {
            let barWidth = (combinedRowWidth - Layout.progressGap) / 2
            if let primaryProgress {
                drawProgress(primaryProgress, primaryColor: primaryTextColor, in: NSRect(x: rowOriginX + Layout.progressInset, y: Layout.pillVerticalPadding + 1, width: barWidth - Layout.progressInset * 2, height: Layout.progressHeight))
            }
            if let secondaryProgress {
                drawProgress(secondaryProgress, primaryColor: secondaryPresentation?.urgency == .overdue ? .white : primaryColor, in: NSRect(x: rowOriginX + barWidth + Layout.progressGap + Layout.progressInset, y: Layout.pillVerticalPadding + 1, width: barWidth - Layout.progressInset * 2, height: Layout.progressHeight))
            }
        } else if let primaryProgress {
            drawProgress(primaryProgress, primaryColor: primaryTextColor, in: NSRect(x: rowOriginX + Layout.progressInset, y: Layout.pillVerticalPadding + 1, width: combinedRowWidth - Layout.progressInset * 2, height: Layout.progressHeight))
        }

        return image
    }

    struct RenderedRowGeometry {
        let rowSize: NSSize
        let textInkBounds: NSRect
        let textOrigin: NSPoint
        let leadingDot: NSRect
        let trailingDot: NSRect
    }

    static func rowGeometry(text: String, attributes: [NSAttributedString.Key: Any], textSize: NSSize) -> RenderedRowGeometry {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let inkBounds = CTLineGetImageBounds(line, nil)
        let rowWidth = Layout.secondarySpacing * 2 + Layout.dotDiameter * 2 + Layout.dotSpacing * 2 + inkBounds.width
        let rowSize = NSSize(width: rowWidth, height: max(Layout.dotDiameter, textSize.height) + Layout.pillVerticalPadding * 2)
        let textOrigin = NSPoint(x: Layout.secondarySpacing + Layout.dotDiameter + Layout.dotSpacing - inkBounds.minX, y: 0)
        let leadingDot = NSRect(x: Layout.secondarySpacing, y: 0, width: Layout.dotDiameter, height: Layout.dotDiameter)
        let trailingDot = NSRect(x: textOrigin.x + inkBounds.maxX + Layout.dotSpacing, y: 0, width: Layout.dotDiameter, height: Layout.dotDiameter)
        return RenderedRowGeometry(rowSize: rowSize, textInkBounds: inkBounds, textOrigin: textOrigin, leadingDot: leadingDot, trailingDot: trailingDot)
    }

    private static func usesOriginalColor(
        presentation: TimerStatusPresentation,
        progress: CountdownProgressPresentation?
    ) -> Bool {
        presentation.urgency != .neutral || progress?.fillStyle.requiresOriginalColor == true
    }

    private static func drawPill(opacity: Double, in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(NSColor(srgbRed: 1, green: 0.15, blue: 0.12, alpha: opacity).cgColor)
        context.addPath(RoundedRectangle(cornerRadius: 6, style: .continuous).path(in: rect).cgPath)
        context.fillPath()
    }

    private static func menuBarPrimaryColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? .white : .black
    }

    private static func textAttributes(
        font: NSFont,
        foregroundColor: NSColor
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: foregroundColor
        ]
    }

    private static func drawStatusRow(
        presentation: TimerStatusPresentation,
        attributes: [NSAttributedString.Key: Any],
        textSize: NSSize,
        rowSize: NSSize,
        rowOriginX: CGFloat,
        rowHeight: CGFloat,
        progressHeight: CGFloat,
        textColor: NSColor
    ) {
        let rowOriginY = Layout.pillVerticalPadding + progressHeight + (rowHeight - rowSize.height) / 2
        let indicatorY = rowOriginY + (rowSize.height - Layout.dotDiameter) / 2
        let geometry = rowGeometry(text: presentation.text, attributes: attributes, textSize: textSize)
        let rowOffsetX = rowOriginX + (rowSize.width - geometry.rowSize.width) / 2
        let textOrigin = NSPoint(
            x: rowOffsetX + geometry.textOrigin.x,
            y: rowOriginY + (rowSize.height - textSize.height) / 2
        )

        drawLeadingIndicator(
            presentation.dotPhase,
            color: indicatorColor(for: presentation.urgency, base: textColor),
            in: NSRect(
                x: rowOffsetX + geometry.leadingDot.minX,
                y: indicatorY,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )

        presentation.text.draw(at: textOrigin, withAttributes: attributes)

        let trailingColor = indicatorColor(for: presentation.urgency, base: textColor)
        drawDot(
            isVisible: presentation.dotPhase == .trailing || presentation.dotPhase == .trailingRed,
            color: trailingColor,
            in: NSRect(
                x: textOrigin.x + geometry.textInkBounds.maxX + Layout.dotSpacing,
                y: indicatorY,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )
    }

    private static func drawProgress(_ progress: CountdownProgressPresentation, primaryColor: NSColor, in rect: NSRect) {
        let outlineRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let outlinePath = NSBezierPath(roundedRect: outlineRect, xRadius: outlineRect.height / 2, yRadius: outlineRect.height / 2)
        primaryColor.setStroke()
        outlinePath.lineWidth = 1
        outlinePath.stroke()
        guard progress.isFillVisible else { return }
        let fillRect = outlineRect.insetBy(dx: Layout.progressInset, dy: 0.5)
        let fillWidth = fillRect.width * min(1, max(0, progress.fractionComplete))
        guard fillWidth > 0 else { return }
        let fillPath = NSBezierPath(roundedRect: NSRect(x: fillRect.minX, y: fillRect.minY, width: fillWidth, height: fillRect.height), xRadius: fillRect.height / 2, yRadius: fillRect.height / 2)
        switch progress.fillStyle {
        case .solid:
            primaryColor.withAlphaComponent(0.75).setFill()
            fillPath.fill()
        case .appIconGradient:
            drawAppIconGradientFill(in: fillPath, rect: fillRect)
        }
    }

    private static func drawAppIconGradientFill(in path: NSBezierPath, rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        path.addClip()
        appIconGradient.draw(in: rect, angle: 0)
    }

    private static var appIconGradient: NSGradient {
        let iconBlue = NSColor(red: 0.22, green: 0.44, blue: 1.0, alpha: 1.0)
        let iconPink = NSColor(red: 1.0, green: 0.25, blue: 0.82, alpha: 1.0)
        return NSGradient(colors: [iconBlue, iconPink]) ?? NSGradient(colors: [.systemBlue, .systemPink])!
    }

    static func indicatorColor(for urgency: TimerUrgency, base: NSColor) -> NSColor {
        // Indicators stay white in every urgency state; urgency is conveyed by the pill.
        .white
    }

    private static func drawDot(isVisible: Bool, color: NSColor = .labelColor, in rect: NSRect) {
        guard isVisible else {
            return
        }

        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private static func drawLeadingIndicator(_ dotPhase: DotPhase, color: NSColor, in rect: NSRect) {
        switch dotPhase {
        case .leading:
            drawDot(isVisible: true, color: color, in: rect)
        case .leadingRed:
            drawDot(isVisible: true, color: .white, in: rect)
        case .leadingSquare:
            drawSquare(color: color, in: rect)
        case .leadingPause:
            drawPauseBars(color: color, in: rect)
        case .trailing, .trailingRed:
            return
        case .hidden:
            return
        }
    }

    private static func drawSquare(color: NSColor, in rect: NSRect) {
        color.setFill()
        NSBezierPath(rect: rect).fill()
    }

    private static func drawPauseBars(color: NSColor, in rect: NSRect) {
        let gap = rect.width - Layout.pauseBarWidth * 2
        let leftRect = NSRect(x: rect.minX, y: rect.minY, width: Layout.pauseBarWidth, height: rect.height)
        let rightRect = NSRect(x: rect.minX + Layout.pauseBarWidth + gap, y: rect.minY, width: Layout.pauseBarWidth, height: rect.height)

        color.setFill()
        NSBezierPath(rect: leftRect).fill()
        NSBezierPath(rect: rightRect).fill()
    }
}

private extension ProgressFillStyle {
    var requiresOriginalColor: Bool {
        switch self {
        case .solid: return false
        case .appIconGradient: return true
        }
    }
}
