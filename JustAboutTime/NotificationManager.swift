import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    enum AuthorizationStatus: Equatable {
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
        case unknown

        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined:
                self = .notDetermined
            case .denied:
                self = .denied
            case .authorized:
                self = .authorized
            case .provisional:
                self = .provisional
            case .ephemeral:
                self = .ephemeral
            @unknown default:
                self = .unknown
            }
        }

        var allowsDelivery: Bool {
            switch self {
            case .authorized, .provisional, .ephemeral:
                return true
            case .notDetermined, .denied, .unknown:
                return false
            }
        }
    }

    struct Request: Equatable {
        let identifier: String
        let title: String
        let body: String
        let sound: Bool
    }

    struct Client {
        var authorizationStatus: @Sendable () async -> AuthorizationStatus
        var requestAuthorization: @Sendable (UNAuthorizationOptions) async throws -> Bool
        var add: @Sendable (Request) async throws -> Void

        static let live = Client(
            authorizationStatus: {
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                return AuthorizationStatus(settings.authorizationStatus)
            },
            requestAuthorization: { options in
                try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            },
            add: { request in
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                if request.sound {
                    content.sound = .default
                }

                let notificationRequest = UNNotificationRequest(
                    identifier: request.identifier,
                    content: content,
                    trigger: nil
                )
                try await UNUserNotificationCenter.current().add(notificationRequest)
            }
        )
    }

    @Published private(set) var authorizationStatus: AuthorizationStatus = .notDetermined

    private let client: Client
    private var hasLoadedAuthorizationStatus = false

    init(client: Client = .live) {
        self.client = client
    }

    func refresh() async {
        authorizationStatus = await client.authorizationStatus()
        hasLoadedAuthorizationStatus = true
    }

    func prepareForCountdownAlertsIfNeeded() async {
        if !hasLoadedAuthorizationStatus {
            await refresh()
        }

        guard authorizationStatus == .notDetermined else {
            return
        }

        await requestAuthorization()
    }

    func requestAuthorization() async {
        _ = try? await client.requestAuthorization([.alert, .sound])
        await refresh()
    }

    func notifyCountdownCompleted(duration: TimeInterval) async {
        if !hasLoadedAuthorizationStatus {
            await refresh()
        }

        guard authorizationStatus.allowsDelivery else {
            return
        }

        let request = Request(
            identifier: UUID().uuidString,
            title: "Countdown Complete",
            body: "Your \(formattedDuration(duration)) countdown finished.",
            sound: true
        )

        try? await client.add(request)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int(duration.rounded(.down)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }

        return "\(totalMinutes)m"
    }
}
