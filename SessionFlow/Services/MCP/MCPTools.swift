import Foundation
import MCP

/// Maps MCP tool calls onto SessionFlow's services. All members are `@MainActor` because they
/// read and mutate `@Published` state on `SchedulingEngine` / `CalendarService`.
@MainActor
final class MCPToolHandler {
    private let engine: SchedulingEngine
    private let calendar: any CalendarWriting
    private let coordinator: ScheduleCoordinator

    init(engine: SchedulingEngine, calendar: any CalendarWriting, coordinator: ScheduleCoordinator) {
        self.engine = engine
        self.calendar = calendar
        self.coordinator = coordinator
    }

    // MARK: Tool catalog

    func toolDefinitions() -> [Tool] {
        [
            Tool(
                name: "learn",
                description: "Return the SessionFlow agent guide: concepts, session types, the schedule workflow, and every tool with arguments and examples. Call this first to learn what you can do.",
                inputSchema: Self.emptyObjectSchema
            ),
            Tool(
                name: "get_config",
                description: "Return SessionFlow's current scheduling configuration: session counts, names, durations, rest lengths, pattern, day hours, task lists, deep-session and long-rest settings, and calendar mapping.",
                inputSchema: Self.emptyObjectSchema
            ),
            Tool(
                name: "get_state",
                description: "Return the current in-app schedule preview (projected sessions with id, type, title, start/end), quota counts, whether quotas are satisfied, the status message, the frozen flag, and the active preset.",
                inputSchema: Self.emptyObjectSchema
            ),
            Tool(
                name: "list_presets",
                description: "List all saved scheduling presets with their id, name, icon, a short summary, and whether each is the active preset or differs from the current configuration.",
                inputSchema: Self.emptyObjectSchema
            ),
            Tool(
                name: "get_day",
                description: "Inspect a calendar day: real events (with start/end, calendar, and SessionFlow type if tagged), existing SessionFlow session counts, and availability (free minutes plus how many work/side/deep sessions could still fit).",
                inputSchema: Self.dateArgSchema(required: false)
            ),
            Tool(
                name: "set_tasks",
                description: "Set the task lists that name the scheduled sessions. Each list is one task per array element. The natural-language entry point: parse what the user wants done into work/side/deep tasks. Also toggles whether task names are used.",
                inputSchema: Self.setTasksSchema
            ),
            Tool(
                name: "set_config",
                description: "Patch any subset of the scheduling configuration (session counts, names, durations, rests, pattern, cycle sizes, day hours, flags, and nested deepSession/bigRest objects). Only provided fields change. To reduce the schedule, lower workSessions/sideSessions or the durations.",
                inputSchema: Self.setConfigSchema
            ),
            Tool(
                name: "apply_preset",
                description: "Switch to a saved preset by id or name. Replaces the current configuration with the preset's values.",
                inputSchema: Self.objectSchema([
                    ("presetId", "string", "Preset UUID (preferred). Optional if name is given."),
                    ("name", "string", "Preset name (used if presetId is omitted)."),
                ])
            ),
            Tool(
                name: "save_preset",
                description: "Save the current configuration as a new preset and make it active.",
                inputSchema: Self.objectSchema([
                    ("name", "string", "Display name for the new preset."),
                    ("icon", "string", "Optional SF Symbol name. Defaults to star.fill."),
                ], required: ["name"])
            ),
            Tool(
                name: "regenerate_schedule",
                description: "Rebuild the in-app schedule preview for a day from the current configuration and tasks. Does NOT write to the calendar. Returns the new projected sessions.",
                inputSchema: Self.objectSchema([
                    ("date", "string", "Day to schedule (YYYY-MM-DD or ISO-8601). Defaults to today."),
                    ("startHour", "integer", "Hour of day (0–23) to start scheduling. Defaults to now if today, else the configured default start hour."),
                ])
            ),
            Tool(
                name: "commit_schedule",
                description: "Write the current preview to the real calendar as events (excluding long rests), then clear the preview. This creates real calendar events.",
                inputSchema: Self.dateArgSchema(required: false)
            ),
            Tool(
                name: "move_session",
                description: "Move or resize a session to a new start/end interval. Targets a committed calendar event by eventId, or a preview session by sessionId. Provide both newStart and newEnd (ISO-8601).",
                inputSchema: Self.moveSchema
            ),
            Tool(
                name: "resize_session",
                description: "Alias of move_session: set a session's start/end interval. Targets a committed event by eventId or a preview session by sessionId.",
                inputSchema: Self.moveSchema
            ),
            Tool(
                name: "delete_sessions",
                description: "Delete SessionFlow-tagged events on the session calendars for a day. Never touches untagged events. scope=future deletes from now onward (today) or the whole day (other days); scope=all deletes the entire day.",
                inputSchema: Self.objectSchema([
                    ("date", "string", "Day to clear (YYYY-MM-DD or ISO-8601). Defaults to today."),
                    ("scope", "string", "\"future\" (default) or \"all\"."),
                ])
            ),
            Tool(
                name: "set_freeze",
                description: "Freeze or unfreeze the preview. When frozen, regenerate_schedule returns the cached sessions unchanged (used to preserve manual edits).",
                inputSchema: Self.objectSchema([
                    ("frozen", "boolean", "true to freeze, false to unfreeze."),
                ], required: ["frozen"])
            ),
        ]
    }

    // MARK: Dispatch

    func call(name: String, arguments: [String: Value]?) async -> (text: String, isError: Bool) {
        switch name {
        case "learn":
            return (MCPGuide.markdown(), false)
        case "get_config":
            return (jsonString(configDictionary()), false)
        case "get_state":
            return (jsonString(stateDictionary()), false)
        case "list_presets":
            return (jsonString(presetsList()), false)
        case "get_day":
            let date = Self.parseDate(arguments?["date"]?.stringValue) ?? Calendar.current.startOfDay(for: Date())
            return (jsonString(await dayDictionary(for: date)), false)
        case "set_tasks":
            return setTasks(arguments)
        case "set_config":
            return setConfig(arguments)
        case "apply_preset":
            return applyPreset(arguments)
        case "save_preset":
            return savePreset(arguments)
        case "regenerate_schedule":
            return await regenerate(arguments)
        case "commit_schedule":
            let date = Self.parseDate(arguments?["date"]?.stringValue) ?? Calendar.current.startOfDay(for: Date())
            let result = await coordinator.commit(date: date)
            return (jsonString([
                "success": result.success, "failed": result.failed, "eventIds": result.eventIds,
            ]), false)
        case "move_session", "resize_session":
            return setSessionInterval(arguments)
        case "delete_sessions":
            let date = Self.parseDate(arguments?["date"]?.stringValue) ?? Calendar.current.startOfDay(for: Date())
            let scope = DeleteScope(rawValue: arguments?["scope"]?.stringValue ?? "future") ?? .future
            let result = await coordinator.deleteSessions(date: date, scope: scope)
            return (jsonString(["deleted": result.deleted, "failed": result.failed, "scope": scope.rawValue]), false)
        case "set_freeze":
            guard let frozen = arguments?["frozen"]?.boolValue else {
                return ("set_freeze requires a boolean \"frozen\" argument", true)
            }
            engine.sessionsFrozen = frozen
            return (jsonString(["sessionsFrozen": engine.sessionsFrozen]), false)
        default:
            return ("Unknown tool: \(name)", true)
        }
    }

    // MARK: - Control tools

    private func setTasks(_ args: [String: Value]?) -> (text: String, isError: Bool) {
        if let work = Self.stringArray(args?["work"]) { engine.workTasks = work.joined(separator: "\n") }
        if let side = Self.stringArray(args?["side"]) { engine.sideTasks = side.joined(separator: "\n") }
        if let deep = Self.stringArray(args?["deep"]) { engine.deepTasks = deep.joined(separator: "\n") }
        if let useWork = args?["useWork"]?.boolValue { engine.useWorkTasks = useWork }
        if let useSide = args?["useSide"]?.boolValue { engine.useSideTasks = useSide }
        if let useDeep = args?["useDeep"]?.boolValue { engine.useDeepTasks = useDeep }
        return (jsonString([
            "tasks": [
                "work": Self.lines(engine.workTasks),
                "side": Self.lines(engine.sideTasks),
                "deep": Self.lines(engine.deepTasks),
                "useWork": engine.useWorkTasks,
                "useSide": engine.useSideTasks,
                "useDeep": engine.useDeepTasks,
            ],
        ]), false)
    }

    private func setConfig(_ args: [String: Value]?) -> (text: String, isError: Bool) {
        guard let args else { return (jsonString(configDictionary()), false) }

        if let v = args["workSessions"]?.intValue { engine.workSessions = max(0, v) }
        if let v = args["sideSessions"]?.intValue { engine.sideSessions = max(0, v) }
        if let v = args["workSessionName"]?.stringValue { engine.workSessionName = v }
        if let v = args["sideSessionName"]?.stringValue { engine.sideSessionName = v }
        if let v = args["workSessionDuration"]?.intValue { engine.workSessionDuration = max(1, v) }
        if let v = args["sideSessionDuration"]?.intValue { engine.sideSessionDuration = max(1, v) }
        if let v = args["planningDuration"]?.intValue { engine.planningDuration = max(1, v) }
        if let v = args["restDuration"]?.intValue { engine.restDuration = max(0, v) }
        if let v = args["sideRestDuration"]?.intValue { engine.sideRestDuration = max(0, v) }
        if let v = args["deepRestDuration"]?.intValue { engine.deepRestDuration = max(0, v) }
        if let v = args["workSessionsPerCycle"]?.intValue { engine.workSessionsPerCycle = max(1, v) }
        if let v = args["sideSessionsPerCycle"]?.intValue { engine.sideSessionsPerCycle = max(1, v) }
        if let v = args["sideFirst"]?.boolValue { engine.sideFirst = v }
        if let v = args["schedulePlanning"]?.boolValue { engine.schedulePlanning = v }
        if let v = args["flexibleSideScheduling"]?.boolValue { engine.flexibleSideScheduling = v }
        if let v = args["dayStartHour"]?.intValue { engine.dayStartHour = Self.clamp(v, to: 0...12) }
        if let v = args["dayEndHour"]?.intValue { engine.dayEndHour = Self.clamp(v, to: 13...24) }
        if let v = args["scheduleEndHour"]?.intValue {
            engine.scheduleEndHour = Self.clamp(v, to: 13...30)
            calendar.scheduleEndHour = engine.scheduleEndHour
        }
        if let v = args["defaultStartHour"]?.intValue { engine.defaultStartHour = Self.clamp(v, to: 0...23) }
        if let raw = args["pattern"]?.stringValue {
            guard let pattern = SchedulePattern(rawValue: raw) else {
                let valid = SchedulePattern.allCases.map(\.rawValue).joined(separator: ", ")
                return ("Invalid pattern \"\(raw)\". Valid values: \(valid)", true)
            }
            engine.pattern = pattern
        }
        if let deep = args["deepSession"]?.objectValue { applyDeepConfig(deep) }
        if let big = args["bigRest"]?.objectValue { applyBigRestConfig(big) }

        return (jsonString(configDictionary()), false)
    }

    private func applyDeepConfig(_ obj: [String: Value]) {
        var config = engine.deepSessionConfig
        if let v = obj["enabled"]?.boolValue { config.enabled = v }
        if let v = obj["sessionCount"]?.intValue { config.sessionCount = max(0, v) }
        if let v = obj["injectAfterEvery"]?.intValue { config.injectAfterEvery = max(1, v) }
        if let v = obj["andThenGap"]?.intValue { config.andThenGap = max(0, v) }
        if let v = obj["name"]?.stringValue { config.name = v }
        if let v = obj["duration"]?.intValue { config.duration = max(1, v) }
        if let v = obj["calendarName"]?.stringValue { config.calendarName = v }
        engine.deepSessionConfig = config
    }

    private func applyBigRestConfig(_ obj: [String: Value]) {
        var config = engine.bigRestConfig
        if let v = obj["enabled"]?.boolValue { config.enabled = v }
        if let v = obj["count"]?.intValue { config.count = max(0, v) }
        if let v = obj["duration"]?.intValue { config.duration = max(1, v) }
        if let v = obj["afterMinutes"]?.intValue { config.afterMinutes = max(0, v) }
        engine.bigRestConfig = config
    }

    private func applyPreset(_ args: [String: Value]?) -> (text: String, isError: Bool) {
        let presets = PresetStorage.shared.loadPresets()
        let preset: Preset?
        if let idString = args?["presetId"]?.stringValue, let id = UUID(uuidString: idString) {
            preset = presets.first { $0.id == id }
        } else if let name = args?["name"]?.stringValue {
            preset = presets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        } else {
            return ("apply_preset requires presetId or name", true)
        }
        guard let preset else { return ("No matching preset found", true) }
        engine.applyPreset(preset)
        return (jsonString(["appliedPreset": preset.name, "presetId": preset.id.uuidString]), false)
    }

    private func savePreset(_ args: [String: Value]?) -> (text: String, isError: Bool) {
        guard let name = args?["name"]?.stringValue, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ("save_preset requires a non-empty name", true)
        }
        let icon = args?["icon"]?.stringValue ?? "star.fill"
        let preset = engine.saveAsPreset(name: name, icon: icon)
        var presets = PresetStorage.shared.loadPresets()
        presets.append(preset)
        PresetStorage.shared.savePresets(presets)
        engine.currentPresetId = preset.id
        return (jsonString(["savedPreset": preset.name, "presetId": preset.id.uuidString]), false)
    }

    private func regenerate(_ args: [String: Value]?) async -> (text: String, isError: Bool) {
        let date = Self.parseDate(args?["date"]?.stringValue) ?? Calendar.current.startOfDay(for: Date())
        var startTime: Date?
        if let hour = args?["startHour"]?.intValue, (0...23).contains(hour) {
            startTime = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date)
        }
        await coordinator.regeneratePreview(date: date, startTime: startTime)
        return (jsonString(stateDictionary()), false)
    }

    private func setSessionInterval(_ args: [String: Value]?) -> (text: String, isError: Bool) {
        guard let newStart = Self.parseDate(args?["newStart"]?.stringValue),
              let newEnd = Self.parseDate(args?["newEnd"]?.stringValue), newEnd > newStart else {
            return ("Provide valid newStart and newEnd ISO-8601 timestamps (newEnd after newStart)", true)
        }
        if let eventId = args?["eventId"]?.stringValue, !eventId.isEmpty {
            let ok = coordinator.moveCommittedEvent(eventId: eventId, newStart: newStart, newEnd: newEnd)
            return ok
                ? (jsonString(["movedEvent": eventId, "newStart": Self.isoString(newStart), "newEnd": Self.isoString(newEnd)]), false)
                : ("Failed to update event \(eventId)", true)
        }
        if let sessionId = args?["sessionId"]?.stringValue,
           let index = engine.projectedSessions.firstIndex(where: { $0.id.uuidString == sessionId }) {
            engine.projectedSessions[index].startTime = newStart
            engine.projectedSessions[index].endTime = newEnd
            return (jsonString(["movedSession": Self.sessionDictionary(engine.projectedSessions[index])]), false)
        }
        return ("Provide eventId (committed event) or a valid sessionId (preview session)", true)
    }

    // MARK: get_config

    private func configDictionary() -> [String: Any] {
        [
            "sessions": [
                "work": engine.workSessions,
                "side": engine.sideSessions,
            ],
            "names": [
                "work": engine.workSessionName,
                "side": engine.sideSessionName,
            ],
            "durationsMinutes": [
                "work": engine.workSessionDuration,
                "side": engine.sideSessionDuration,
                "planning": engine.planningDuration,
                "rest": engine.restDuration,
                "sideRest": engine.sideRestDuration,
                "deepRest": engine.deepRestDuration,
            ],
            "pattern": engine.pattern.rawValue,
            "workSessionsPerCycle": engine.workSessionsPerCycle,
            "sideSessionsPerCycle": engine.sideSessionsPerCycle,
            "sideFirst": engine.sideFirst,
            "schedulePlanning": engine.schedulePlanning,
            "flexibleSideScheduling": engine.flexibleSideScheduling,
            "hours": [
                "dayStart": engine.dayStartHour,
                "dayEnd": engine.dayEndHour,
                "scheduleEnd": engine.scheduleEndHour,
                "defaultStart": engine.defaultStartHour,
            ],
            "tasks": [
                "work": Self.lines(engine.workTasks),
                "side": Self.lines(engine.sideTasks),
                "deep": Self.lines(engine.deepTasks),
                "useWork": engine.useWorkTasks,
                "useSide": engine.useSideTasks,
                "useDeep": engine.useDeepTasks,
            ],
            "deepSession": [
                "enabled": engine.deepSessionConfig.enabled,
                "sessionCount": engine.deepSessionConfig.sessionCount,
                "injectAfterEvery": engine.deepSessionConfig.injectAfterEvery,
                "andThenGap": engine.deepSessionConfig.andThenGap,
                "name": engine.deepSessionConfig.name,
                "durationMinutes": engine.deepSessionConfig.duration,
                "calendarName": engine.deepSessionConfig.calendarName,
                "calendarIdentifier": Self.orNull(engine.deepSessionConfig.calendarIdentifier),
            ],
            "bigRest": [
                "enabled": engine.bigRestConfig.enabled,
                "count": engine.bigRestConfig.count,
                "durationMinutes": engine.bigRestConfig.duration,
                "afterMinutes": engine.bigRestConfig.afterMinutes,
            ],
            "calendars": [
                "workName": engine.workCalendarName,
                "sideName": engine.sideCalendarName,
                "workIdentifier": Self.orNull(engine.workCalendarIdentifier),
                "sideIdentifier": Self.orNull(engine.sideCalendarIdentifier),
            ],
        ]
    }

    // MARK: get_state

    private func stateDictionary() -> [String: Any] {
        [
            "projectedSessions": engine.projectedSessions.map(Self.sessionDictionary),
            "quotaCounts": [
                "work": engine.quotaCounts.work,
                "side": engine.quotaCounts.side,
                "deep": engine.quotaCounts.deep,
            ],
            "quotasSatisfied": engine.quotasSatisfied,
            "schedulingMessage": engine.schedulingMessage,
            "sessionsFrozen": engine.sessionsFrozen,
            "activePreset": Self.orNull(activePresetName()),
        ]
    }

    private func activePresetName() -> String? {
        guard let id = engine.currentPresetId else { return nil }
        return PresetStorage.shared.loadPresets().first { $0.id == id }?.name
    }

    // MARK: list_presets

    private func presetsList() -> [String: Any] {
        let presets = PresetStorage.shared.loadPresets()
        let items: [[String: Any]] = presets.map { preset in
            [
                "id": preset.id.uuidString,
                "name": preset.name,
                "icon": preset.icon,
                "summary": "\(preset.workSessionCount)W / \(preset.sideSessionCount)S · \(preset.pattern.rawValue)",
                "isActive": preset.id == engine.currentPresetId,
                "isModified": engine.isPresetModified(preset),
            ]
        }
        return ["presets": items, "activePresetId": Self.orNull(engine.currentPresetId?.uuidString)]
    }

    // MARK: get_day

    private func dayDictionary(for date: Date) async -> [String: Any] {
        let snapshot = await coordinator.daySnapshot(date: date)
        let events: [[String: Any]] = snapshot.busySlots.map { slot in
            [
                "id": slot.id,
                "title": slot.title,
                "start": Self.isoString(slot.startTime),
                "end": Self.isoString(slot.endTime),
                "calendar": slot.calendarName,
                "sessionType": Self.orNull(SessionFlowEventSemantics.sessionType(fromNotes: slot.notes)?.rawValue),
            ]
        }
        return [
            "date": Self.dayString(date),
            "events": events,
            "existingSessionCounts": [
                "work": snapshot.existingSessions.work,
                "side": snapshot.existingSessions.side,
                "deep": snapshot.existingSessions.deep,
            ],
            "availability": [
                "availableMinutes": snapshot.availability.availableMinutes,
                "possibleWorkSessions": snapshot.availability.possibleWorkSessions,
                "possibleSideSessions": snapshot.availability.possibleSideSessions,
                "possibleDeepSessions": snapshot.availability.possibleDeepSessions,
            ],
        ]
    }

    // MARK: - Serialization helpers

    static func sessionDictionary(_ session: ScheduledSession) -> [String: Any] {
        [
            "id": session.id.uuidString,
            "type": session.type.rawValue,
            "hashtag": "#" + session.hashtag(),
            "title": session.title,
            "start": isoString(session.startTime),
            "end": isoString(session.endTime),
            "durationMinutes": session.durationMinutes,
            "calendar": session.calendarName,
        ]
    }

    static let emptyObjectSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([:]),
        "additionalProperties": .bool(false),
    ])

    static func dateArgSchema(required: Bool) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object([
                "date": .object([
                    "type": .string("string"),
                    "description": .string("Day to inspect, as YYYY-MM-DD or ISO-8601. Defaults to today."),
                ]),
            ]),
        ]
        if required { schema["required"] = .array([.string("date")]) }
        return .object(schema)
    }

    /// Builds an object JSON Schema from `(name, type, description)` scalar properties.
    static func objectSchema(_ props: [(name: String, type: String, description: String)], required: [String] = []) -> Value {
        var properties: [String: Value] = [:]
        for prop in props {
            properties[prop.name] = .object([
                "type": .string(prop.type),
                "description": .string(prop.description),
            ])
        }
        var schema: [String: Value] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }

    private static func stringArrayProperty(_ description: String) -> Value {
        .object([
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "description": .string(description),
        ])
    }

    static let setTasksSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "work": stringArrayProperty("Work session task names, one per element."),
            "side": stringArrayProperty("Side session task names, one per element."),
            "deep": stringArrayProperty("Deep session task names, one per element."),
            "useWork": .object(["type": .string("boolean"), "description": .string("Use the work task names as session titles.")]),
            "useSide": .object(["type": .string("boolean"), "description": .string("Use the side task names as session titles.")]),
            "useDeep": .object(["type": .string("boolean"), "description": .string("Use the deep task names as session titles.")]),
        ]),
    ])

    static let setConfigSchema: Value = {
        var properties: [String: Value] = [:]
        let scalars: [(String, String, String)] = [
            ("workSessions", "integer", "Number of work sessions."),
            ("sideSessions", "integer", "Number of side sessions."),
            ("workSessionName", "string", "Default work session title."),
            ("sideSessionName", "string", "Default side session title."),
            ("workSessionDuration", "integer", "Work session length, minutes."),
            ("sideSessionDuration", "integer", "Side session length, minutes."),
            ("planningDuration", "integer", "Planning session length, minutes."),
            ("restDuration", "integer", "Break after work sessions, minutes."),
            ("sideRestDuration", "integer", "Break after side sessions, minutes."),
            ("deepRestDuration", "integer", "Break after deep sessions, minutes."),
            ("workSessionsPerCycle", "integer", "Work sessions per cycle (alternating/custom patterns)."),
            ("sideSessionsPerCycle", "integer", "Side sessions per cycle (custom pattern)."),
            ("sideFirst", "boolean", "Start cycles with a side session."),
            ("schedulePlanning", "boolean", "Inject a planning session at the start of the day."),
            ("flexibleSideScheduling", "boolean", "Allow side sessions to fill smaller gaps."),
            ("dayStartHour", "integer", "Timeline visibility start hour (display only)."),
            ("dayEndHour", "integer", "Timeline visibility end hour (display only)."),
            ("scheduleEndHour", "integer", "Hour scheduling stops (13–30; may exceed 24 for next day)."),
            ("defaultStartHour", "integer", "Default start hour when scheduling a non-today date."),
            ("pattern", "string", "Schedule pattern: Alternating, Alternating Reverse, All Work First, All Side First, Sides First & Last, or Custom Ratio."),
        ]
        for (name, type, description) in scalars {
            properties[name] = .object(["type": .string(type), "description": .string(description)])
        }
        properties["deepSession"] = .object([
            "type": .string("object"),
            "description": .string("Deep-session config. Keys: enabled, sessionCount, injectAfterEvery, andThenGap, name, duration, calendarName."),
        ])
        properties["bigRest"] = .object([
            "type": .string("object"),
            "description": .string("Long-rest config. Keys: enabled, count, duration, afterMinutes."),
        ])
        return .object(["type": .string("object"), "properties": .object(properties)])
    }()

    static let moveSchema: Value = objectSchema([
        ("eventId", "string", "Committed calendar event identifier (from get_day)."),
        ("sessionId", "string", "Preview session UUID (from get_state). Used if eventId is omitted."),
        ("newStart", "string", "New start time, ISO-8601."),
        ("newEnd", "string", "New end time, ISO-8601."),
    ], required: ["newStart", "newEnd"])

    static func stringArray(_ value: Value?) -> [String]? {
        guard let array = value?.arrayValue else { return nil }
        return array.compactMap { $0.stringValue }
    }

    static func orNull(_ value: String?) -> Any {
        if let value { return value }
        return NSNull()
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func isoString(_ date: Date) -> String { isoFormatter.string(from: date) }
    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let iso = isoFormatter.date(from: string) { return iso }
        return dayFormatter.date(from: string)
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Loads the bundled agent guide, served by the `learn` tool and the `sessionflow://guide` resource.
enum MCPGuide {
    static let resourceURI = "sessionflow://guide"
    static let resourceName = "SessionFlow Agent Guide"
    static let mimeType = "text/markdown"

    static func markdown() -> String {
        let candidates = [Bundle.main, Bundle(for: MCPGuideBundleToken.self)]
        for bundle in candidates {
            if let url = bundle.url(forResource: "AgentGuide", withExtension: "md"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return "SessionFlow agent guide is unavailable."
    }
}

private final class MCPGuideBundleToken {}
