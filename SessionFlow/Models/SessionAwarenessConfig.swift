import Foundation

// MARK: - Per-type ambient sound settings

struct SessionSoundConfig: Codable, Equatable {
    var sound: String           // Built-in ambient name, "Off", or custom name
    var volume: Float           // 0.0–1.0
    var customSoundPath: String? = nil
    var enabled: Bool = true

    static let off = SessionSoundConfig(sound: "Off", volume: 0.0, enabled: false)

    static let availableSounds = [
        "Clock Ticking",
        "Clock Ticking Slow",
        "Creek Atmosphere",
        "Kitchen Timer",
        "Duskfall on a River",
        "Light Rain",
        "Mountain Atmosphere",
        "Ocean Waves",
        "Peaceful Wind",
        "Thunder in the Woods",
    ]

    var isPlayable: Bool {
        enabled && sound != "Off"
    }

    init(sound: String, volume: Float, customSoundPath: String? = nil, enabled: Bool = true) {
        self.sound = sound
        self.volume = volume
        self.customSoundPath = customSoundPath
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? "Off"
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 0
        customSoundPath = try container.decodeIfPresent(String.self, forKey: .customSoundPath)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? (sound != "Off")
    }
}

// MARK: - Start/End transition sound settings

struct TransitionSoundConfig: Codable, Equatable {
    var sound: String           // Built-in transition name, "Off", or custom name
    var volume: Float           // 0.0–1.0
    var customSoundPath: String? = nil
    var enabled: Bool = true

    static let off = TransitionSoundConfig(sound: "Off", volume: 0.0, enabled: false)

    static let availableSounds = ["Hero", "Morse", "Glass", "Submarine", "Purr", "Gong", "Kitchen Timer"]

    var isPlayable: Bool {
        enabled && sound != "Off"
    }

    init(sound: String, volume: Float, customSoundPath: String? = nil, enabled: Bool = true) {
        self.sound = sound
        self.volume = volume
        self.customSoundPath = customSoundPath
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? "Off"
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 0
        customSoundPath = try container.decodeIfPresent(String.self, forKey: .customSoundPath)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? (sound != "Off")
    }
}

// MARK: - Time display mode

enum TimeDisplayMode: String, Codable, CaseIterable {
    case remaining = "remaining"
    case elapsed = "elapsed"
}

// MARK: - Accelerando config

struct AccelerandoConfig: Codable, Equatable {
    var enabled: Bool = false
    var maxMultiplier: Double = 1.0

    static let multiplierOptions: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0]
}

// MARK: - Codable rect for window position persistence

struct CodableRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

// MARK: - Custom sound entry

struct CustomSoundEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var filePath: String

    init(name: String, filePath: String) {
        self.id = UUID()
        self.name = name
        self.filePath = filePath
    }
}

// MARK: - Custom sound store

class CustomSoundStore {
    static let shared = CustomSoundStore()
    private static let storageKey = "SessionFlow.CustomSounds"

    private init() {}

    func loadEntries() -> [CustomSoundEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([CustomSoundEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func addEntry(_ entry: CustomSoundEntry) {
        var entries = loadEntries()
        entries.append(entry)
        save(entries)
    }

    func removeEntry(id: UUID) {
        var entries = loadEntries()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    func entry(named name: String) -> CustomSoundEntry? {
        loadEntries().first { $0.name == name }
    }

    private func save(_ entries: [CustomSoundEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Shortcut type filter

struct ShortcutTypeFilter: Codable, Equatable {
    var work: Bool = true
    var side: Bool = true
    var deep: Bool = true
    var planning: Bool = true
    var external: Bool = false

    func matches(sessionType: SessionType?, isBusySlot: Bool) -> Bool {
        if isBusySlot || sessionType == nil { return external }
        guard let type = sessionType else { return false }
        switch type {
        case .work: return work
        case .side: return side
        case .deep: return deep
        case .planning: return planning
        case .bigRest: return false
        }
    }

    /// Count of enabled types (out of 5)
    var enabledCount: Int {
        [work, side, deep, planning, external].filter { $0 }.count
    }
}

// MARK: - Shortcut trigger config

struct ShortcutTriggerConfig: Codable, Equatable {
    var isEnabled: Bool = false
    var shortcutName: String
    var leadTimeMinutes: Int? = nil   // Only for "approaching" trigger
    var typeFilter: ShortcutTypeFilter = .init()

    init(isEnabled: Bool = false, shortcutName: String, leadTimeMinutes: Int? = nil) {
        self.isEnabled = isEnabled
        self.shortcutName = shortcutName
        self.leadTimeMinutes = leadTimeMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        shortcutName = try c.decodeIfPresent(String.self, forKey: .shortcutName) ?? ""
        leadTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .leadTimeMinutes)
        typeFilter = try c.decodeIfPresent(ShortcutTypeFilter.self, forKey: .typeFilter) ?? .init()
    }
}

// MARK: - Shortcuts config

struct ShortcutsConfig: Codable, Equatable {
    var approaching: ShortcutTriggerConfig = .init(shortcutName: "SessionFlow Approaching", leadTimeMinutes: 1)
    var started: ShortcutTriggerConfig = .init(shortcutName: "SessionFlow Started")
    var ended: ShortcutTriggerConfig = .init(shortcutName: "SessionFlow Ended")
    var restStarted: ShortcutTriggerConfig = .init(shortcutName: "Rest Started")
    var restEnded: ShortcutTriggerConfig = .init(shortcutName: "Rest Ended")
    var restEndingSoon: ShortcutTriggerConfig = .init(shortcutName: "Rest Ending Soon")

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        approaching = try c.decodeIfPresent(ShortcutTriggerConfig.self, forKey: .approaching)
            ?? .init(shortcutName: "SessionFlow Approaching", leadTimeMinutes: 1)
        started = try c.decodeIfPresent(ShortcutTriggerConfig.self, forKey: .started)
            ?? .init(shortcutName: "SessionFlow Started")
        ended = try c.decodeIfPresent(ShortcutTriggerConfig.self, forKey: .ended)
            ?? .init(shortcutName: "SessionFlow Ended")
        restStarted = try c.decodeIfPresent(ShortcutTriggerConfig.self, forKey: .restStarted)
            ?? .init(shortcutName: "Rest Started")
        restEnded = try c.decodeIfPresent(ShortcutTriggerConfig.self, forKey: .restEnded)
            ?? .init(shortcutName: "Rest Ended")
        restEndingSoon = try c.decodeIfPresent(ShortcutTriggerConfig.self, forKey: .restEndingSoon)
            ?? .init(shortcutName: "Rest Ending Soon")
    }
}

// MARK: - Focus weights (percentage each rating contributes to focus time)

struct FocusWeights: Codable, Equatable {
    var rocketPercent: Int = 100   // Fire
    var completedPercent: Int = 80 // Done
    var partialPercent: Int = 50   // Partly
    var skippedPercent: Int = 0    // Skipped

    func multiplier(for rating: SessionRating) -> Double {
        switch rating {
        case .rocket: return Double(rocketPercent) / 100.0
        case .completed: return Double(completedPercent) / 100.0
        case .partial: return Double(partialPercent) / 100.0
        case .skipped: return Double(skippedPercent) / 100.0
        }
    }
}

// MARK: - Main config

struct SessionAwarenessConfig: Codable, Equatable {
    var enabled: Bool = true
    var masterVolume: Float = 1.0           // 0.0–1.0, scales all audio output
    var outputDeviceUID: String? = nil      // nil = system default
    var muteEnabled: Bool = false           // Manual mute (always mute)
    var micAwareEnabled: Bool = true        // Auto-mute while mic is active

    // Per-type ambient sound settings
    var workSound: SessionSoundConfig = .init(sound: "Clock Ticking", volume: 0.6)
    var sideSound: SessionSoundConfig = .init(sound: "Clock Ticking", volume: 0.4)
    var deepSound: SessionSoundConfig = .init(sound: "Mountain Atmosphere", volume: 0.4)
    var planningSound: SessionSoundConfig = .init(sound: "Peaceful Wind", volume: 0.3)
    var breakSound: SessionSoundConfig = .init(sound: "Ocean Waves", volume: 0.3)

    // Non-tagged calendar events (busy slots without our tags)
    var trackOtherEvents: Bool = false
    var otherEventsSound: SessionSoundConfig = .init(sound: "Clock Ticking Slow", volume: 0.5)

    // Start/End session transition sounds
    var startSound: TransitionSoundConfig = .init(sound: "Hero", volume: 0.6)
    var endSound: TransitionSoundConfig = .init(sound: "Gong", volume: 0.6)

    // Phase 2: Time display mode
    var timeDisplayMode: TimeDisplayMode = .remaining

    // Phase 3: Ending soon transition
    var endingSoonSound: TransitionSoundConfig = .init(sound: "Submarine", volume: 0.5)

    // Phase 3: Presence reminder
    var presenceReminderEnabled: Bool = true
    var presenceReminderIntervalMinutes: Int = 10
    var presenceReminderSound: TransitionSoundConfig = .init(sound: "Glass", volume: 0.4)

    // Phase 3: Accelerando per type
    var workSoundAccelerando: AccelerandoConfig = .init(enabled: true, maxMultiplier: 1.2)
    var sideSoundAccelerando: AccelerandoConfig = .init(enabled: true, maxMultiplier: 1.2)
    var deepSoundAccelerando: AccelerandoConfig = .init()
    var planningSoundAccelerando: AccelerandoConfig = .init()
    var otherEventsSoundAccelerando: AccelerandoConfig = .init(enabled: true, maxMultiplier: 1.2)

    // Productivity feedback
    var productivityEnabled: Bool = true
    var focusWeights: FocusWeights = .init()

    // Phase 5: Menu bar & Dock
    var showMenuBarItem: Bool = true
    var showDockProgress: Bool = true

    // Phase 6: Mini-player & main window frames
    var miniPlayerFrame: CodableRect? = nil
    var mainWindowFrame: CodableRect? = nil

    // Rest tracking between sessions
    var trackRests: Bool = false
    var restSound: SessionSoundConfig = .init(sound: "Ocean Waves", volume: 0.3)
    var restSoundAccelerando: AccelerandoConfig = .init()
    var restEndingSoonLeadTimeMinutes: Int = 2

    // Shortcuts integration
    var shortcuts: ShortcutsConfig = .init()

    static let `default` = SessionAwarenessConfig()

    // MARK: - Persistence

    private static let storageKey = "SessionFlow.SessionAwarenessConfig"

    static func load() -> SessionAwarenessConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(SessionAwarenessConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Coding keys (includes legacy muteMode for migration)

    private enum CodingKeys: String, CodingKey {
        case enabled, masterVolume, outputDeviceUID
        case muteEnabled, micAwareEnabled
        case muteMode // legacy — decoded for migration, never encoded
        case workSound, sideSound, deepSound, planningSound, breakSound
        case trackOtherEvents, otherEventsSound
        case startSound, endSound
        case timeDisplayMode, endingSoonSound
        case presenceReminderEnabled, presenceReminderIntervalMinutes, presenceReminderSound
        case workSoundAccelerando, sideSoundAccelerando, deepSoundAccelerando
        case planningSoundAccelerando, otherEventsSoundAccelerando
        case productivityEnabled, focusWeights
        case showMenuBarItem, showDockProgress
        case miniPlayerFrame, mainWindowFrame
        case trackRests, restSound, restSoundAccelerando, restEndingSoonLeadTimeMinutes
        case shortcuts
    }

    // MARK: - Encoding (excludes legacy muteMode)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(masterVolume, forKey: .masterVolume)
        try c.encodeIfPresent(outputDeviceUID, forKey: .outputDeviceUID)
        try c.encode(muteEnabled, forKey: .muteEnabled)
        try c.encode(micAwareEnabled, forKey: .micAwareEnabled)
        try c.encode(workSound, forKey: .workSound)
        try c.encode(sideSound, forKey: .sideSound)
        try c.encode(deepSound, forKey: .deepSound)
        try c.encode(planningSound, forKey: .planningSound)
        try c.encode(breakSound, forKey: .breakSound)
        try c.encode(trackOtherEvents, forKey: .trackOtherEvents)
        try c.encode(otherEventsSound, forKey: .otherEventsSound)
        try c.encode(startSound, forKey: .startSound)
        try c.encode(endSound, forKey: .endSound)
        try c.encode(timeDisplayMode, forKey: .timeDisplayMode)
        try c.encode(endingSoonSound, forKey: .endingSoonSound)
        try c.encode(presenceReminderEnabled, forKey: .presenceReminderEnabled)
        try c.encode(presenceReminderIntervalMinutes, forKey: .presenceReminderIntervalMinutes)
        try c.encode(presenceReminderSound, forKey: .presenceReminderSound)
        try c.encode(workSoundAccelerando, forKey: .workSoundAccelerando)
        try c.encode(sideSoundAccelerando, forKey: .sideSoundAccelerando)
        try c.encode(deepSoundAccelerando, forKey: .deepSoundAccelerando)
        try c.encode(planningSoundAccelerando, forKey: .planningSoundAccelerando)
        try c.encode(otherEventsSoundAccelerando, forKey: .otherEventsSoundAccelerando)
        try c.encode(productivityEnabled, forKey: .productivityEnabled)
        try c.encode(focusWeights, forKey: .focusWeights)
        try c.encode(showMenuBarItem, forKey: .showMenuBarItem)
        try c.encode(showDockProgress, forKey: .showDockProgress)
        try c.encodeIfPresent(miniPlayerFrame, forKey: .miniPlayerFrame)
        try c.encodeIfPresent(mainWindowFrame, forKey: .mainWindowFrame)
        try c.encode(trackRests, forKey: .trackRests)
        try c.encode(restSound, forKey: .restSound)
        try c.encode(restSoundAccelerando, forKey: .restSoundAccelerando)
        try c.encode(restEndingSoonLeadTimeMinutes, forKey: .restEndingSoonLeadTimeMinutes)
        try c.encode(shortcuts, forKey: .shortcuts)
    }

    // MARK: - Backward-compatible decoding

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        masterVolume = try c.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1.0
        outputDeviceUID = try c.decodeIfPresent(String.self, forKey: .outputDeviceUID)
        // Backward compat: migrate old muteMode enum to new booleans
        if let legacy = try? c.decodeIfPresent(String.self, forKey: .muteMode) {
            muteEnabled = (legacy == "on")
            micAwareEnabled = (legacy == "auto")
        } else {
            muteEnabled = try c.decodeIfPresent(Bool.self, forKey: .muteEnabled) ?? false
            micAwareEnabled = try c.decodeIfPresent(Bool.self, forKey: .micAwareEnabled) ?? true
        }

        workSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .workSound) ?? .init(sound: "Clock Ticking", volume: 0.6)
        sideSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .sideSound) ?? .init(sound: "Clock Ticking", volume: 0.4)
        deepSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .deepSound) ?? .init(sound: "Mountain Atmosphere", volume: 0.4)
        planningSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .planningSound) ?? .init(sound: "Peaceful Wind", volume: 0.3)
        breakSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .breakSound) ?? .off

        trackOtherEvents = try c.decodeIfPresent(Bool.self, forKey: .trackOtherEvents) ?? false
        otherEventsSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .otherEventsSound) ?? .init(sound: "Clock Ticking Slow", volume: 0.5)

        startSound = try c.decodeIfPresent(TransitionSoundConfig.self, forKey: .startSound) ?? .init(sound: "Hero", volume: 0.6)
        endSound = try c.decodeIfPresent(TransitionSoundConfig.self, forKey: .endSound) ?? .init(sound: "Gong", volume: 0.6)

        timeDisplayMode = try c.decodeIfPresent(TimeDisplayMode.self, forKey: .timeDisplayMode) ?? .remaining
        endingSoonSound = try c.decodeIfPresent(TransitionSoundConfig.self, forKey: .endingSoonSound) ?? .init(sound: "Submarine", volume: 0.5)

        presenceReminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .presenceReminderEnabled) ?? true
        presenceReminderIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .presenceReminderIntervalMinutes) ?? 10
        presenceReminderSound = try c.decodeIfPresent(TransitionSoundConfig.self, forKey: .presenceReminderSound) ?? .init(sound: "Glass", volume: 0.4)

        workSoundAccelerando = try c.decodeIfPresent(AccelerandoConfig.self, forKey: .workSoundAccelerando) ?? .init(enabled: true, maxMultiplier: 1.2)
        sideSoundAccelerando = try c.decodeIfPresent(AccelerandoConfig.self, forKey: .sideSoundAccelerando) ?? .init(enabled: true, maxMultiplier: 1.2)
        deepSoundAccelerando = try c.decodeIfPresent(AccelerandoConfig.self, forKey: .deepSoundAccelerando) ?? .init()
        planningSoundAccelerando = try c.decodeIfPresent(AccelerandoConfig.self, forKey: .planningSoundAccelerando) ?? .init()
        otherEventsSoundAccelerando = try c.decodeIfPresent(AccelerandoConfig.self, forKey: .otherEventsSoundAccelerando) ?? .init(enabled: true, maxMultiplier: 1.2)

        productivityEnabled = try c.decodeIfPresent(Bool.self, forKey: .productivityEnabled) ?? true
        focusWeights = try c.decodeIfPresent(FocusWeights.self, forKey: .focusWeights) ?? .init()
        showMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? true
        showDockProgress = try c.decodeIfPresent(Bool.self, forKey: .showDockProgress) ?? true
        miniPlayerFrame = try c.decodeIfPresent(CodableRect.self, forKey: .miniPlayerFrame)
        mainWindowFrame = try c.decodeIfPresent(CodableRect.self, forKey: .mainWindowFrame)
        trackRests = try c.decodeIfPresent(Bool.self, forKey: .trackRests) ?? false
        restSound = try c.decodeIfPresent(SessionSoundConfig.self, forKey: .restSound) ?? .init(sound: "Ocean Waves", volume: 0.3)
        restSoundAccelerando = try c.decodeIfPresent(AccelerandoConfig.self, forKey: .restSoundAccelerando) ?? .init()
        restEndingSoonLeadTimeMinutes = try c.decodeIfPresent(Int.self, forKey: .restEndingSoonLeadTimeMinutes) ?? 2
        shortcuts = try c.decodeIfPresent(ShortcutsConfig.self, forKey: .shortcuts) ?? .init()
    }

    init() {}

    // MARK: - Helpers

    func soundConfig(for sessionType: SessionType) -> SessionSoundConfig {
        switch sessionType {
        case .work: return workSound
        case .side: return sideSound
        case .deep: return deepSound
        case .planning: return planningSound
        case .bigRest: return breakSound
        }
    }

    func accelerandoConfig(for sessionType: SessionType) -> AccelerandoConfig {
        switch sessionType {
        case .work: return workSoundAccelerando
        case .side: return sideSoundAccelerando
        case .deep: return deepSoundAccelerando
        case .planning: return planningSoundAccelerando
        case .bigRest: return .init()
        }
    }
}
