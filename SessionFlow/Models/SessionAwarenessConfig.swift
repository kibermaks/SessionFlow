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

// MARK: - Main config

struct SessionAwarenessConfig: Codable, Equatable {
    var enabled: Bool = true
    var masterVolume: Float = 1.0           // 0.0–1.0, scales all audio output
    var outputDeviceUID: String? = nil      // nil = system default

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

    // Phase 5: Menu bar & Dock
    var showMenuBarItem: Bool = true
    var showDockProgress: Bool = true

    // Phase 6: Mini-player & main window frames
    var miniPlayerFrame: CodableRect? = nil
    var mainWindowFrame: CodableRect? = nil

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

    // MARK: - Backward-compatible decoding

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        masterVolume = try c.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1.0
        outputDeviceUID = try c.decodeIfPresent(String.self, forKey: .outputDeviceUID)

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

        showMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarItem) ?? true
        showDockProgress = try c.decodeIfPresent(Bool.self, forKey: .showDockProgress) ?? true
        miniPlayerFrame = try c.decodeIfPresent(CodableRect.self, forKey: .miniPlayerFrame)
        mainWindowFrame = try c.decodeIfPresent(CodableRect.self, forKey: .mainWindowFrame)
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
