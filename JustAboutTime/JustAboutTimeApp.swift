import AppKit
import CoreText
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
                .environmentObject(updateManager)
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
        static let progressGap = 16.0
        static let secondarySpacing = 2.0
        // At the track's low y-position, a rounded capsule is narrower than its
        // bounding rectangle. Extra horizontal clearance keeps both track ends
        // inside the visible silhouette instead of crossing the lower corners.
        static let pillHorizontalPadding = 8.0
        static let pillVerticalPadding = 2.0
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
        context.setFillColor(NSColor(srgbRed: 0.65, green: 0.04, blue: 0.08, alpha: opacity).cgColor)
        // Continuous corners match the system status pill rather than semicircular capsule ends.
        context.addPath(RoundedRectangle(cornerRadius: rect.height / 2, style: .continuous).path(in: rect).cgPath)
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
