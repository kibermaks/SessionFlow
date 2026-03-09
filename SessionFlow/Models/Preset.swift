import Foundation
import EventKit

// MARK: - Preset Schema Version
/// Tracks the schema version of presets for migration purposes
/// Increment this when adding new required fields or making breaking changes
enum PresetSchemaVersion: Int, Codable, Comparable {
    case v1 = 1  // Initial version (before flexibleSideScheduling)
    case v2 = 2  // Added flexibleSideScheduling field
    case v3 = 3  // Added calendar identifiers
    
    static let current: PresetSchemaVersion = .v3
    
    static func < (lhs: PresetSchemaVersion, rhs: PresetSchemaVersion) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Calendar Mapping for Presets
struct CalendarMapping: Codable, Equatable {
    var workCalendarName: String
    var sideCalendarName: String
    var workCalendarIdentifier: String?
    var sideCalendarIdentifier: String?
    
    static let `default` = CalendarMapping(
        workCalendarName: "Work",
        sideCalendarName: "Side Tasks",
        workCalendarIdentifier: nil,
        sideCalendarIdentifier: nil
    )
}

// MARK: - Deep Session Configuration
struct DeepSessionConfig: Codable, Equatable {
    var enabled: Bool
    var sessionCount: Int
    var injectAfterEvery: Int
    var name: String
    var duration: Int
    var calendarName: String
    var calendarIdentifier: String?
    var andThenGap: Int  // slots (regular sessions) between consecutive deep sessions

    init(enabled: Bool = false, sessionCount: Int = 1, injectAfterEvery: Int = 3, name: String = "Deep Session", duration: Int = 100, calendarName: String = "Work", calendarIdentifier: String? = nil, andThenGap: Int = 2) {
        self.enabled = enabled
        self.sessionCount = sessionCount
        self.injectAfterEvery = injectAfterEvery
        self.name = name
        self.duration = duration
        self.calendarName = calendarName
        self.calendarIdentifier = calendarIdentifier
        self.andThenGap = andThenGap
    }

    // Support decoding presets saved before andThenGap existed
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        sessionCount = try container.decode(Int.self, forKey: .sessionCount)
        injectAfterEvery = try container.decode(Int.self, forKey: .injectAfterEvery)
        name = try container.decode(String.self, forKey: .name)
        duration = try container.decode(Int.self, forKey: .duration)
        calendarName = try container.decode(String.self, forKey: .calendarName)
        calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier)
        andThenGap = try container.decodeIfPresent(Int.self, forKey: .andThenGap) ?? 2
    }

    static let `default` = DeepSessionConfig()
}

// MARK: - Big Rest Configuration
struct BigRestConfig: Codable, Equatable {
    var enabled: Bool
    var count: Int          // max number of long rests to inject
    var duration: Int       // minutes
    var afterMinutes: Int   // cumulative session minutes before injecting a big rest

    init(enabled: Bool = true, count: Int = 1, duration: Int = 50, afterMinutes: Int = 120) {
        self.enabled = enabled
        self.count = count
        self.duration = duration
        self.afterMinutes = afterMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 50
        afterMinutes = try container.decodeIfPresent(Int.self, forKey: .afterMinutes) ?? 120
    }

    static let `default` = BigRestConfig()
}

// MARK: - Preset Configuration
struct Preset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    
    // Session counts
    var workSessionCount: Int
    var sideSessionCount: Int
    
    // Session names
    var workSessionName: String
    var sideSessionName: String
    
    // Durations (in minutes)
    var workSessionDuration: Int
    var sideSessionDuration: Int
    var planningDuration: Int
    var sideSessionsPerCycle: Int // For Custom Ratio
    var sideFirst: Bool // For Custom Ratio
    
    var deepSessionConfig: DeepSessionConfig
    
    var calendarMapping: CalendarMapping
    
    var deepRestDuration: Int
    
    var restDuration: Int
    var sideRestDuration: Int
    
    var schedulePlanning: Bool
    var pattern: SchedulePattern
    var workSessionsPerCycle: Int
    var flexibleSideScheduling: Bool

    var bigRestConfig: BigRestConfig

    // Default start hour for future days
    var defaultStartHour: Int
    
    // Schema version for migration tracking
    var schemaVersion: PresetSchemaVersion
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "calendar",
        workSessionCount: Int = 5,
        sideSessionCount: Int = 2,
        workSessionName: String = "Work Session",
        sideSessionName: String = "Side Session",
        workSessionDuration: Int = 40,
        sideSessionDuration: Int = 30,
        planningDuration: Int = 10,
        restDuration: Int = 10,
        sideRestDuration: Int? = nil,
        deepRestDuration: Int? = nil,
        schedulePlanning: Bool = true,
        pattern: SchedulePattern = .alternating,
        workSessionsPerCycle: Int = 2,
        sideSessionsPerCycle: Int = 2,
        sideFirst: Bool = false,
        deepSessionConfig: DeepSessionConfig = .default,
        flexibleSideScheduling: Bool = true,
        bigRestConfig: BigRestConfig = .default,
        calendarMapping: CalendarMapping = .default,
        defaultStartHour: Int = 8,
        schemaVersion: PresetSchemaVersion = .current
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.workSessionCount = workSessionCount
        self.sideSessionCount = sideSessionCount
        self.workSessionName = workSessionName
        self.sideSessionName = sideSessionName
        self.workSessionDuration = workSessionDuration
        self.sideSessionDuration = sideSessionDuration
        self.planningDuration = planningDuration
        self.restDuration = restDuration
        
        // Calculate derived durations based on work and rest
        self.sideRestDuration = sideRestDuration ?? Self.calculateSideRest(from: restDuration)
        self.deepRestDuration = deepRestDuration ?? Self.calculateDeepRest(from: restDuration)
        
        self.schedulePlanning = schedulePlanning
        self.pattern = pattern
        self.workSessionsPerCycle = workSessionsPerCycle
        self.sideSessionsPerCycle = sideSessionsPerCycle
        self.sideFirst = sideFirst
        self.deepSessionConfig = deepSessionConfig
        self.flexibleSideScheduling = flexibleSideScheduling
        self.bigRestConfig = bigRestConfig
        self.calendarMapping = calendarMapping
        self.defaultStartHour = defaultStartHour
        self.schemaVersion = schemaVersion
    }
    
    // MARK: - Session Count Calculation Helpers
    
    /// Calculates work sessions for standard presets (1x basic)
    static func calculateStandardWorkSessions(from basicSessions: Int) -> Int {
        return basicSessions
    }
    
    /// Calculates work sessions for focus day (1.25x basic, rounded down)
    static func calculateFocusWorkSessions(from basicSessions: Int) -> Int {
        return Int(floor(Double(basicSessions) * 1.25))
    }
    
    /// Calculates side sessions for standard presets (0.5x work sessions, rounded down)
    static func calculateStandardSideSessions(from workSessions: Int) -> Int {
        return Int(floor(Double(workSessions) * 0.5))
    }
    
    /// Calculates side sessions for focus day (0.35x work sessions, rounded down)
    static func calculateFocusSideSessions(from workSessions: Int) -> Int {
        return Int(floor(Double(workSessions) * 0.35))
    }
    
    /// Calculates work sessions for light day (0.5x standard work, rounded up)
    static func calculateLightWorkSessions(from standardWorkSessions: Int) -> Int {
        return Int(ceil(Double(standardWorkSessions) * 0.5))
    }
    
    /// Calculates side sessions for light day (0.5x standard side, rounded up)
    static func calculateLightSideSessions(from standardSideSessions: Int) -> Int {
        return Int(ceil(Double(standardSideSessions) * 0.5))
    }
    
    // MARK: - Duration Calculation Helpers
    
    /// Calculates side session duration: 3/4 of work duration, rounded up to nearest 5 mins
    static func calculateSideDuration(from workDuration: Int) -> Int {
        let raw = Double(workDuration) * 0.75
        return Int(ceil(raw / 5.0) * 5.0)
    }
    
    /// Calculates deep session duration: 2.5x of work duration, rounded up to nearest 5 mins
    static func calculateDeepDuration(from workDuration: Int) -> Int {
        let raw = Double(workDuration) * 2.5
        return Int(ceil(raw / 5.0) * 5.0)
    }
    
    /// Calculates side rest duration: 3/4 of work rest, rounded up to nearest 5 mins
    static func calculateSideRest(from restDuration: Int) -> Int {
        let raw = Double(restDuration) * 0.75
        return max(5, Int(ceil(raw / 5.0) * 5.0))
    }
    
    /// Calculates deep rest duration: 2.5x of work rest, rounded up to nearest 5 mins
    static func calculateDeepRest(from restDuration: Int) -> Int {
        let raw = Double(restDuration) * 2.5
        return Int(ceil(raw / 5.0) * 5.0)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, icon
        case workSessionCount, sideSessionCount
        case workSessionName, sideSessionName
        case workSessionDuration, sideSessionDuration
        case planningDuration, restDuration, sideRestDuration, deepRestDuration
        case schedulePlanning, pattern, workSessionsPerCycle, sideSessionsPerCycle, sideFirst
        case deepSessionConfig, flexibleSideScheduling, bigRestConfig, calendarMapping, defaultStartHour
        case schemaVersion
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        workSessionCount = try container.decode(Int.self, forKey: .workSessionCount)
        sideSessionCount = try container.decode(Int.self, forKey: .sideSessionCount)
        workSessionName = try container.decode(String.self, forKey: .workSessionName)
        sideSessionName = try container.decode(String.self, forKey: .sideSessionName)
        workSessionDuration = try container.decode(Int.self, forKey: .workSessionDuration)
        sideSessionDuration = try container.decode(Int.self, forKey: .sideSessionDuration)
        planningDuration = try container.decode(Int.self, forKey: .planningDuration)
        restDuration = try container.decode(Int.self, forKey: .restDuration)
        sideRestDuration = try container.decode(Int.self, forKey: .sideRestDuration)
        deepRestDuration = try container.decodeIfPresent(Int.self, forKey: .deepRestDuration) ?? restDuration
        schedulePlanning = try container.decode(Bool.self, forKey: .schedulePlanning)
        pattern = try container.decode(SchedulePattern.self, forKey: .pattern)
        workSessionsPerCycle = try container.decode(Int.self, forKey: .workSessionsPerCycle)
        sideSessionsPerCycle = try container.decodeIfPresent(Int.self, forKey: .sideSessionsPerCycle) ?? 1
        sideFirst = try container.decodeIfPresent(Bool.self, forKey: .sideFirst) ?? false
        deepSessionConfig = try container.decode(DeepSessionConfig.self, forKey: .deepSessionConfig)
        flexibleSideScheduling = try container.decodeIfPresent(Bool.self, forKey: .flexibleSideScheduling) ?? true
        bigRestConfig = try container.decodeIfPresent(BigRestConfig.self, forKey: .bigRestConfig) ?? .default
        calendarMapping = try container.decode(CalendarMapping.self, forKey: .calendarMapping)
        defaultStartHour = try container.decodeIfPresent(Int.self, forKey: .defaultStartHour) ?? 8
        // If version is missing, assume v1 (old preset)
        schemaVersion = try container.decodeIfPresent(PresetSchemaVersion.self, forKey: .schemaVersion) ?? .v1
    }
    
    // MARK: - Default Presets
    private static let basicSessions = 5
    private static let workDuration = 40
    private static let restDuration = 10
    
    static let defaultWorkday = Preset(
        name: "Standard Day",
        icon: "briefcase.fill",
        workSessionCount: calculateStandardWorkSessions(from: basicSessions),
        sideSessionCount: calculateStandardSideSessions(from: calculateStandardWorkSessions(from: basicSessions)),
        workSessionDuration: workDuration,
        sideSessionDuration: calculateSideDuration(from: workDuration),
        restDuration: restDuration,
        pattern: .alternating,
        calendarMapping: CalendarMapping(
            workCalendarName: "Work",
            sideCalendarName: "Side Tasks",
            workCalendarIdentifier: nil,
            sideCalendarIdentifier: nil
        )
    )
    
    static let focusDay = Preset(
        name: "Focus Day",
        icon: "brain.head.profile",
        workSessionCount: calculateFocusWorkSessions(from: basicSessions),
        sideSessionCount: calculateFocusSideSessions(from: calculateFocusWorkSessions(from: basicSessions)),
        workSessionDuration: workDuration,
        sideSessionDuration: calculateSideDuration(from: workDuration),
        restDuration: restDuration,
        pattern: .alternating,
        deepSessionConfig: DeepSessionConfig(
            enabled: true,
            sessionCount: 1,
            injectAfterEvery: 3,
            name: "Deep Session",
            duration: calculateDeepDuration(from: workDuration),
            calendarName: "Work",
            calendarIdentifier: nil
        ),
        calendarMapping: CalendarMapping(
            workCalendarName: "Work",
            sideCalendarName: "Side Tasks",
            workCalendarIdentifier: nil,
            sideCalendarIdentifier: nil
        )
    )
    
    static let allWorkFirst = Preset(
        name: "All Work First",
        icon: "arrow.right.circle.fill",
        workSessionCount: calculateStandardWorkSessions(from: basicSessions),
        sideSessionCount: calculateStandardSideSessions(from: calculateStandardWorkSessions(from: basicSessions)),
        workSessionDuration: workDuration,
        sideSessionDuration: calculateSideDuration(from: workDuration),
        restDuration: restDuration,
        pattern: .allWorkFirst,
        calendarMapping: CalendarMapping(
            workCalendarName: "Work",
            sideCalendarName: "Side Tasks",
            workCalendarIdentifier: nil,
            sideCalendarIdentifier: nil
        )
    )
    
    static let weekend = Preset(
        name: "Weekend",
        icon: "sun.max.fill",
        workSessionCount: 0,
        sideSessionCount: basicSessions,
        workSessionName: "Weekend Work",
        sideSessionName: "Weekend Side",
        workSessionDuration: workDuration,
        sideSessionDuration: calculateSideDuration(from: workDuration),
        restDuration: restDuration,
        schedulePlanning: false,
        pattern: .allSideFirst,
        deepSessionConfig: DeepSessionConfig(
            enabled: true,
            sessionCount: 1,
            injectAfterEvery: 3,
            name: "Deep Session",
            duration: calculateDeepDuration(from: workDuration),
            calendarName: "Work",
            calendarIdentifier: nil
        ),
        calendarMapping: CalendarMapping(
            workCalendarName: "Work",
            sideCalendarName: "Side Tasks",
            workCalendarIdentifier: nil,
            sideCalendarIdentifier: nil
        ),
        defaultStartHour: 10
    )
    
    static let lightDay = Preset(
        name: "Light Day",
        icon: "leaf.fill",
        workSessionCount: calculateLightWorkSessions(from: calculateStandardWorkSessions(from: basicSessions)),
        sideSessionCount: calculateLightSideSessions(from: calculateStandardSideSessions(from: calculateStandardWorkSessions(from: basicSessions))),
        workSessionDuration: workDuration,
        sideSessionDuration: calculateSideDuration(from: workDuration),
        restDuration: restDuration,
        pattern: .alternating,
        calendarMapping: CalendarMapping(
            workCalendarName: "Work",
            sideCalendarName: "Side Tasks",
            workCalendarIdentifier: nil,
            sideCalendarIdentifier: nil
        )
    )
    
    static let initialPresets: [Preset] = [
        .focusDay,
        .defaultWorkday,
        .allWorkFirst,
        .weekend,
        .lightDay
    ]
    
    // MARK: - Create Initial Presets with Custom Calendars
    /// Creates the initial set of presets with the user's selected calendar names from setup
    static func createInitialPresets(
        workCalendar: String,
        sideCalendar: String,
        deepCalendar: String,
        workCalendarId: String? = nil,
        sideCalendarId: String? = nil,
        deepCalendarId: String? = nil,
        workDuration: Int = 40,
        restDuration: Int = 10,
        basicSessions: Int = 5
    ) -> [Preset] {
        let workMapping = CalendarMapping(
            workCalendarName: workCalendar,
            sideCalendarName: sideCalendar,
            workCalendarIdentifier: workCalendarId,
            sideCalendarIdentifier: sideCalendarId
        )
        
        // Calculate session counts
        let standardWork = calculateStandardWorkSessions(from: basicSessions)
        let standardSide = calculateStandardSideSessions(from: standardWork)
        let focusWork = calculateFocusWorkSessions(from: basicSessions)
        let focusSide = calculateFocusSideSessions(from: focusWork)
        let lightWork = calculateLightWorkSessions(from: standardWork)
        let lightSide = calculateLightSideSessions(from: standardSide)
        
        // Deep config disabled by default
        let deepConfigDisabled = DeepSessionConfig(
            enabled: false,
            sessionCount: 1,
            injectAfterEvery: 3,
            name: "Deep Session",
            duration: calculateDeepDuration(from: workDuration),
            calendarName: deepCalendar,
            calendarIdentifier: deepCalendarId
        )
        
        let bigRestCfg = BigRestConfig(
            enabled: false,
            duration: restDuration * 5,
            afterMinutes: workDuration * 3
        )

        // Deep config enabled for Focus Day preset
        let deepConfigEnabled = DeepSessionConfig(
            enabled: true,
            sessionCount: 1,
            injectAfterEvery: 3,
            name: "Deep Session",
            duration: calculateDeepDuration(from: workDuration),
            calendarName: deepCalendar,
            calendarIdentifier: deepCalendarId
        )

        // Deep config enabled for Focus Day preset
        let deepConfigWeekend = DeepSessionConfig(
            enabled: true,
            sessionCount: 1,
            injectAfterEvery: 2,
            name: "Weekend Deep",
            duration: calculateDeepDuration(from: workDuration),
            calendarName: deepCalendar,
            calendarIdentifier: deepCalendarId
        )
        
        return [
            Preset(
                name: "Focus Day",
                icon: "brain.head.profile",
                workSessionCount: focusWork,
                sideSessionCount: focusSide,
                workSessionDuration: workDuration,
                sideSessionDuration: calculateSideDuration(from: workDuration),
                restDuration: restDuration,
                pattern: .alternating,
                deepSessionConfig: deepConfigEnabled,
                bigRestConfig: bigRestCfg,
                calendarMapping: workMapping
            ),
            Preset(
                name: "Standard Day",
                icon: "briefcase.fill",
                workSessionCount: standardWork,
                sideSessionCount: standardSide,
                workSessionDuration: workDuration,
                sideSessionDuration: calculateSideDuration(from: workDuration),
                restDuration: restDuration,
                pattern: .alternating,
                deepSessionConfig: deepConfigDisabled,
                bigRestConfig: bigRestCfg,
                calendarMapping: workMapping
            ),
            Preset(
                name: "All Work First",
                icon: "arrow.right.circle.fill",
                workSessionCount: standardWork,
                sideSessionCount: standardSide,
                workSessionDuration: workDuration,
                sideSessionDuration: calculateSideDuration(from: workDuration),
                restDuration: restDuration,
                pattern: .allWorkFirst,
                deepSessionConfig: deepConfigDisabled,
                bigRestConfig: bigRestCfg,
                calendarMapping: workMapping
            ),
            Preset(
                name: "Weekend",
                icon: "sun.max.fill",
                workSessionCount: 0,
                sideSessionCount: basicSessions,
                workSessionName: "Weekend Work",
                sideSessionName: "Weekend Side",
                workSessionDuration: workDuration,
                sideSessionDuration: calculateSideDuration(from: workDuration),
                restDuration: restDuration,
                schedulePlanning: false,
                pattern: .alternatingReverse,
                deepSessionConfig: deepConfigWeekend,
                bigRestConfig: bigRestCfg,
                calendarMapping: workMapping,
                defaultStartHour: 10
            ),
            Preset(
                name: "Light Day",
                icon: "leaf.fill",
                workSessionCount: lightWork,
                sideSessionCount: lightSide,
                workSessionDuration: workDuration,
                sideSessionDuration: calculateSideDuration(from: workDuration),
                restDuration: restDuration,
                pattern: .alternating,
                deepSessionConfig: deepConfigDisabled,
                bigRestConfig: bigRestCfg,
                calendarMapping: workMapping
            )
        ]
    }
}

// MARK: - Preset Migration
extension Preset {
    /// Migrates a preset from an older schema version to the current version
    mutating func migrateToCurrentVersion() {
        while schemaVersion < PresetSchemaVersion.current {
            migrateToNextVersion()
        }
    }
    
    /// Migrates preset to the next version
    private mutating func migrateToNextVersion() {
        switch schemaVersion {
        case .v1:
            // Migration from v1 to v2: Add flexibleSideScheduling with default value
            // flexibleSideScheduling already has a default value in decoder (true),
            // but we ensure it's explicitly set here for migration clarity
            flexibleSideScheduling = true // Default to enabled for migrated presets
            schemaVersion = .v2
        case .v2:
            // Migration from v2 to v3: Initialize calendar identifiers as unknown
            if calendarMapping.workCalendarIdentifier == nil {
                calendarMapping.workCalendarIdentifier = nil
            }
            if calendarMapping.sideCalendarIdentifier == nil {
                calendarMapping.sideCalendarIdentifier = nil
            }
            if deepSessionConfig.calendarIdentifier == nil {
                deepSessionConfig.calendarIdentifier = nil
            }
            schemaVersion = .v3
        case .v3:
            break
        }
    }
}

// MARK: - Preset Storage Manager
class PresetStorage {
    static let shared = PresetStorage()
    private let presetsKey = "SessionFlow.Presets"
    private let lastActivePresetKey = "SessionFlow.LastActivePresetID"
    
    private init() {}
    
    func loadPresets() -> [Preset] {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           var presets = try? JSONDecoder().decode([Preset].self, from: data),
           !presets.isEmpty {
            // Migrate presets to current version if needed
            var needsSave = false
            for index in presets.indices {
                let oldVersion = presets[index].schemaVersion
                presets[index].migrateToCurrentVersion()
                if presets[index].schemaVersion != oldVersion {
                    needsSave = true
                }
            }
            
            // Save migrated presets if any were updated
            if needsSave {
                savePresets(presets)
            }
            
            return presets
        }
        // Return empty - presets should be created after calendar setup
        return []
    }
    
    /// Check if presets have been initialized (saved to storage)
    func hasInitializedPresets() -> Bool {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let presets = try? JSONDecoder().decode([Preset].self, from: data),
           !presets.isEmpty {
            return true
        }
        return false
    }
    
    /// Initialize presets with calendar names from setup
    func initializePresets(
        workCalendar: String,
        sideCalendar: String,
        deepCalendar: String,
        workCalendarId: String? = nil,
        sideCalendarId: String? = nil,
        deepCalendarId: String? = nil,
        workDuration: Int = 40,
        restDuration: Int = 10,
        basicSessions: Int = 5
    ) {
        let presets = Preset.createInitialPresets(
            workCalendar: workCalendar,
            sideCalendar: sideCalendar,
            deepCalendar: deepCalendar,
            workCalendarId: workCalendarId,
            sideCalendarId: sideCalendarId,
            deepCalendarId: deepCalendarId,
            workDuration: workDuration,
            restDuration: restDuration,
            basicSessions: basicSessions
        )
        savePresets(presets)
    }
    
    func savePresets(_ presets: [Preset]) {
        // Ensure all presets are at current version before saving
        var presetsToSave = presets
        for index in presetsToSave.indices {
            presetsToSave[index].schemaVersion = PresetSchemaVersion.current
        }
        
        guard let data = try? JSONEncoder().encode(presetsToSave) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }
    
    func addPreset(_ preset: Preset) {
        var presets = loadPresets()
        presets.append(preset)
        savePresets(presets)
    }
    
    func updatePreset(_ updatedPreset: Preset) {
        var presets = loadPresets()
        if let index = presets.firstIndex(where: { $0.id == updatedPreset.id }) {
            presets[index] = updatedPreset
            savePresets(presets)
        }
    }
    
    func deletePreset(_ preset: Preset) {
        var presets = loadPresets()
        presets.removeAll { $0.id == preset.id }
        savePresets(presets)
    }
    
    func populateCalendarIdentifiers(using calendars: [EKCalendar]) {
        guard !calendars.isEmpty else { return }
        var presets = loadPresets()
        var changed = false
        
        func identifier(for name: String) -> String? {
            calendars.first(where: { $0.title == name })?.calendarIdentifier
        }
        
        for index in presets.indices {
            if presets[index].calendarMapping.workCalendarIdentifier == nil,
               let id = identifier(for: presets[index].calendarMapping.workCalendarName) {
                presets[index].calendarMapping.workCalendarIdentifier = id
                changed = true
            }
            if presets[index].calendarMapping.sideCalendarIdentifier == nil,
               let id = identifier(for: presets[index].calendarMapping.sideCalendarName) {
                presets[index].calendarMapping.sideCalendarIdentifier = id
                changed = true
            }
            if presets[index].deepSessionConfig.calendarIdentifier == nil,
               let id = identifier(for: presets[index].deepSessionConfig.calendarName) {
                presets[index].deepSessionConfig.calendarIdentifier = id
                changed = true
            }
        }
        
        if changed {
            savePresets(presets)
        }
    }
    
    // MARK: - Persistence of Selection
    
    func saveLastActivePresetId(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: lastActivePresetKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastActivePresetKey)
        }
    }
    
    func loadLastActivePresetId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: lastActivePresetKey) else { return nil }
        return UUID(uuidString: str)
    }
}
