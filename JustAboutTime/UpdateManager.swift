import Foundation
@preconcurrency import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    enum Status: Equatable {
        case unknown
        case checking
        case upToDate
        case updateAvailable(version: String)
        case downloading
        case readyToInstall
        case failed(String)
    }

    @Published private(set) var status: Status = .unknown
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyChecksForUpdates, forKey: Self.autoCheckKey)
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    @Published var automaticallyDownloadsUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyDownloadsUpdates, forKey: Self.autoDownloadKey)
            updaterController.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    private static let autoCheckKey = "UpdateManager.automaticallyChecksForUpdates"
    private static let autoDownloadKey = "UpdateManager.automaticallyDownloadsUpdates"

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

override init() {
    automaticallyChecksForUpdates = UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
        automaticallyDownloadsUpdates = UserDefaults.standard.object(forKey: Self.autoDownloadKey) as? Bool ?? true
        super.init()

        updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        updaterController.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        updaterController.startUpdater()
    }

    var isBusy: Bool {
        status == .checking || status == .downloading
    }

    func checkForUpdatesIfNeeded() {
        guard !isBusy, automaticallyChecksForUpdates else { return }
        status = .checking
        updaterController.updater.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        status = .checking
        updaterController.checkForUpdates(nil)
    }

    func resetStatus() {
        status = .unknown
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            status = .updateAvailable(version: version)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            status = .upToDate
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            status = .failed(message)
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        Task { @MainActor in
            status = .downloading
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Task { @MainActor in
            status = .readyToInstall
        }
    }
}
