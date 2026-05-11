import AppKit
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    enum Status: Equatable {
        case unknown
        case checking
        case upToDate
        case updateAvailable(version: String, downloadURL: URL)
        case downloading(progress: Double)
        case downloadFailed(String)
        case checkFailed(String)
    }

    @Published var status: Status = .unknown

    private let owner = "moophis"
    private let repo = "JustAboutTime"
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    private static let githubAPIBase = "https://api.github.com"

    var isBusy: Bool {
        if case .checking = status { return true }
        if case .downloading = status { return true }
        return false
    }

    private var currentVersion: String {
        Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.1"
    }

    // MARK: - Public API

    func checkForUpdatesIfNeeded() {
        guard !isBusy else { return }
        Task {
            await performCheck(silent: true)
        }
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        Task {
            await performCheck(silent: false)
        }
    }

    func downloadAndInstall(url: URL) {
        guard !isBusy else { return }
        Task {
            await performDownloadAndInstall(from: url)
        }
    }

    // MARK: - Version Check

    private func performCheck(silent: Bool) async {
        status = .checking

        let url = URL(string: "\(Self.githubAPIBase)/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            guard httpResponse?.statusCode == 200 else {
                let code = httpResponse?.statusCode ?? 0
                if code == 403 {
                    status = .checkFailed("GitHub rate limit exceeded. Try again later.")
                } else {
                    status = .checkFailed("Unable to check for updates (HTTP \(code)).")
                }
                if !silent {
                    showAlert(message: statusMessage)
                }
                return
            }
            data = responseData
        } catch {
            let message = error.localizedDescription.contains("offline") || error.localizedDescription.contains("connection")
                ? "Unable to check for updates. Check your internet connection."
                : "Unable to check for updates: \(error.localizedDescription)"
            status = .checkFailed(message)
            if !silent {
                showAlert(message: message)
            }
            return
        }

        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            status = .checkFailed("Unable to parse release information.")
            if !silent {
                showAlert(message: statusMessage)
            }
            return
        }

        let latestVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        guard isVersion(latestVersion, newerThan: currentVersion) else {
            status = .upToDate
            return
        }

        guard let dmgAsset = release.assets.first(where: { asset in
            asset.contentType.contains("diskimage") ||
            asset.name.hasSuffix(".dmg") ||
            asset.browserDownloadURL.pathExtension == "dmg"
        }) else {
            status = .checkFailed("No download available for this release.")
            if !silent {
                showAlert(message: statusMessage)
            }
            return
        }

        status = .updateAvailable(version: latestVersion, downloadURL: dmgAsset.browserDownloadURL)

        if !silent {
            let alert = NSAlert()
            alert.messageText = "New Version Available"
            alert.informativeText = "JustAboutTime \(latestVersion) is available. You have \(currentVersion). Would you like to download and install it?"
            alert.addButton(withTitle: "Install & Restart")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                downloadAndInstall(url: dmgAsset.browserDownloadURL)
            }
        }
    }

    // MARK: - Download & Install

    private func performDownloadAndInstall(from url: URL) async {
        status = .downloading(progress: 0)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustAboutTime-Update-\(UUID().uuidString)")
        let dmgPath = tempDir.appendingPathComponent("update.dmg")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            status = .downloadFailed("Failed to create temporary directory.")
            return
        }
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dmgURL: URL
        do {
            dmgURL = try await downloadFile(from: url, to: dmgPath) { [weak self] progress in
                Task { @MainActor in
                    self?.status = .downloading(progress: progress)
                }
            }
        } catch {
            status = .downloadFailed("Download failed. Please try again.")
            return
        }

        guard let mountPoint = await mountDMG(at: dmgURL) else {
            status = .downloadFailed("Failed to mount disk image.")
            return
        }

        let appName = (Bundle.main.bundleURL.lastPathComponent as NSString).deletingPathExtension
        let mountedAppPath = "\(mountPoint)/\(appName).app"
        let targetAppPath = Bundle.main.bundlePath

        guard FileManager.default.fileExists(atPath: mountedAppPath) else {
            await ejectDMG(at: mountPoint)
            status = .downloadFailed("App not found in disk image.")
            return
        }

        let scriptPath = tempDir.appendingPathComponent("install.sh")

        let script = """
        #!/bin/bash
        set -euo pipefail
        sleep 2
        rsync -a --delete "\(mountedAppPath)/" "\(targetAppPath)/"
        hdiutil detach "\(mountPoint)" -force 2>/dev/null
        rm -rf "\(tempDir.path)"
        open "\(targetAppPath)"
        """

        do {
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            await ejectDMG(at: mountPoint)
            status = .downloadFailed("Failed to prepare installer.")
            return
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptPath.path
            )
        } catch {
            await ejectDMG(at: mountPoint)
            status = .downloadFailed("Failed to prepare installer.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            await ejectDMG(at: mountPoint)
            status = .downloadFailed("Failed to start installer.")
            return
        }

        // Brief delay so the process can start, then quit this app
        try? await Task.sleep(nanoseconds: 500_000_000)
        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func downloadFile(
        from url: URL,
        to destination: URL,
        progressHandler: @MainActor @escaping (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await session.bytes(from: url)
        let expectedLength = Double(response.expectedContentLength)
        let fileHandle = try FileHandle(forWritingTo: destination)
        defer { try? fileHandle.close() }
        var receivedBytes = 0
        var buffer = [UInt8]()
        buffer.reserveCapacity(65536)

        for try await byte in bytes {
            buffer.append(byte)
            receivedBytes += 1
            if buffer.count >= 65536 {
                try fileHandle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            if expectedLength > 0 {
                await progressHandler(Double(receivedBytes) / expectedLength)
            }
        }
        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
        }
        return destination
    }

    private func mountDMG(at url: URL) async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["attach", url.path, "-nobrowse", "-plist"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return nil
            }

            guard process.terminationStatus == 0,
                  let data = try? pipe.fileHandleForReading.readToEnd(),
                  let plist = try? PropertyListSerialization.propertyList(
                      from: data, options: [], format: nil
                  ) as? [String: Any],
                  let entities = plist["system-entities"] as? [[String: Any]]
            else {
                return nil
            }

            for entity in entities {
                if let mountPoint = entity["mount-point"] as? String {
                    return mountPoint
                }
            }
            return nil
        }.value
    }

    private func ejectDMG(at mountPoint: String) async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["detach", mountPoint, "-force"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }.value
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    var statusMessage: String {
        switch status {
        case .unknown, .checking, .upToDate, .updateAvailable, .downloading:
            return ""
        case .checkFailed(let message), .downloadFailed(let message):
            return message
        }
    }

    // MARK: - Version Comparison

    func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let latestParts = sanitizedVersionComponents(latest)
        let currentParts = sanitizedVersionComponents(current)

        let maxCount = max(latestParts.count, currentParts.count)
        for i in 0 ..< maxCount {
            let latestComponent = i < latestParts.count ? latestParts[i] : 0
            let currentComponent = i < currentParts.count ? currentParts[i] : 0
            if latestComponent > currentComponent { return true }
            if latestComponent < currentComponent { return false }
        }
        return false
    }

    private func sanitizedVersionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .components(separatedBy: ".")
            .compactMap { component in
                let digits = component.prefix(while: { $0.isNumber })
                return Int(digits)
            }
    }
}

// MARK: - GitHub API Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let contentType: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case browserDownloadURL = "browser_download_url"
    }
}
