import AppKit
import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var historyStore: HistoryStore
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var preferencesStore = PreferencesStore()
    @StateObject private var timerCoordinator: TimerCoordinator
    @StateObject private var shortcutManager: ShortcutManager
    @StateObject private var updateManager = UpdateManager()

    init() {
        let historyStore = HistoryStore()
        let notificationManager = NotificationManager()
        let preferencesStore = PreferencesStore()
        let timerCoordinator = TimerCoordinator(
            historyStore: historyStore,
            notificationManager: notificationManager,
            preferencesStore: preferencesStore
        )
        _historyStore = StateObject(wrappedValue: historyStore)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _timerCoordinator = StateObject(wrappedValue: timerCoordinator)
        _shortcutManager = StateObject(wrappedValue: ShortcutManager(timerCoordinator: timerCoordinator))

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
        } label: {
            StatusBarLabelView(timerCoordinator: timerCoordinator)
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: HistoryWindow.id) {
            HistoryView(historyStore: historyStore, timerCoordinator: timerCoordinator)
        }

        Window("About JustAboutTime", id: AboutWindow.id) {
            AboutView()
                .environmentObject(updateManager)
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesView(preferencesStore: preferencesStore, notificationManager: notificationManager)
        }
    }
}

enum HistoryWindow {
    static let id = "history"
}

enum AboutWindow {
    static let id = "about"
}

private struct StatusBarLabelView: View {
    @ObservedObject var timerCoordinator: TimerCoordinator

    var body: some View {
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
        static let dotSpacing = 4.0
        static let pauseBarWidth = 2.0
        static let progressHeight = 3.0
        static let progressSpacing = 1.0
        static let progressInset = 1.0
        static let progressGap = 3.0
        static let secondarySpacing = 5.0
        static let pillVerticalPadding = 1.0
    }

    // Match the native system size while keeping the existing compact row layout.
    static let timerFontSize = NSFont.systemFontSize

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
        // Reserve the overtime prefix before the deadline so urgency does not move adjacent items.
        let primaryLayoutSize = reservedTextSize(primaryPresentation.text, attributes: primaryAttributes)
        let primaryRowSize = rowSize(textSize: primaryLayoutSize)

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
            secondaryLayoutSize = reservedTextSize(secondaryPresentation.text, attributes: attributes)
        } else {
            secondaryAttributes = nil
            secondaryTextSize = nil
            secondaryLayoutSize = nil
        }

        let dualCellWidth = secondaryLayoutSize.map {
            max(34, max(primaryRowSize.width, rowSize(textSize: $0).width))
        }
        let combinedRowWidth = dualCellWidth.map {
            $0 * 2 + Layout.progressGap
        } ?? primaryRowSize.width
        let textRowHeight = max(primaryRowSize.height, secondaryTextSize?.height ?? 0)
        let hasProgress = primaryProgress != nil || secondaryProgress != nil
        let progressHeight = hasProgress ? Layout.progressSpacing + Layout.progressHeight : 0
        let progressWidth = max(34, combinedRowWidth)
        let imageSize = NSSize(width: max(combinedRowWidth, progressWidth), height: textRowHeight + progressHeight)
        let image = NSImage(size: imageSize)
        image.isTemplate = !needsOriginalColor

        image.lockFocus()
        defer { image.unlockFocus() }

        let rowOriginX = (imageSize.width - combinedRowWidth) / 2
        let cellWidth = dualCellWidth ?? combinedRowWidth
        drawPill(opacity: primaryPillOpacity, in: NSRect(x: rowOriginX, y: 0, width: cellWidth, height: imageSize.height))
        if secondaryPresentation != nil {
            drawPill(opacity: secondaryPillOpacity, in: NSRect(x: rowOriginX + cellWidth + Layout.progressGap, y: 0, width: cellWidth, height: imageSize.height))
        }
        if let secondaryPresentation, let secondaryAttributes, let secondaryTextSize, let dualCellWidth {
            for (presentation, attributes, textSize, x) in [
                (primaryPresentation, primaryAttributes, primaryTextSize, rowOriginX),
                (secondaryPresentation, secondaryAttributes, secondaryTextSize, rowOriginX + dualCellWidth + Layout.progressGap)
            ] {
                drawStatusRow(presentation: presentation, attributes: attributes, textSize: textSize,
                              rowSize: NSSize(width: dualCellWidth, height: textRowHeight), rowOriginX: x,
                              rowHeight: textRowHeight, progressHeight: progressHeight,
                              primaryColor: primaryColor, textColor: presentation.urgency == .overdue ? .white : primaryColor)
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
                primaryColor: primaryColor,
                textColor: primaryTextColor
            )
        }

        if secondaryPresentation != nil {
            let barWidth = (progressWidth - Layout.progressGap) / 2
            if let primaryProgress {
                drawProgress(
                    primaryProgress,
                    primaryColor: primaryTextColor,
                    in: NSRect(x: 10, y: 2, width: barWidth - 20, height: Layout.progressHeight)
                )
            }
            if let secondaryProgress {
                drawProgress(
                    secondaryProgress,
                    primaryColor: secondaryPresentation?.urgency == .overdue ? .white : primaryColor,
                    in: NSRect(
                        x: barWidth + Layout.progressGap + 10,
                        y: 2,
                        width: barWidth - 20,
                        height: Layout.progressHeight
                    )
                )
            }
        } else if let primaryProgress {
            drawProgress(
                primaryProgress,
                primaryColor: primaryTextColor,
                in: NSRect(x: 10, y: 2, width: progressWidth - 20, height: Layout.progressHeight)
            )
        }

        return image
    }

    private static func reservedTextSize(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSSize {
        (text.hasPrefix("+") ? text : "+" + text).size(withAttributes: attributes)
    }

    private static func rowSize(textSize: NSSize) -> NSSize {
        NSSize(
            width: Layout.dotDiameter * 2 + Layout.dotSpacing * 2 + textSize.width + Layout.secondarySpacing * 2,
            height: max(Layout.dotDiameter, textSize.height) + Layout.pillVerticalPadding * 2
        )
    }

    private static func usesOriginalColor(
        presentation: TimerStatusPresentation,
        progress: CountdownProgressPresentation?
    ) -> Bool {
        presentation.urgency != .neutral ||
            progress?.fillStyle.requiresOriginalColor == true
    }

    private static func drawPill(opacity: Double, in rect: NSRect) {
        NSColor(srgbRed: 0.65, green: 0.04, blue: 0.08, alpha: opacity).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
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
        primaryColor: NSColor,
        textColor: NSColor
    ) {
        let rowOriginY = progressHeight + (rowHeight - rowSize.height) / 2
        let indicatorY = rowOriginY + (rowSize.height - Layout.dotDiameter) / 2
        let textOrigin = NSPoint(
            x: rowOriginX + (rowSize.width - textSize.width) / 2,
            y: rowOriginY + (rowSize.height - textSize.height) / 2
        )

        drawLeadingIndicator(
            presentation.dotPhase,
            color: textColor,
            in: NSRect(
                x: rowOriginX + Layout.secondarySpacing,
                y: indicatorY,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )

        presentation.text.draw(at: textOrigin, withAttributes: attributes)

        drawDot(
            isVisible: presentation.dotPhase == .trailing,
            color: primaryColor,
            in: NSRect(
                x: textOrigin.x + textSize.width + Layout.dotSpacing,
                y: indicatorY,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )
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
        case .leadingSquare:
            drawSquare(color: color, in: rect)
        case .leadingPause:
            drawPauseBars(color: color, in: rect)
        case .hidden, .trailing:
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

    private static func drawProgress(_ progress: CountdownProgressPresentation, primaryColor: NSColor, in rect: NSRect) {
        let outlineRect = rect.insetBy(dx: 0.5, dy: 0.5)
        let progressColor = primaryColor
        let outlinePath = NSBezierPath(
            roundedRect: outlineRect,
            xRadius: outlineRect.height / 2,
            yRadius: outlineRect.height / 2
        )

        progressColor.setStroke()
        outlinePath.lineWidth = 1
        outlinePath.stroke()

        guard progress.isFillVisible else {
            return
        }

        let fillRect = outlineRect.insetBy(dx: Layout.progressInset, dy: 0.5)
        let fillWidth = fillRect.width * min(1, max(0, progress.fractionComplete))
        guard fillWidth > 0 else {
            return
        }

        let fillPath = NSBezierPath(
            roundedRect: NSRect(x: fillRect.minX, y: fillRect.minY, width: fillWidth, height: fillRect.height),
            xRadius: fillRect.height / 2,
            yRadius: fillRect.height / 2
        )

        switch progress.fillStyle {
        case .solid:
            progressColor.withAlphaComponent(0.75).setFill()
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
}

private extension ProgressFillStyle {
    var requiresOriginalColor: Bool {
        switch self {
        case .solid:
            return false
        case .appIconGradient:
            return true
        }
    }
}
