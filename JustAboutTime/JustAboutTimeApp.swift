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

    var body: some View {
        Image(nsImage: StatusBarLabelImageRenderer.image(
            primaryPresentation: primaryTimer.statusPresentation,
            primaryProgress: primaryTimer.countdownProgress,
            secondaryPresentation: isSecondaryActivated ? secondaryTimer.statusPresentation : nil,
            secondaryProgress: isSecondaryActivated ? secondaryTimer.countdownProgress : nil,
            colorScheme: colorScheme
        ))
            .accessibilityLabel(accessibilityLabel)
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

private enum StatusBarLabelImageRenderer {
    private enum Layout {
        static let dotDiameter = 6.0
        static let dotSpacing = 4.0
        static let pauseBarWidth = 2.0
        static let progressHeight = 5.0
        static let progressSpacing = 1.0
        static let progressInset = 1.0
        static let progressGap = 3.0
        static let secondarySpacing = 2.0
    }

    static func image(
        primaryPresentation: TimerStatusPresentation,
        primaryProgress: CountdownProgressPresentation?,
        secondaryPresentation: TimerStatusPresentation?,
        secondaryProgress: CountdownProgressPresentation?,
        colorScheme: ColorScheme
    ) -> NSImage {
        let isDualTimer = secondaryPresentation != nil
        let needsOriginalColor = usesOriginalColor(
            presentation: primaryPresentation,
            progress: primaryProgress
        ) || secondaryPresentation.map {
            usesOriginalColor(presentation: $0, progress: secondaryProgress)
        } == true
        let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor
        let primaryTextColor = primaryProgress?.isBlinking == true ? NSColor.systemRed : primaryColor
        let compactFontSize = NSFont.systemFontSize - 2
        let primaryAttributes = textAttributes(
            font: NSFont.monospacedDigitSystemFont(
                ofSize: isDualTimer ? compactFontSize : NSFont.systemFontSize,
                weight: .regular
            ),
            foregroundColor: primaryTextColor
        )
        let primaryTextSize = primaryPresentation.text.size(withAttributes: primaryAttributes)
        let primaryRowSize = rowSize(textSize: primaryTextSize)

        let secondaryAttributes: [NSAttributedString.Key: Any]?
        let secondaryTextSize: NSSize?
        if let secondaryPresentation {
            let secondaryTextColor = secondaryProgress?.isBlinking == true ? NSColor.systemRed : primaryColor
            let attributes = textAttributes(
                font: NSFont.monospacedDigitSystemFont(ofSize: compactFontSize, weight: .regular),
                foregroundColor: secondaryTextColor
            )
            secondaryAttributes = attributes
            secondaryTextSize = secondaryPresentation.text.size(withAttributes: attributes)
        } else {
            secondaryAttributes = nil
            secondaryTextSize = nil
        }

        let dualCellWidth = secondaryTextSize.map {
            max(34, max(primaryTextSize.width, $0.width) + Layout.secondarySpacing * 2)
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
        if let secondaryPresentation, let secondaryAttributes, let secondaryTextSize, let dualCellWidth {
            drawDualTextRow(
                primaryText: primaryPresentation.text,
                primaryAttributes: primaryAttributes,
                primaryTextSize: primaryTextSize,
                secondaryText: secondaryPresentation.text,
                secondaryAttributes: secondaryAttributes,
                secondaryTextSize: secondaryTextSize,
                cellWidth: dualCellWidth,
                rowOriginX: rowOriginX,
                rowHeight: textRowHeight,
                progressHeight: progressHeight
            )
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
                    primaryColor: primaryColor,
                    in: NSRect(x: 0, y: 0, width: barWidth, height: Layout.progressHeight)
                )
            }
            if let secondaryProgress {
                drawProgress(
                    secondaryProgress,
                    primaryColor: primaryColor,
                    in: NSRect(
                        x: barWidth + Layout.progressGap,
                        y: 0,
                        width: barWidth,
                        height: Layout.progressHeight
                    )
                )
            }
        } else if let primaryProgress {
            drawProgress(
                primaryProgress,
                primaryColor: primaryColor,
                in: NSRect(x: 0, y: 0, width: progressWidth, height: Layout.progressHeight)
            )
        }

        return image
    }

    private static func rowSize(textSize: NSSize) -> NSSize {
        NSSize(
            width: Layout.dotDiameter * 2 + Layout.dotSpacing * 2 + textSize.width,
            height: max(Layout.dotDiameter, textSize.height)
        )
    }

    private static func usesOriginalColor(
        presentation: TimerStatusPresentation,
        progress: CountdownProgressPresentation?
    ) -> Bool {
        presentation.dotPhase == .leadingRed ||
            presentation.dotPhase == .trailingRed ||
            progress?.isWarning == true ||
            progress?.isBlinking == true ||
            progress?.fillStyle.requiresOriginalColor == true
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
            x: rowOriginX + Layout.dotDiameter + Layout.dotSpacing,
            y: rowOriginY
        )
        let isLeadingRed = presentation.dotPhase == .leadingRed
        let isTrailingRed = presentation.dotPhase == .trailingRed

        drawLeadingIndicator(
            presentation.dotPhase,
            color: isLeadingRed ? .systemRed : textColor,
            in: NSRect(
                x: rowOriginX,
                y: indicatorY,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )

        presentation.text.draw(at: textOrigin, withAttributes: attributes)

        drawDot(
            isVisible: presentation.dotPhase == .trailing || isTrailingRed,
            color: isTrailingRed ? .systemRed : primaryColor,
            in: NSRect(
                x: textOrigin.x + textSize.width + Layout.dotSpacing,
                y: indicatorY,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )
    }

    private static func drawDualTextRow(
        primaryText: String,
        primaryAttributes: [NSAttributedString.Key: Any],
        primaryTextSize: NSSize,
        secondaryText: String,
        secondaryAttributes: [NSAttributedString.Key: Any],
        secondaryTextSize: NSSize,
        cellWidth: CGFloat,
        rowOriginX: CGFloat,
        rowHeight: CGFloat,
        progressHeight: CGFloat
    ) {
        let primaryOrigin = NSPoint(
            x: rowOriginX + (cellWidth - primaryTextSize.width) / 2,
            y: progressHeight + (rowHeight - primaryTextSize.height) / 2
        )
        let secondaryCellOriginX = rowOriginX + cellWidth + Layout.progressGap
        let secondaryOrigin = NSPoint(
            x: secondaryCellOriginX + (cellWidth - secondaryTextSize.width) / 2,
            y: progressHeight + (rowHeight - secondaryTextSize.height) / 2
        )

        primaryText.draw(at: primaryOrigin, withAttributes: primaryAttributes)
        secondaryText.draw(at: secondaryOrigin, withAttributes: secondaryAttributes)
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
        case .leading, .leadingRed:
            drawDot(isVisible: true, color: color, in: rect)
        case .leadingSquare:
            drawSquare(color: color, in: rect)
        case .leadingPause:
            drawPauseBars(color: color, in: rect)
        case .hidden, .trailing, .trailingRed:
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
        let progressColor = progress.isWarning ? NSColor.systemRed : primaryColor
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

        let fillRect = outlineRect.insetBy(dx: Layout.progressInset, dy: Layout.progressInset)
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
