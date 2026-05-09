import AppKit
import SwiftUI

@main
struct JustAboutTimeApp: App {
    @StateObject private var historyStore: HistoryStore
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var preferencesStore = PreferencesStore()
    @StateObject private var timerStore: TimerStore
    @StateObject private var shortcutManager: ShortcutManager

    init() {
        let historyStore = HistoryStore()
        let notificationManager = NotificationManager()
        let preferencesStore = PreferencesStore()
        let timerStore = TimerStore(historyStore: historyStore, notificationManager: notificationManager, preferencesStore: preferencesStore)
        _historyStore = StateObject(wrappedValue: historyStore)
        _notificationManager = StateObject(wrappedValue: notificationManager)
        _preferencesStore = StateObject(wrappedValue: preferencesStore)
        _timerStore = StateObject(wrappedValue: timerStore)
        _shortcutManager = StateObject(wrappedValue: ShortcutManager(timerStore: timerStore))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(timerStore: timerStore, preferencesStore: preferencesStore)
        } label: {
            StatusBarLabelView(
                presentation: timerStore.statusPresentation,
                countdownProgress: timerStore.countdownProgress
            )
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: HistoryWindow.id) {
            HistoryView(historyStore: historyStore, timerStore: timerStore)
        }

        Window("About JustAboutTime", id: AboutWindow.id) {
            AboutView()
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
    let presentation: TimerStatusPresentation
    let countdownProgress: CountdownProgressPresentation?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: StatusBarLabelImageRenderer.image(
            presentation: presentation,
            countdownProgress: countdownProgress,
            colorScheme: colorScheme
        ))
            .accessibilityLabel(presentation.text)
    }
}

private enum StatusBarLabelImageRenderer {
    private enum Layout {
        static let dotDiameter = 6.0
        static let dotSpacing = 4.0
        static let progressHeight = 5.0
        static let progressSpacing = 1.0
        static let progressInset = 1.0
    }

    static func image(
        presentation: TimerStatusPresentation,
        countdownProgress: CountdownProgressPresentation?,
        colorScheme: ColorScheme
    ) -> NSImage {
        let needsOriginalColor = usesSemanticRed(presentation: presentation, countdownProgress: countdownProgress)
        let primaryColor = needsOriginalColor ? menuBarPrimaryColor(for: colorScheme) : .labelColor
        let attributes = textAttributes(foregroundColor: primaryColor)
        let textSize = presentation.text.size(withAttributes: attributes)
        let textRowSize = rowSize(textSize: textSize)
        let progressHeight = countdownProgress == nil ? 0 : Layout.progressSpacing + Layout.progressHeight
        let progressWidth = max(34, textRowSize.width)
        let imageSize = NSSize(width: max(textRowSize.width, progressWidth), height: textRowSize.height + progressHeight)
        let image = NSImage(size: imageSize)
        image.isTemplate = !needsOriginalColor

        image.lockFocus()
        defer { image.unlockFocus() }

        let rowOriginX = (imageSize.width - textRowSize.width) / 2
        let textOrigin = NSPoint(x: rowOriginX + Layout.dotDiameter + Layout.dotSpacing, y: progressHeight)
        let isLeadingRed = presentation.dotPhase == .leadingRed
        let isTrailingRed = presentation.dotPhase == .trailingRed

        drawDot(
            isVisible: presentation.dotPhase == .leading || isLeadingRed,
            color: isLeadingRed ? .systemRed : primaryColor,
            in: NSRect(
                x: rowOriginX,
                y: progressHeight + (textRowSize.height - Layout.dotDiameter) / 2,
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
                y: progressHeight + (textRowSize.height - Layout.dotDiameter) / 2,
                width: Layout.dotDiameter,
                height: Layout.dotDiameter
            )
        )

        if let countdownProgress {
            drawProgress(
                countdownProgress,
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

    private static func usesSemanticRed(
        presentation: TimerStatusPresentation,
        countdownProgress: CountdownProgressPresentation?
    ) -> Bool {
        presentation.dotPhase == .leadingRed ||
            presentation.dotPhase == .trailingRed ||
            countdownProgress?.isWarning == true
    }

    private static func menuBarPrimaryColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? .white : .black
    }

    private static func textAttributes(foregroundColor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: foregroundColor
        ]
    }

    private static func drawDot(isVisible: Bool, color: NSColor = .labelColor, in rect: NSRect) {
        guard isVisible else {
            return
        }

        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
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
        progressColor.withAlphaComponent(0.75).setFill()
        fillPath.fill()
    }
}
