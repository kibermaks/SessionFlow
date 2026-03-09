import Foundation
import AVFoundation
import CoreAudio
import SwiftUI

class SessionAudioService: ObservableObject {

    // MARK: - Published state

    @Published var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: "SessionFlow.SessionAudioMuted")
            if isMuted { muteAmbient() } else if shouldBePlayingAmbient { resumeAmbient() }
        }
    }
    @Published var isPlaying: Bool = false
    @Published var availableOutputDevices: [AudioOutputDevice] = []

    // MARK: - Audio engine

    private var ambientEngine = AVAudioEngine()
    private var ambientPlayerNode = AVAudioPlayerNode()
    private var varispeedNode = AVAudioUnitVarispeed()
    private var transitionPlayer: AVAudioPlayer?

    private var currentAmbientBuffer: AVAudioPCMBuffer?
    private var currentAmbientConfig: SessionSoundConfig?
    private var shouldBePlayingAmbient = false
    private(set) var masterVolume: Float = 1.0

    // Preview pause/resume state
    private var previewPausedConfig: SessionSoundConfig?
    private var previewPausedShouldPlay = false

    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Output device model

    struct AudioOutputDevice: Identifiable, Equatable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    // MARK: - Sound file mapping

    private static let ambientFiles: [String: (name: String, ext: String)] = [
        "Clock Ticking": ("Clock Ticking", "wav"),
        "Clock Ticking Slow": ("Clock Ticking Slow", "wav"),
        "Kitchen Timer": ("Kitchen Timer", "wav"),
        "Duskfall on a River": ("Duskfall on a River", "mp3"),
        "Light Rain": ("Light Rain Falling on Forest Floor", "mp3"),
        "Mountain Atmosphere": ("Mountain Atmosphere", "mp3"),
        "Ocean Waves": ("Ocean Waves", "mp3"),
        "Peaceful Wind": ("Peaceful Wind Atop a Hill", "mp3"),
        "Thunder in the Woods": ("Thunder in the Woods", "mp3"),
    ]

    private static let transitionFiles: [String: (name: String, ext: String)] = [
        "Kitchen Timer": ("Kitchen Timer", "wav"),
        "Gong": ("Gong", "mp3"),
        "Hero": ("Hero", "aiff"),
        "Morse": ("Morse", "aiff"),
        "Glass": ("Glass", "aiff"),
        "Submarine": ("Submarine", "aiff"),
        "Purr": ("Purr", "aiff"),
    ]

    // MARK: - Init

    init() {
        self.isMuted = UserDefaults.standard.bool(forKey: "SessionFlow.SessionAudioMuted")
        setupAmbientEngine()
        refreshOutputDevices()
        observeDeviceChanges()
        observeEngineConfigChanges()
    }

    deinit {
        removeDeviceListener()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Ambient Engine Setup

    private func setupAmbientEngine() {
        ambientEngine.attach(ambientPlayerNode)
        ambientEngine.attach(varispeedNode)
        ambientEngine.connect(ambientPlayerNode, to: varispeedNode, format: nil)
        ambientEngine.connect(varispeedNode, to: ambientEngine.mainMixerNode, format: nil)
    }

    // MARK: - Reset / Fix

    /// Full audio reset: stops everything, tears down engine, rebuilds from scratch
    func resetAudioEngine() {
        // Stop all playback
        ambientPlayerNode.stop()
        transitionPlayer?.stop()
        transitionPlayer = nil

        // Stop engine
        if ambientEngine.isRunning {
            ambientEngine.stop()
        }

        // Clear all state
        currentAmbientBuffer = nil
        currentAmbientConfig = nil
        shouldBePlayingAmbient = false
        previewPausedConfig = nil
        previewPausedShouldPlay = false
        varispeedNode.rate = 1.0

        // Detach and rebuild nodes
        ambientEngine.detach(ambientPlayerNode)
        ambientEngine.detach(varispeedNode)
        ambientPlayerNode = AVAudioPlayerNode()
        varispeedNode = AVAudioUnitVarispeed()
        setupAmbientEngine()

        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }

    // MARK: - Master Volume

    func setMasterVolume(_ volume: Float) {
        masterVolume = volume
        ambientEngine.mainMixerNode.outputVolume = volume
        transitionPlayer?.volume = (transitionPlayer?.volume ?? 0) // volume already set per-play
    }

    // MARK: - Ambient Playback

    func playAmbient(config: SessionSoundConfig, ignoreMute: Bool = false) {
        guard (!isMuted || ignoreMute), config.isPlayable else {
            shouldBePlayingAmbient = config.isPlayable
            currentAmbientConfig = config
            return
        }

        stopAmbientInternal()
        currentAmbientConfig = config
        shouldBePlayingAmbient = true

        guard let buffer = loadAmbientBuffer(for: config) else { return }
        currentAmbientBuffer = buffer

        // Reconnect with the buffer's exact format to prevent format mismatch crash
        ambientEngine.connect(ambientPlayerNode, to: varispeedNode, format: buffer.format)
        ambientEngine.connect(varispeedNode, to: ambientEngine.mainMixerNode, format: buffer.format)
        ambientPlayerNode.volume = config.volume
        ambientEngine.mainMixerNode.outputVolume = masterVolume
        varispeedNode.rate = 1.0

        do {
            try ambientEngine.start()
            ambientPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            ambientPlayerNode.play()
            DispatchQueue.main.async { self.isPlaying = true }
        } catch {
            print("SessionAudioService: Failed to start ambient engine: \(error)")
        }
    }

    /// Update ambient sound dynamically (e.g. when user changes settings mid-session)
    func updateAmbientIfPlaying(config: SessionSoundConfig) {
        guard shouldBePlayingAmbient || isPlaying else { return }

        if currentAmbientConfig?.sound != config.sound || currentAmbientConfig?.isPlayable != config.isPlayable {
            // Sound type changed — restart or stop
            if !config.isPlayable {
                stopAmbient()
            } else {
                playAmbient(config: config)
            }
        } else if currentAmbientConfig?.volume != config.volume {
            // Volume only — adjust directly without engine restart
            ambientPlayerNode.volume = config.volume
            currentAmbientConfig = config
        }
    }

    /// Set a fixed playback rate (used when accelerando is off but multiplier != 1.0)
    func setFixedPlaybackRate(_ rate: Float) {
        varispeedNode.rate = rate
    }

    /// Update playback rate for accelerando effect
    func updatePlaybackRate(progress: Double, accelerando: AccelerandoConfig) {
        guard accelerando.enabled else {
            // When not accelerating, use the fixed multiplier as constant speed
            let fixedRate = Float(accelerando.maxMultiplier)
            if varispeedNode.rate != fixedRate {
                varispeedNode.rate = fixedRate
            }
            return
        }
        // Accelerando ramps toward 1.0:
        //   speed > 1.0: starts at 1.0, ends at maxMultiplier
        //   speed < 1.0: starts at maxMultiplier, ends at 1.0
        let startRate = min(accelerando.maxMultiplier, 1.0)
        let endRate = max(accelerando.maxMultiplier, 1.0)
        let rate = Float(startRate + (endRate - startRate) * progress)
        varispeedNode.rate = rate
    }

    func stopAmbient() {
        stopAmbientInternal()
        shouldBePlayingAmbient = false
        currentAmbientConfig = nil
    }

    /// Stops playback but preserves shouldBePlayingAmbient + currentAmbientConfig so unmute can resume
    private func muteAmbient() {
        stopAmbientInternal()
    }

    /// Stops engine/player without clearing state (used internally before restarting)
    private func stopAmbientInternal() {
        ambientPlayerNode.stop()
        varispeedNode.rate = 1.0
        if ambientEngine.isRunning {
            ambientEngine.stop()
        }
        currentAmbientBuffer = nil
        DispatchQueue.main.async { self.isPlaying = false }
    }

    private func resumeAmbient() {
        guard let config = currentAmbientConfig, config.isPlayable else { return }
        playAmbient(config: config)
    }

    // MARK: - Transition Playback

    @discardableResult
    func playTransition(config: TransitionSoundConfig, ignoreMute: Bool = false) -> TimeInterval {
        guard (!isMuted || ignoreMute), config.isPlayable else { return 0 }

        guard let url = transitionSoundURL(for: config) else { return 0 }

        do {
            transitionPlayer?.stop()
            transitionPlayer = try AVAudioPlayer(contentsOf: url)
            transitionPlayer?.volume = config.volume * masterVolume
            transitionPlayer?.play()
            return transitionPlayer?.duration ?? 0
        } catch {
            print("SessionAudioService: Failed to play transition sound: \(error)")
            return 0
        }
    }

    func stopTransition() {
        transitionPlayer?.stop()
        transitionPlayer = nil
    }

    // MARK: - Preview Pause/Resume

    /// Pause session ambient for demo preview (saves state for later resume)
    func pauseForPreview() {
        if previewPausedConfig == nil {
            previewPausedConfig = currentAmbientConfig
            previewPausedShouldPlay = shouldBePlayingAmbient
        }
        stopAmbientInternal()
    }

    /// Resume session ambient after demo preview ends
    func resumeAfterPreview() {
        stopAmbientInternal()
        stopTransition()
        varispeedNode.rate = 1.0

        let config = previewPausedConfig
        let wasPlaying = previewPausedShouldPlay
        previewPausedConfig = nil
        previewPausedShouldPlay = false

        // Reset flags left over from preview playback
        shouldBePlayingAmbient = false
        currentAmbientConfig = nil

        guard let config = config, wasPlaying else { return }

        currentAmbientConfig = config
        shouldBePlayingAmbient = true
        if !isMuted {
            playAmbient(config: config)
        }
    }

    // MARK: - Sound file loading

    private func loadAmbientBuffer(for config: SessionSoundConfig) -> AVAudioPCMBuffer? {
        guard let url = ambientSoundURL(for: config) else { return nil }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            print("SessionAudioService: Failed to load ambient sound: \(error)")
            return nil
        }
    }

    private func ambientSoundURL(for config: SessionSoundConfig) -> URL? {
        // Custom sound by path
        if let customPath = config.customSoundPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Custom sound by name (from CustomSoundStore)
        if let entry = CustomSoundStore.shared.entry(named: config.sound) {
            let url = URL(fileURLWithPath: entry.filePath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Built-in sound
        guard let file = Self.ambientFiles[config.sound] else { return nil }
        return Bundle.main.url(forResource: file.name, withExtension: file.ext)
    }

    private func transitionSoundURL(for config: TransitionSoundConfig) -> URL? {
        if let customPath = config.customSoundPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Custom sound by name
        if let entry = CustomSoundStore.shared.entry(named: config.sound) {
            let url = URL(fileURLWithPath: entry.filePath)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        guard let file = Self.transitionFiles[config.sound] else { return nil }
        return Bundle.main.url(forResource: file.name, withExtension: file.ext)
    }

    // MARK: - Output Device Management

    func setOutputDevice(uid: String?) {
        let outputNode = ambientEngine.outputNode
        guard let audioUnit = outputNode.audioUnit else { return }

        let wasRunning = ambientEngine.isRunning
        if wasRunning {
            ambientPlayerNode.stop()
            ambientEngine.stop()
        }

        if let uid = uid, let deviceID = deviceID(forUID: uid) {
            var id = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        if wasRunning, shouldBePlayingAmbient {
            resumeAmbient()
        }
    }

    func refreshOutputDevices() {
        availableOutputDevices = enumerateOutputDevices()
    }

    private func enumerateOutputDevices() -> [AudioOutputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status2 = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status2 == noErr else { return [] }

        return deviceIDs.compactMap { id -> AudioOutputDevice? in
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            var hasOutput = (streamStatus == noErr && streamSize > 0)

            if !hasOutput {
                var outputAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyStreamConfiguration,
                    mScope: kAudioObjectPropertyScopeOutput,
                    mElement: kAudioObjectPropertyElementMain
                )
                var outputSize: UInt32 = 0
                if AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &outputSize) == noErr && outputSize > 0 {
                    let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
                    defer { bufferListPointer.deallocate() }
                    if AudioObjectGetPropertyData(id, &outputAddress, 0, nil, &outputSize, bufferListPointer) == noErr {
                        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
                        let outputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
                        hasOutput = outputChannels > 0
                    }
                }
            }

            guard hasOutput else { return nil }

            // Filter out virtual and aggregate devices (Teams, aggregate, etc.)
            let transportType: UInt32 = {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyTransportType,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var value: UInt32 = 0
                var size = UInt32(MemoryLayout<UInt32>.size)
                AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
                return value
            }()

            let excludedTransports: Set<UInt32> = [
                kAudioDeviceTransportTypeAggregate,
                kAudioDeviceTransportTypeVirtual
            ]
            if excludedTransports.contains(transportType) { return nil }

            let name: String = {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceNameCFString,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var value: CFString = "" as CFString
                var size = UInt32(MemoryLayout<CFString>.size)
                withUnsafeMutablePointer(to: &value) { ptr in
                    _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
                }
                return value as String
            }()

            let uid: String = {
                var address = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyDeviceUID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var value: CFString = "" as CFString
                var size = UInt32(MemoryLayout<CFString>.size)
                withUnsafeMutablePointer(to: &value) { ptr in
                    _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, ptr)
                }
                return value as String
            }()

            guard !name.isEmpty, !uid.isEmpty else { return nil }

            return AudioOutputDevice(id: id, uid: uid, name: name)
        }
    }

    private func deviceID(forUID uid: String) -> AudioDeviceID? {
        availableOutputDevices.first { $0.uid == uid }?.id
    }

    // MARK: - Device change listener

    private func observeDeviceChanges() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshOutputDevices()
            }
        }
        deviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    private func removeDeviceListener() {
        guard let block = deviceListenerBlock else { return }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Audio engine recovery

    private func observeEngineConfigChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: ambientEngine
        )
    }

    @objc private func handleEngineConfigChange(_ notification: Notification) {
        // Engine was stopped by system (device change, other app took audio, etc.)
        // Restart if we should be playing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.shouldBePlayingAmbient, !self.isMuted else { return }
            self.resumeAmbient()
        }
    }

    // MARK: - Custom Sound Import

    static func importCustomSound(from sourceURL: URL) -> String? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let soundsDir = appSupport.appendingPathComponent("SessionFlow/CustomSounds")

        do {
            try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
            let dest = soundsDir.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest.path
        } catch {
            print("SessionAudioService: Failed to import custom sound: \(error)")
            return nil
        }
    }
}
