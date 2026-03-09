import Foundation
import SwiftUI
import AppKit

/// Handles lightweight update checks against GitHub releases.
final class UpdateService: ObservableObject {
    struct UpdateInfo {
        let version: String
        let title: String
        let releaseNotes: String
        let downloadURL: URL?
        let pageURL: URL
    }

    struct UpdateAlert: Identifiable {
        enum Kind {
            case updateAvailable(UpdateInfo)
            case upToDate(String)
            case failure(String)
        }

        let id = UUID()
        let kind: Kind
    }

    struct InstallationStatus {
        enum Phase {
            case preparing
            case downloading
            case extracting
            case installing
            case relaunching
        }

        let phase: Phase
        let message: String
    }

    @Published private(set) var isChecking = false
    @Published var pendingAlert: UpdateAlert?
    @Published private(set) var installationStatus: InstallationStatus?

    private let repoOwner = "kibermaks"
    private let repoName = "SessionFlow"
    private let lastCheckDefaultsKey = "SessionFlow.LastUpdateCheckDate"
    private var periodicTimer: Timer?
    private var hasScheduledChecks = false
    private var installerTask: Task<Void, Never>?

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json"
        ]
        return URLSession(configuration: configuration)
    }()
    
    deinit {
        periodicTimer?.invalidate()
    }
    
    // MARK: - Public API
    
    func startAutomaticChecks() {
        guard !hasScheduledChecks else { return }
        hasScheduledChecks = true
        checkForUpdates(userInitiated: false, ignoreThrottle: true)
        schedulePeriodicChecks()
    }
    
    func userInitiatedCheck() {
        checkForUpdates(userInitiated: true, ignoreThrottle: true)
    }
    
    func installLatestUpdate(_ info: UpdateInfo) {
        guard installerTask == nil else { return }
        dismissAlert()
        installerTask = Task { [weak self] in
            await self?.performInstallation(info: info)
        }
    }
    
    func dismissAlert() {
        pendingAlert = nil
    }
    
    // MARK: - Update Logic
    
    private func checkForUpdatesIfNeeded() {
        guard shouldPerformAutomaticCheck else { return }
        checkForUpdates(userInitiated: false, ignoreThrottle: false)
    }
    
    private var shouldPerformAutomaticCheck: Bool {
        let defaults = UserDefaults.standard
        guard let lastCheck = defaults.object(forKey: lastCheckDefaultsKey) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastCheck) > 60 * 60 * 24
    }
    
    private func checkForUpdates(userInitiated: Bool, ignoreThrottle: Bool) {
        if isChecking { return }
        if !ignoreThrottle && !userInitiated && !shouldPerformAutomaticCheck {
            return
        }
        
        isChecking = true
        Task {
            defer {
                Task { @MainActor in
                    self.isChecking = false
                }
            }
            
            do {
                let request = try buildLatestReleaseRequest()
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw UpdateError.invalidResponse
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw UpdateError.badStatus(httpResponse.statusCode)
                }
                
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                try await handleRelease(release, userInitiated: userInitiated)
            } catch {
                if userInitiated {
                    _ = await MainActor.run {
                        self.pendingAlert = UpdateAlert(kind: .failure(errorMessage(for: error)))
                    }
                }
            }
        }
    }
    
    private func handleRelease(_ release: GitHubRelease, userInitiated: Bool) async throws {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let normalizedTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let comparison = compareVersion(lhs: normalizedTag, rhs: currentVersion)
        
        _ = await MainActor.run {
            UserDefaults.standard.set(Date(), forKey: self.lastCheckDefaultsKey)
        }
        
        switch comparison {
        case .orderedDescending:
            let info = UpdateInfo(
                version: normalizedTag,
                title: release.name.isEmpty ? "SessionFlow \(normalizedTag)" : release.name,
                releaseNotes: release.notesPreview,
                downloadURL: preferredDownloadURL(from: release.assets),
                pageURL: release.htmlURL
            )
            _ = await MainActor.run {
                self.pendingAlert = UpdateAlert(kind: .updateAvailable(info))
            }
        default:
            guard userInitiated else { return }
            _ = await MainActor.run {
                self.pendingAlert = UpdateAlert(kind: .upToDate(currentVersion))
            }
        }
    }
    
    private func buildLatestReleaseRequest() throws -> URLRequest {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            throw UpdateError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }
    
    private func preferredDownloadURL(from assets: [GitHubRelease.Asset]) -> URL? {
        let dmg = assets.first { $0.browserDownloadURL.pathExtension.lowercased() == "dmg" }
        if let dmgURL = dmg?.browserDownloadURL { return dmgURL }
        let zip = assets.first { $0.browserDownloadURL.pathExtension.lowercased() == "zip" }
        if let zipURL = zip?.browserDownloadURL { return zipURL }
        return assets.first?.browserDownloadURL
    }
    
    private func errorMessage(for error: Error) -> String {
        if let updateError = error as? UpdateError {
            return updateError.localizedDescription
        }
        return error.localizedDescription
    }

    @MainActor
    private func setInstallationStatus(_ phase: InstallationStatus.Phase, message: String) {
        installationStatus = InstallationStatus(phase: phase, message: message)
    }
    
    private func clearInstallationStatus() async {
        _ = await MainActor.run {
            installationStatus = nil
            installerTask = nil
        }
    }
    
    private func performInstallation(info: UpdateInfo) async {
        guard let downloadURL = info.downloadURL else {
            _ = await MainActor.run {
                NSWorkspace.shared.open(info.pageURL)
            }
            return
        }
        
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SessionFlowUpdate-\(UUID().uuidString)")
        let downloadTarget = tempDir.appendingPathComponent(downloadURL.lastPathComponent)
        var shouldCleanupTempDir = true
        
        defer {
            if shouldCleanupTempDir {
                try? fileManager.removeItem(at: tempDir)
            }
            Task {
                await clearInstallationStatus()
            }
        }
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            _ = await MainActor.run {
                pendingAlert = nil
                setInstallationStatus(.preparing, message: "Preparing update...")
            }
            _ = await MainActor.run {
                setInstallationStatus(.downloading, message: "Downloading \(info.version)...")
            }
            
            let (downloadedURL, response) = try await urlSession.download(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw UpdateError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            if fileManager.fileExists(atPath: downloadTarget.path) {
                try fileManager.removeItem(at: downloadTarget)
            }
            try fileManager.moveItem(at: downloadedURL, to: downloadTarget)
            
            _ = await MainActor.run {
                setInstallationStatus(.extracting, message: "Extracting update...")
            }
            let extractedApp = try extractApplication(from: downloadTarget, workingDirectory: tempDir)
            
            _ = await MainActor.run {
                setInstallationStatus(.installing, message: "Installing update...")
            }
            try installAndPrepareRelaunch(using: extractedApp, tempDir: tempDir)
            shouldCleanupTempDir = false
            
            _ = await MainActor.run {
                setInstallationStatus(.relaunching, message: "Relaunching SessionFlow...")
                NSApp.terminate(nil)
            }
        } catch {
            shouldCleanupTempDir = true
            _ = await MainActor.run {
                self.pendingAlert = UpdateAlert(kind: .failure("Installation failed: \(error.localizedDescription)"))
            }
        }
    }
    
    private func extractApplication(from archiveURL: URL, workingDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        let ext = archiveURL.pathExtension.lowercased()
        if ext == "dmg" {
            return try extractFromDMG(archiveURL, workingDirectory: workingDirectory)
        } else if ext == "zip" {
            try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, workingDirectory.path])
        } else if ext == "app" {
            let destination = workingDirectory.appendingPathComponent(archiveURL.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: archiveURL, to: destination)
            return destination
        }
        
        if let existingApp = try findAppBundle(in: workingDirectory) {
            return existingApp
        }
        throw InstallationError.missingAppBundle
    }
    
    private func extractFromDMG(_ dmgURL: URL, workingDirectory: URL) throws -> URL {
        let mountPoint = "/Volumes/SessionFlowUpdate-\(UUID().uuidString)"
        try runProcess("/usr/bin/hdiutil", arguments: [
            "attach",
            dmgURL.path,
            "-mountpoint", mountPoint,
            "-nobrowse",
            "-quiet"
        ])
        
        defer {
            _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
        }
        
        let mountURL = URL(fileURLWithPath: mountPoint)
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let appURL = contents.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw InstallationError.missingAppBundle
        }
        
        let destination = workingDirectory.appendingPathComponent(appURL.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: appURL, to: destination)
        return destination
    }
    
    private func installAndPrepareRelaunch(using appURL: URL, tempDir: URL) throws {
        let fileManager = FileManager.default
        let destinationApp = resolvedDestinationAppURL()
        let destinationDir = destinationApp.deletingLastPathComponent()
        
        if !fileManager.fileExists(atPath: destinationDir.path) {
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        let stagedApp = destinationDir.appendingPathComponent(".SessionFlowUpdate-\(UUID().uuidString).app")
        if fileManager.fileExists(atPath: stagedApp.path) {
            try fileManager.removeItem(at: stagedApp)
        }
        try fileManager.copyItem(at: appURL, to: stagedApp)
        
        let scriptURL = tempDir.appendingPathComponent("install.sh")
        let script = """
#!/bin/bash
set -e
TEMP_APP="$1"
DEST_APP="$2"
PROCESS_NAME="$3"
TEMP_DIR="$4"

wait_for_exit() {
  while pgrep -x "$PROCESS_NAME" >/dev/null; do
    sleep 0.5
  done
}

wait_for_exit
rm -rf "$DEST_APP"
mv "$TEMP_APP" "$DEST_APP"
rm -rf "$TEMP_DIR"
open "$DEST_APP"
"""
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try runProcess("/bin/chmod", arguments: ["+x", scriptURL.path])
        
        let process = Process()
        process.launchPath = "/bin/bash"
        process.arguments = [
            scriptURL.path,
            stagedApp.path,
            destinationApp.path,
            ProcessInfo.processInfo.processName,
            tempDir.path
        ]
        try process.run()
    }
    
    private func resolvedDestinationAppURL() -> URL {
        let fileManager = FileManager.default
        let bundleURL = Bundle.main.bundleURL
        let parentDir = bundleURL.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: parentDir.path, isDirectory: &isDir),
           isDir.boolValue,
           fileManager.isWritableFile(atPath: parentDir.path) {
            return bundleURL
        }
        return URL(fileURLWithPath: "/Applications/@My Apps/SessionFlow.app")
    }
    
    private func findAppBundle(in directory: URL) throws -> URL? {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        if let directMatch = contents.first(where: { $0.pathExtension.lowercased() == "app" }) {
            return directMatch
        }
        for entry in contents {
            let resourceValues = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true {
                if let nested = try findAppBundle(in: entry) {
                    return nested
                }
            }
        }
        return nil
    }
    
    @discardableResult
    private func runProcess(_ launchPath: String, arguments: [String]) throws -> String {
        let process = Process()
        process.launchPath = launchPath
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw InstallationError.processFailure(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
    
    private func schedulePeriodicChecks() {
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdatesIfNeeded()
        }
        if let timer = periodicTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    // MARK: - Helpers
    
    private func compareVersion(lhs: String, rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(lhsComponents.count, rhsComponents.count)
        
        for index in 0..<maxCount {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - Models

extension UpdateService {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String
        let body: String?
        let htmlURL: URL
        let assets: [Asset]
        
        var notesPreview: String {
            let trimmed = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = trimmed.split(separator: "\n").map { String($0) }
            return lines.prefix(6).joined(separator: "\n")
        }
        
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL
            
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }
    
    enum UpdateError: LocalizedError {
        case invalidURL
        case invalidResponse
        case badStatus(Int)
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Failed to build update URL."
            case .invalidResponse:
                return "GitHub returned an invalid response."
            case .badStatus(let code):
                return "GitHub update check failed with status code \(code)."
            }
        }
    }
    
    enum InstallationError: LocalizedError {
        case missingAppBundle
        case processFailure(String)
        
        var errorDescription: String? {
            switch self {
            case .missingAppBundle:
                return "Downloaded archive did not contain a SessionFlow app."
            case .processFailure(let output):
                if output.isEmpty {
                    return "A helper command failed while installing the update."
                }
                return output
            }
        }
    }
}
