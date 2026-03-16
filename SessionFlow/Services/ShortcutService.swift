import Foundation

/// Fires macOS Shortcuts at session lifecycle moments with structured JSON input.
class ShortcutService {

    enum Trigger: String {
        case approaching
        case started
        case ended
    }

    struct SessionInfo {
        let title: String
        let type: SessionType?
        let isBusySlot: Bool
        let startTime: Date
        let endTime: Date
    }

    private var approachingTimer: Timer?
    private var lastScheduledSessionId: String?

    // MARK: - Public API

    /// Fire a shortcut for the given trigger, checking config filters.
    func fire(trigger: Trigger, session: SessionInfo, config: ShortcutsConfig) {
        let triggerConfig: ShortcutTriggerConfig
        switch trigger {
        case .approaching: triggerConfig = config.approaching
        case .started: triggerConfig = config.started
        case .ended: triggerConfig = config.ended
        }

        guard triggerConfig.isEnabled else { return }
        guard triggerConfig.typeFilter.matches(sessionType: session.type, isBusySlot: session.isBusySlot) else { return }
        guard !triggerConfig.shortcutName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let payload = buildPayload(trigger: trigger, session: session)
        runShortcut(name: triggerConfig.shortcutName, payload: payload)
    }

    /// Schedule the "approaching" shortcut to fire before a session starts.
    func scheduleApproaching(sessionId: String, session: SessionInfo, config: ShortcutsConfig) {
        let triggerConfig = config.approaching
        guard triggerConfig.isEnabled else {
            cancelApproaching()
            return
        }
        guard triggerConfig.typeFilter.matches(sessionType: session.type, isBusySlot: session.isBusySlot) else {
            cancelApproaching()
            return
        }

        // Don't reschedule if already set for the same session
        if lastScheduledSessionId == sessionId { return }

        cancelApproaching()
        lastScheduledSessionId = sessionId

        let leadTime = TimeInterval((triggerConfig.leadTimeMinutes ?? 1) * 60)
        let fireDate = session.startTime.addingTimeInterval(-leadTime)
        let delay = fireDate.timeIntervalSinceNow

        guard delay > 0 else { return } // Already past the lead time

        approachingTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.fire(trigger: .approaching, session: session, config: config)
            self?.lastScheduledSessionId = nil
        }
    }

    /// Cancel any pending approaching timer.
    func cancelApproaching() {
        approachingTimer?.invalidate()
        approachingTimer = nil
        lastScheduledSessionId = nil
    }

    // MARK: - Payload

    private func buildPayload(trigger: Trigger, session: SessionInfo) -> String {
        let iso = ISO8601DateFormatter()
        let typeName = session.type?.rawValue ?? "External"
        let typeKey = session.type?.rawValue.lowercased() ?? "external"
        let duration = Int(session.endTime.timeIntervalSince(session.startTime) / 60)

        let message: String
        switch trigger {
        case .approaching:
            let lead = Int(session.startTime.timeIntervalSinceNow / 60) + 1
            message = "\(typeName) session '\(session.title)' starts in \(lead) min"
        case .started:
            message = "\(typeName) session '\(session.title)' started"
        case .ended:
            message = "\(typeName) session '\(session.title)' ended"
        }

        let payload: [String: Any] = [
            "trigger": trigger.rawValue,
            "type": typeKey,
            "typeName": typeName,
            "title": session.title,
            "message": message,
            "duration": duration,
            "startTime": iso.string(from: session.startTime),
            "endTime": iso.string(from: session.endTime)
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: - Test

    /// Run a shortcut with a test payload and report success/failure.
    static func test(name: String, payload: String, completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let inputPath = Self.writePayloadToTempFile(payload) else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "ShortcutService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to write payload"]))) }
                return
            }
            defer { try? FileManager.default.removeItem(at: inputPath) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name, "--input-path", inputPath.path]
            let errPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    DispatchQueue.main.async { completion(.success(())) }
                } else {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Exit code \(process.terminationStatus)"
                    DispatchQueue.main.async { completion(.failure(NSError(domain: "ShortcutService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg]))) }
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Execution

    private func runShortcut(name: String, payload: String) {
        DispatchQueue.global(qos: .utility).async {
            guard let inputPath = Self.writePayloadToTempFile(payload) else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", name, "--input-path", inputPath.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: inputPath)
        }
    }

    private static func writePayloadToTempFile(_ payload: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let file = tempDir.appendingPathComponent("sessionflow-shortcut-\(UUID().uuidString).txt")
        guard (try? payload.write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        return file
    }
}
