import Foundation

/// Fires macOS Shortcuts at session lifecycle moments with structured JSON input.
class ShortcutService {

    enum Trigger: String {
        case approaching
        case started
        case endingSoon = "ending_soon"
        case ended
        case restStarted = "rest_started"
        case restEnded = "rest_ended"
        case restEndingSoon = "rest_ending_soon"
    }

    struct SessionInfo {
        let title: String
        let type: SessionType?
        let isBusySlot: Bool
        let startTime: Date
        let endTime: Date
        // Rest context (optional, populated for rest triggers)
        var restDuration: Int? = nil        // minutes
        var nextTitle: String? = nil
        var nextStartTime: Date? = nil
    }

    private var approachingTimer: Timer?
    private var lastScheduledSessionId: String?

    // MARK: - Public API

    /// Fire a shortcut for the given trigger, checking config filters.
    func fire(trigger: Trigger, session: SessionInfo, config: ShortcutsConfig) {
        let triggerConfig = configFor(trigger: trigger, config: config)

        guard triggerConfig.isEnabled else { return }
        guard triggerConfig.typeFilter.matches(sessionType: session.type, isBusySlot: session.isBusySlot) else { return }
        guard !triggerConfig.shortcutName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let payload = buildPayload(trigger: trigger, session: session)
        runShortcut(name: triggerConfig.shortcutName, payload: payload)
    }

    /// Fire a shortcut synchronously (launch process without waiting).
    /// Used for app termination flush — the child process continues after the app exits.
    func fireAndForget(trigger: Trigger, session: SessionInfo, config: ShortcutsConfig) {
        let triggerConfig = configFor(trigger: trigger, config: config)

        guard triggerConfig.isEnabled else { return }
        guard triggerConfig.typeFilter.matches(sessionType: session.type, isBusySlot: session.isBusySlot) else { return }
        guard !triggerConfig.shortcutName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let payload = buildPayload(trigger: trigger, session: session)
        guard let inputPath = Self.writePayloadToTempFile(payload) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", triggerConfig.shortcutName, "--input-path", inputPath.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        // Don't wait — process continues after app terminates
        // Don't clean up temp file — OS handles it
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

    // MARK: - Config lookup

    private func configFor(trigger: Trigger, config: ShortcutsConfig) -> ShortcutTriggerConfig {
        switch trigger {
        case .approaching: return config.approaching
        case .started: return config.started
        case .endingSoon: return config.endingSoon
        case .ended: return config.ended
        case .restStarted: return config.restStarted
        case .restEndingSoon: return config.restEndingSoon
        case .restEnded: return config.restEnded
        }
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
        case .endingSoon:
            let lead = max(1, Int(session.endTime.timeIntervalSinceNow / 60) + 1)
            message = "\(typeName) session '\(session.title)' ends in \(lead) min"
        case .ended:
            message = "\(typeName) session '\(session.title)' ended"
        case .restStarted:
            if let restMin = session.restDuration, let nextTitle = session.nextTitle {
                message = "Rest started — \(restMin) min until '\(nextTitle)'"
            } else if let restMin = session.restDuration {
                message = "Rest started — \(restMin) min break"
            } else {
                message = "Rest started after \(typeName) session '\(session.title)'"
            }
        case .restEndingSoon:
            if let nextTitle = session.nextTitle, let nextStart = session.nextStartTime {
                let lead = max(1, Int(nextStart.timeIntervalSinceNow / 60) + 1)
                message = "Rest ending soon — '\(nextTitle)' starts in \(lead) min"
            } else {
                message = "Rest ending soon"
            }
        case .restEnded:
            if let nextTitle = session.nextTitle {
                message = "Rest ended — '\(nextTitle)' is starting"
            } else {
                message = "Rest ended"
            }
        }

        var payload: [String: Any] = [
            "trigger": trigger.rawValue,
            "type": typeKey,
            "typeName": typeName,
            "title": session.title,
            "message": message,
            "duration": duration,
            "startTime": iso.string(from: session.startTime),
            "endTime": iso.string(from: session.endTime)
        ]

        // Add rest-specific fields
        if let restDuration = session.restDuration {
            payload["restDuration"] = restDuration
        }
        if let nextTitle = session.nextTitle {
            payload["nextTitle"] = nextTitle
        }
        if let nextStart = session.nextStartTime {
            payload["nextStartTime"] = iso.string(from: nextStart)
        }

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
