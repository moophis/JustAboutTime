import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    enum DeliveryError: Equatable {
        case failedToSchedule
    }

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

    private struct InFlightStatusTask {
        let token = UUID()
        let task: Task<AuthorizationStatus, Never>
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
    @Published private(set) var latestDeliveryError: DeliveryError?

    private let client: Client
    private var hasLoadedAuthorizationStatus = false
    private var refreshTask: InFlightStatusTask?
    private var authorizationTask: InFlightStatusTask?

    init(client: Client = .live) {
        self.client = client
    }

    var preferencesDetailText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Notification access is enabled for countdown alerts."
        case .denied:
            return "Notification access is turned off. Open System Settings to enable alerts later."
        case .notDetermined:
            return "Countdown alerts are not allowed yet. Grant access so completed timers can notify you."
        case .unknown:
            return "Notification access status is unavailable."
        }
    }

    var preferencesActionTitle: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Allow Notifications"
        case .denied:
            return "Open System Settings"
        case .authorized, .provisional, .ephemeral, .unknown:
            return "Refresh"
        }
    }

    var preferencesErrorText: String? {
        switch latestDeliveryError {
        case .failedToSchedule:
            return "The last countdown alert could not be scheduled."
        case nil:
            return nil
        }
    }

    func refresh() async {
        _ = await currentAuthorizationStatus(forceRefresh: true)
    }

    func prepareForCountdownAlertsIfNeeded() async {
        let status = await currentAuthorizationStatus(forceRefresh: !hasLoadedAuthorizationStatus)

        guard status == .notDetermined else {
            return
        }

        await requestAuthorization()
    }

    func requestAuthorization() async {
        _ = await authorizedStatus()
    }

    func notifyCountdownCompleted(duration: TimeInterval) async {
        var status = await currentAuthorizationStatus(forceRefresh: true)

        if status == .notDetermined {
            status = await authorizedStatus()
        }

        guard status.allowsDelivery else {
            return
        }

        let request = Request(
            identifier: UUID().uuidString,
            title: "Countdown Complete",
            body: "Your \(formattedDuration(duration)) countdown finished.",
            sound: true
        )

        do {
            try await client.add(request)
            latestDeliveryError = nil
        } catch {
            latestDeliveryError = .failedToSchedule
        }
    }

    private func currentAuthorizationStatus(forceRefresh: Bool) async -> AuthorizationStatus {
        if !forceRefresh, let refreshTask {
            return await refreshTask.task.value
        }

        let inFlightTask = InFlightStatusTask(task: Task { [client] in
            await client.authorizationStatus()
        })
        refreshTask = inFlightTask

        let status = await inFlightTask.task.value

        if refreshTask?.token == inFlightTask.token {
            refreshTask = nil
        }

        authorizationStatus = status
        hasLoadedAuthorizationStatus = true
        return status
    }

    private func authorizedStatus() async -> AuthorizationStatus {
        if let authorizationTask {
            return await authorizationTask.task.value
        }

        let inFlightTask = InFlightStatusTask(task: Task { [client] in
            _ = try? await client.requestAuthorization([.alert, .sound])
            return await client.authorizationStatus()
        })
        authorizationTask = inFlightTask

        let status = await inFlightTask.task.value

        if authorizationTask?.token == inFlightTask.token {
            authorizationTask = nil
        }

        authorizationStatus = status
        hasLoadedAuthorizationStatus = true
        return status
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
