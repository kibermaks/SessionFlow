import Foundation
import AVFoundation
import AppKit
import CoreAudio
import SwiftUI
import Combine

final class AudioRouteRecoveryCoordinator {
    enum SuspensionReason: Hashable {
        case systemSleep
        case screenSleep
        case inactiveSession
    }

    enum ResumeOutcome: Equatable {
        case ignored
        case waiting
        case scheduled
    }

    typealias Cancellation = () -> Void
    typealias Scheduler = (_ delay: TimeInterval, _ operation: @escaping () -> Void) -> Cancellation

    private let scheduler: Scheduler
    private var suspensionReasons: Set<SuspensionReason> = []
    private var longestResumeDelay: TimeInterval = 0
    private var generation = 0
    private var cancelPendingOperation: Cancellation?

    init(scheduler: @escaping Scheduler = { delay, operation in
        let workItem = DispatchWorkItem(block: operation)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return { workItem.cancel() }
    }) {
        self.scheduler = scheduler
    }

    func suspend(reason: SuspensionReason) {
        if suspensionReasons.isEmpty {
            longestResumeDelay = 0
        }
        suspensionReasons.insert(reason)
        invalidatePendingOperation()
    }

    @discardableResult
    func resume(
        reason: SuspensionReason,
        delay: TimeInterval,
        operation: @escaping () -> Void
    ) -> ResumeOutcome {
        guard suspensionReasons.remove(reason) != nil else { return .ignored }
        longestResumeDelay = max(longestResumeDelay, delay)
        guard suspensionReasons.isEmpty else { return .waiting }
        let recoveryDelay = longestResumeDelay
        longestResumeDelay = 0
        replacePendingOperation(delay: recoveryDelay, operation: operation)
        return .scheduled
    }

    func scheduleWhileActive(delay: TimeInterval, operation: @escaping () -> Void) {
        guard suspensionReasons.isEmpty else { return }
        replacePendingOperation(delay: delay, operation: operation)
    }

    func cancelPending() {
        invalidatePendingOperation()
    }

    private func replacePendingOperation(delay: TimeInterval, operation: @escaping () -> Void) {
        invalidatePendingOperation()
        let scheduledGeneration = generation
        cancelPendingOperation = scheduler(delay) { [weak self] in
            guard let self,
                  self.suspensionReasons.isEmpty,
                  self.generation == scheduledGeneration else { return }

            self.cancelPendingOperation = nil
            operation()
        }
    }

    private func invalidatePendingOperation() {
        generation &+= 1
        cancelPendingOperation?()
        cancelPendingOperation = nil
    }
}

class SessionAudioService: ObservableObject {

    // MARK: - Published state

    @Published private(set) var isMuted: Bool = false
    @Published var isPlaying: Bool = false
    @Published var availableOutputDevices: [AudioOutputDevice] = []

    @Published var muteEnabled: Bool = false {
        didSet { applyMuteState() }
    }
    @Published var micAwareEnabled: Bool = false {
        didSet { applyMuteState() }
    }

    let micMonitor = MicrophoneMonitor()
    private var micCancellable: AnyCancellable?
    private var sharedDeviceCancellable: AnyCancellable?

    // MARK: - Audio engine

    private var ambientEngine = AVAudioEngine()
    private var ambientPlayerNode = AVAudioPlayerNode()
    private var varispeedNode = AVAudioUnitVarispeed()
    private var transitionPlayer: AVAudioPlayer?
    private let audioControlQueue = DispatchQueue(
        label: "com.kibermaks.SessionFlow.audio-control",
        qos: .userInteractive
    )

    private var currentAmbientBuffer: AVAudioPCMBuffer?
    private var currentAmbientConfig: SessionSoundConfig?
    private var ambientBufferCache: [String: AVAudioPCMBuffer] = [:]
    private var shouldBePlayingAmbient = false
    private var ambientPlaybackGeneration = 0
    private var audioRouteIsRecovering = false
    private var audioRouteRecoveryNeedsEngineRebuild = false
    private let audioRouteRecoveryCoordinator = AudioRouteRecoveryCoordinator()
    private var userSessionIsInactive = false
    private var selectedOutputDeviceUID: String?
    private(set) var masterVolume: Float = 1.0
    private let ambientRestartDelays: [TimeInterval] = [0.5, 1.0, 2.0, 4.0]
    private var audioActivity: NSObjectProtocol?
    private var transitionPlaybackGeneration = 0
    private var transitionIsPlaying = false

    // Preview pause/resume state
    private var previewActive = false
    private var previewPausedConfig: SessionSoundConfig?
    private var previewPausedShouldPlay = false
    private var previewPausedRate: Float = 1.0
    private var ambientResumePlaybackRate: Float = 1.0
    private var lastAppliedPlaybackRate: Float = 1.0

    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    // MARK: - Output device model

    struct AudioOutputDevice: Identifiable, Equatable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    // MARK: - Sound file mapping

    private static let ambientFiles: [String: (name: String, ext: String)] = [
        "Campfire": ("Campfire", "mp3"),
        "Clock Ticking": ("Clock Ticking", "mp3"),
        "Clock Ticking Slow": ("Clock Ticking Slow", "mp3"),
        "Creek Atmosphere": ("Creek Atmosphere", "mp3"),
        "Kitchen Timer": ("Kitchen Timer", "mp3"),
        "Duskfall on a River": ("Duskfall on a River", "mp3"),
        "Light Rain": ("Light Rain Falling on Forest Floor", "mp3"),
        "Mountain Atmosphere": ("Mountain Atmosphere", "mp3"),
        "Ocean Waves": ("Ocean Waves", "mp3"),
        "Peaceful Wind": ("Peaceful Wind Atop a Hill", "mp3"),
        "Thunder in the Woods": ("Thunder in the Woods", "mp3"),
    ]

    private static let transitionFiles: [String: (name: String, ext: String)] = [
        "Kitchen Timer": ("Kitchen Timer", "mp3"),
        "Gong": ("Gong", "mp3"),
        "Hero": ("Hero", "mp3"),
        "Morse": ("Morse", "mp3"),
        "Glass": ("Glass", "mp3"),
        "Submarine": ("Submarine", "mp3"),
        "Purr": ("Purr", "mp3"),
    ]

    // MARK: - Init

    init() {
        setupAmbientEngine()
        refreshOutputDevices()
        observeDeviceChanges()
        observeEngineConfigChanges()
        observeWorkspaceAudioRecoveryNotifications()

        micCancellable = micMonitor.$isMicActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyMuteState() }
        sharedDeviceCancellable = micMonitor.$inputOutputSharedDevice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyMuteState() }
    }

    // MARK: - Mute Logic

    private func applyMuteState() {
        let micAwareActive = micAwareEnabled && micMonitor.isMicActive && !micMonitor.inputOutputSharedDevice
        let shouldMute = muteEnabled || micAwareActive
        guard shouldMute != isMuted else { return }
        isMuted = shouldMute
        if isMuted {
            muteAmbient()
            stopTransition()
        } else if shouldBePlayingAmbient {
            resumeAmbient()
        }
    }

    /// Toggle manual mute from panel buttons.
    func toggleMute() {
        muteEnabled.toggle()
    }

    deinit {
        audioRouteRecoveryCoordinator.cancelPending()
        if let audioActivity {
            ProcessInfo.processInfo.endActivity(audioActivity)
        }
        removeDeviceListener()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Ambient Engine Setup

    private func setupAmbientEngine() {
        ambientEngine.isAutoShutdownEnabled = false
        ambientEngine.attach(ambientPlayerNode)
        ambientEngine.attach(varispeedNode)
        ambientEngine.connect(ambientPlayerNode, to: varispeedNode, format: nil)
        ambientEngine.connect(varispeedNode, to: ambientEngine.mainMixerNode, format: nil)
    }

    // MARK: - Reset / Fix

    /// Full audio reset: stops everything, tears down engine, rebuilds from scratch
    func resetAudioEngine() {
        ambientPlaybackGeneration += 1

        // Stop all playback
        transitionPlaybackGeneration += 1
        transitionIsPlaying = false
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
        ambientBufferCache.removeAll()
        shouldBePlayingAmbient = false
        audioRouteIsRecovering = false
        audioRouteRecoveryNeedsEngineRebuild = false
        audioRouteRecoveryCoordinator.cancelPending()
        previewPausedConfig = nil
        previewPausedShouldPlay = false
        ambientResumePlaybackRate = 1.0
        applyPlaybackRate(1.0)
        updateAudioActivity()

        rebuildAmbientEngine()

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

    func playAmbient(config: SessionSoundConfig, ignoreMute: Bool = false, initialPlaybackRate: Float? = nil) {
        ambientPlaybackGeneration += 1
        playAmbient(
            config: config,
            ignoreMute: ignoreMute,
            initialPlaybackRate: initialPlaybackRate ?? 1.0,
            attempt: 0,
            generation: ambientPlaybackGeneration
        )
    }

    private func playAmbient(
        config: SessionSoundConfig,
        ignoreMute: Bool,
        initialPlaybackRate: Float,
        attempt: Int,
        generation: Int
    ) {
        guard generation == ambientPlaybackGeneration else { return }

        guard (!isMuted || ignoreMute), config.isPlayable else {
            shouldBePlayingAmbient = config.isPlayable
            currentAmbientConfig = config
            updateAudioActivity()
            return
        }

        currentAmbientConfig = config
        shouldBePlayingAmbient = true
        updateAudioActivity()

        guard !userSessionIsInactive else {
            stopAmbientInternal()
            updateAudioActivity()
            return
        }

        guard !audioRouteIsRecovering else {
            scheduleAmbientRestart(
                config: config,
                ignoreMute: ignoreMute,
                initialPlaybackRate: initialPlaybackRate,
                nextAttempt: attempt + 1,
                generation: generation,
                reason: "audio route is recovering"
            )
            return
        }

        stopAmbientInternal()

        guard let buffer = loadAmbientBuffer(for: config) else {
            handleAmbientStartFailure(
                config: config,
                ignoreMute: ignoreMute,
                initialPlaybackRate: initialPlaybackRate,
                attempt: attempt,
                generation: generation,
                reason: "unable to load ambient buffer"
            )
            return
        }
        guard buffer.frameLength > 0,
              buffer.format.sampleRate > 0,
              buffer.format.channelCount > 0 else {
            handleAmbientStartFailure(
                config: config,
                ignoreMute: ignoreMute,
                initialPlaybackRate: initialPlaybackRate,
                attempt: attempt,
                generation: generation,
                reason: "invalid ambient buffer format"
            )
            return
        }
        currentAmbientBuffer = buffer

        // Reconnect with the buffer's exact format to prevent format mismatch crash
        ambientEngine.connect(ambientPlayerNode, to: varispeedNode, format: buffer.format)
        ambientEngine.connect(varispeedNode, to: ambientEngine.mainMixerNode, format: buffer.format)
        ambientPlayerNode.volume = config.volume
        ambientEngine.mainMixerNode.outputVolume = masterVolume
        applyPlaybackRate(initialPlaybackRate)

        do {
            ambientEngine.prepare()
            try ambientEngine.start()
            guard ambientEngine.isRunning else {
                handleAmbientStartFailure(
                    config: config,
                    ignoreMute: ignoreMute,
                    initialPlaybackRate: initialPlaybackRate,
                    attempt: attempt,
                    generation: generation,
                    reason: "ambient engine did not remain running"
                )
                return
            }

            ambientPlayerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            if let exceptionReason = AVAudioExceptionCatcher.playPlayerNodeAndReturnExceptionReason(ambientPlayerNode) {
                handleAmbientStartFailure(
                    config: config,
                    ignoreMute: ignoreMute,
                    initialPlaybackRate: initialPlaybackRate,
                    attempt: attempt,
                    generation: generation,
                    reason: exceptionReason
                )
                return
            }

            updateAudioActivity()
            DispatchQueue.main.async { self.isPlaying = true }
        } catch {
            handleAmbientStartFailure(
                config: config,
                ignoreMute: ignoreMute,
                initialPlaybackRate: initialPlaybackRate,
                attempt: attempt,
                generation: generation,
                reason: "\(error)"
            )
        }
    }

    /// Update ambient sound dynamically (e.g. when user changes settings mid-session)
    func updateAmbientIfPlaying(config: SessionSoundConfig, initialPlaybackRate: Float? = nil) {
        guard shouldBePlayingAmbient || isPlaying else { return }

        if currentAmbientConfig?.sound != config.sound || currentAmbientConfig?.isPlayable != config.isPlayable {
            // Sound type changed — restart or stop
            if !config.isPlayable {
                stopAmbient()
            } else {
                playAmbient(config: config, initialPlaybackRate: initialPlaybackRate)
            }
        } else if currentAmbientConfig?.volume != config.volume {
            // Volume only — adjust directly without engine restart
            ambientPlayerNode.volume = config.volume
            currentAmbientConfig = config
            if let initialPlaybackRate {
                applyPlaybackRate(initialPlaybackRate)
            }
        } else if let initialPlaybackRate {
            applyPlaybackRate(initialPlaybackRate)
        }
    }

    /// Set a fixed playback rate (used when accelerando is off but multiplier != 1.0)
    func setFixedPlaybackRate(_ rate: Float) {
        applyPlaybackRate(rate)
    }

    static func playbackRate(progress: Double, accelerando: AccelerandoConfig) -> Float {
        guard accelerando.enabled else {
            return Float(accelerando.maxMultiplier)
        }
        // Accelerando ramps toward 1.0:
        //   speed > 1.0: starts at 1.0, ends at maxMultiplier
        //   speed < 1.0: starts at maxMultiplier, ends at 1.0
        let boundedProgress = min(1.0, max(0.0, progress))
        let startRate = min(accelerando.maxMultiplier, 1.0)
        let endRate = max(accelerando.maxMultiplier, 1.0)
        return Float(startRate + (endRate - startRate) * boundedProgress)
    }

    private static func clampedPlaybackRate(_ rate: Float) -> Float {
        min(max(rate, 0.25), 4.0)
    }

    private func applyPlaybackRate(_ rate: Float, rememberForResume: Bool = true) {
        let clampedRate = Self.clampedPlaybackRate(rate)
        if rememberForResume {
            ambientResumePlaybackRate = clampedRate
        }
        guard abs(lastAppliedPlaybackRate - clampedRate) >= 0.001 else { return }
        lastAppliedPlaybackRate = clampedRate

        if !ambientEngine.isRunning {
            varispeedNode.rate = clampedRate
            return
        }

        let node = varispeedNode
        audioControlQueue.async {
            guard abs(node.rate - clampedRate) >= 0.001 else { return }
            node.rate = clampedRate
        }
    }

    /// Update playback rate for accelerando effect
    func updatePlaybackRate(progress: Double, accelerando: AccelerandoConfig) {
        applyPlaybackRate(Self.playbackRate(progress: progress, accelerando: accelerando))
    }

    func stopAmbient() {
        ambientPlaybackGeneration += 1
        stopAmbientInternal()
        shouldBePlayingAmbient = false
        currentAmbientConfig = nil
        ambientResumePlaybackRate = 1.0
        updateAudioActivity()
    }

    /// Stops playback but preserves shouldBePlayingAmbient + currentAmbientConfig so unmute can resume
    private func muteAmbient() {
        ambientResumePlaybackRate = varispeedNode.rate
        stopAmbientInternal()
        updateAudioActivity()
    }

    /// Stops engine/player without clearing state (used internally before restarting)
    private func stopAmbientInternal() {
        ambientPlayerNode.stop()
        applyPlaybackRate(1.0, rememberForResume: false)
        if ambientEngine.isRunning {
            ambientEngine.stop()
        }
        currentAmbientBuffer = nil
        DispatchQueue.main.async { self.isPlaying = false }
    }

    private func resumeAmbient() {
        guard let config = currentAmbientConfig, config.isPlayable else { return }
        playAmbient(config: config, initialPlaybackRate: ambientResumePlaybackRate)
    }

    private func handleAmbientStartFailure(
        config: SessionSoundConfig,
        ignoreMute: Bool,
        initialPlaybackRate: Float,
        attempt: Int,
        generation: Int,
        reason: String
    ) {
        guard generation == ambientPlaybackGeneration else { return }

        print("SessionAudioService: Failed to start ambient playback: \(reason)")
        stopAmbientInternal()
        rebuildAmbientEngine()
        updateAudioActivity()
        scheduleAmbientRestart(
            config: config,
            ignoreMute: ignoreMute,
            initialPlaybackRate: initialPlaybackRate,
            nextAttempt: attempt + 1,
            generation: generation,
            reason: reason
        )
    }

    private func scheduleAmbientRestart(
        config: SessionSoundConfig,
        ignoreMute: Bool,
        initialPlaybackRate: Float,
        nextAttempt: Int,
        generation: Int,
        reason: String
    ) {
        guard generation == ambientPlaybackGeneration,
              shouldBePlayingAmbient,
              currentAmbientConfig == config else { return }

        guard nextAttempt <= ambientRestartDelays.count else {
            print("SessionAudioService: Ambient playback deferred after repeated failures: \(reason)")
            shouldBePlayingAmbient = false
            currentAmbientConfig = nil
            updateAudioActivity()
            DispatchQueue.main.async { self.isPlaying = false }
            return
        }

        let delay = ambientRestartDelays[nextAttempt - 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self,
                  generation == self.ambientPlaybackGeneration,
                  self.shouldBePlayingAmbient,
                  self.currentAmbientConfig == config else { return }

            self.playAmbient(
                config: config,
                ignoreMute: ignoreMute,
                initialPlaybackRate: initialPlaybackRate,
                attempt: nextAttempt,
                generation: generation
            )
        }
    }

    // MARK: - Transition Playback

    @discardableResult
    func playTransition(config: TransitionSoundConfig, ignoreMute: Bool = false) -> TimeInterval {
        guard (!isMuted || ignoreMute), config.isPlayable else { return 0 }

        guard let url = transitionSoundURL(for: config) else { return 0 }

        do {
            transitionPlaybackGeneration += 1
            let generation = transitionPlaybackGeneration
            transitionPlayer?.stop()
            transitionPlayer = try AVAudioPlayer(contentsOf: url)
            transitionPlayer?.volume = config.volume * masterVolume
            transitionPlayer?.prepareToPlay()

            guard transitionPlayer?.play() == true else {
                transitionIsPlaying = false
                updateAudioActivity()
                return 0
            }

            transitionIsPlaying = true
            updateAudioActivity()
            let duration = transitionPlayer?.duration ?? 0
            scheduleTransitionActivityRelease(duration: duration, generation: generation)
            return duration
        } catch {
            print("SessionAudioService: Failed to play transition sound: \(error)")
            transitionIsPlaying = false
            updateAudioActivity()
            return 0
        }
    }

    func stopTransition() {
        transitionPlaybackGeneration += 1
        transitionIsPlaying = false
        transitionPlayer?.stop()
        transitionPlayer = nil
        updateAudioActivity()
    }

    private func scheduleTransitionActivityRelease(duration: TimeInterval, generation: Int) {
        guard duration > 0 else {
            transitionIsPlaying = false
            updateAudioActivity()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.25) { [weak self] in
            guard let self = self,
                  generation == self.transitionPlaybackGeneration else { return }

            self.transitionIsPlaying = self.transitionPlayer?.isPlaying == true
            if !self.transitionIsPlaying {
                self.transitionPlayer = nil
            }
            self.updateAudioActivity()
        }
    }

    // MARK: - Audio performance assertion

    private func updateAudioActivity() {
        let intendsAmbientPlayback = shouldBePlayingAmbient
            && currentAmbientConfig?.isPlayable == true
            && !isMuted
            && !userSessionIsInactive
            && !audioRouteIsRecovering
        let shouldHoldActivity = intendsAmbientPlayback || ambientPlayerNode.isPlaying || transitionIsPlaying

        if shouldHoldActivity {
            guard audioActivity == nil else { return }
            audioActivity = ProcessInfo.processInfo.beginActivity(
                options: [
                    .userInitiated,
                    .latencyCritical,
                    .suddenTerminationDisabled,
                    .automaticTerminationDisabled
                ],
                reason: "SessionFlow audio playback"
            )
        } else if let activity = audioActivity {
            ProcessInfo.processInfo.endActivity(activity)
            audioActivity = nil
        }
    }

    // MARK: - Preview Pause/Resume

    /// Pause session ambient for demo preview (saves state for later resume)
    func pauseForPreview() {
        // Capture session state only when starting a fresh preview. The saved
        // config may legitimately be nil (no active session) — preview tracking
        // must not depend on it, or the preview can never be stopped.
        if !previewActive {
            previewActive = true
            previewPausedConfig = currentAmbientConfig
            previewPausedShouldPlay = shouldBePlayingAmbient
            previewPausedRate = varispeedNode.rate
        }
        stopAmbientInternal()
    }

    /// Resume session ambient after demo preview ends
    func resumeAfterPreview() {
        // No preview was started — don't touch the active session audio
        guard previewActive else { return }
        previewActive = false

        stopAmbientInternal()
        stopTransition()
        applyPlaybackRate(1.0)

        let config = previewPausedConfig
        let wasPlaying = previewPausedShouldPlay
        let savedRate = previewPausedRate
        previewPausedConfig = nil
        previewPausedShouldPlay = false
        previewPausedRate = 1.0

        // Reset flags left over from preview playback
        shouldBePlayingAmbient = false
        currentAmbientConfig = nil

        guard let config = config, wasPlaying else { return }

        currentAmbientConfig = config
        shouldBePlayingAmbient = true
        if !isMuted {
            playAmbient(config: config, initialPlaybackRate: savedRate)
        }
    }

    // MARK: - Sound file loading

    private func loadAmbientBuffer(for config: SessionSoundConfig) -> AVAudioPCMBuffer? {
        guard let url = ambientSoundURL(for: config) else { return nil }
        let cacheKey = ambientBufferCacheKey(for: url, soundName: config.sound)

        if let cached = ambientBufferCache[cacheKey] {
            return cached
        }

        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            try file.read(into: buffer)
            let preparedBuffer = prepareAmbientBuffer(buffer, soundName: config.sound)
            ambientBufferCache[cacheKey] = preparedBuffer
            return preparedBuffer
        } catch {
            print("SessionAudioService: Failed to load ambient sound: \(error)")
            return nil
        }
    }

    private func ambientBufferCacheKey(for url: URL, soundName: String) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(soundName)|\(url.path)|\(fileSize)|\(modified)"
    }

    private func prepareAmbientBuffer(_ buffer: AVAudioPCMBuffer, soundName: String) -> AVAudioPCMBuffer {
        if soundName == "Clock Ticking" || soundName == "Clock Ticking Slow" {
            return makeSeamlessClockBuffer(from: buffer, soundName: soundName) ?? buffer
        }

        return makeSeamlessAmbientLoopBuffer(from: buffer, soundName: soundName) ?? buffer
    }

    private func makeSeamlessClockBuffer(from source: AVAudioPCMBuffer, soundName: String) -> AVAudioPCMBuffer? {
        guard source.format.commonFormat == .pcmFormatFloat32,
              !source.format.isInterleaved,
              let sourceChannels = source.floatChannelData else {
            return nil
        }

        let frameLength = Int(source.frameLength)
        let channelCount = Int(source.format.channelCount)
        let sampleRate = source.format.sampleRate
        guard frameLength > 0, channelCount > 0, sampleRate > 0 else { return nil }

        let onsets = detectClockOnsets(in: source, soundName: soundName)
        guard onsets.count >= 2 else { return nil }

        var periodFrames = Int((Double(frameLength) / Double(onsets.count)).rounded())
        if soundName == "Clock Ticking Slow" {
            let oneSecondFrames = Int(sampleRate.rounded())
            if abs(periodFrames - oneSecondFrames) <= Int(sampleRate * 0.02) {
                periodFrames = oneSecondFrames
            }
        }

        let targetFrameCount = periodFrames * onsets.count
        guard targetFrameCount > 0,
              let target = AVAudioPCMBuffer(
                pcmFormat: source.format,
                frameCapacity: AVAudioFrameCount(targetFrameCount)
              ),
              let targetChannels = target.floatChannelData else {
            return nil
        }

        target.frameLength = AVAudioFrameCount(targetFrameCount)

        for channel in 0..<channelCount {
            for frame in 0..<targetFrameCount {
                targetChannels[channel][frame] = 0
            }
        }

        let preRollFrames = min(onsets[0], Int(sampleRate * 0.012), 512)
        let clipFrames = max(1, min(Int(Double(periodFrames) * 0.45), Int(sampleRate * 0.18)))

        for (index, onset) in onsets.enumerated() {
            let sourceStart = max(0, onset - preRollFrames)
            let targetStart = index * periodFrames
            let framesToCopy = min(preRollFrames + clipFrames, frameLength - sourceStart, targetFrameCount - targetStart)
            guard framesToCopy > 0 else { continue }

            let fadeFrames = min(256, framesToCopy / 4)
            let fadeStart = max(0, framesToCopy - fadeFrames)

            for channel in 0..<channelCount {
                let sourcePointer = sourceChannels[channel]
                let targetPointer = targetChannels[channel]

                for frame in 0..<framesToCopy {
                    var sample = sourcePointer[sourceStart + frame]
                    if fadeFrames > 0 && frame >= fadeStart {
                        sample *= Float(framesToCopy - frame) / Float(fadeFrames + 1)
                    }
                    targetPointer[targetStart + frame] = sample
                }
            }
        }

        return target
    }

    private func detectClockOnsets(in buffer: AVAudioPCMBuffer, soundName: String) -> [Int] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }

        var peak: Float = 0
        for frame in 0..<frameLength {
            var amplitude: Float = 0
            for channel in 0..<channelCount {
                amplitude = max(amplitude, abs(channelData[channel][frame]))
            }
            peak = max(peak, amplitude)
        }

        guard peak > 0 else { return [] }

        let sampleRate = buffer.format.sampleRate
        let minimumGapSeconds = soundName == "Clock Ticking Slow" ? 0.45 : 0.12
        let minimumGapFrames = Int(sampleRate * minimumGapSeconds)
        let threshold = max(peak * 0.08, 0.005)

        var onsets: [Int] = []
        var lastOnset = -minimumGapFrames
        var wasAboveThreshold = false

        for frame in 0..<frameLength {
            var amplitude: Float = 0
            for channel in 0..<channelCount {
                amplitude = max(amplitude, abs(channelData[channel][frame]))
            }

            let isAboveThreshold = amplitude >= threshold
            if isAboveThreshold && !wasAboveThreshold && frame - lastOnset >= minimumGapFrames {
                onsets.append(frame)
                lastOnset = frame
            }
            wasAboveThreshold = isAboveThreshold
        }

        return onsets
    }

    private func makeSeamlessAmbientLoopBuffer(from source: AVAudioPCMBuffer, soundName: String) -> AVAudioPCMBuffer? {
        guard source.format.commonFormat == .pcmFormatFloat32,
              !source.format.isInterleaved,
              let sourceChannels = source.floatChannelData else {
            return nil
        }

        let frameLength = Int(source.frameLength)
        let channelCount = Int(source.format.channelCount)
        let sampleRate = source.format.sampleRate
        guard frameLength > 0, channelCount > 0, sampleRate > 0 else { return nil }

        let duration = Double(frameLength) / sampleRate
        guard duration >= 2.0 else { return nil }

        let desiredCrossfadeSeconds = ambientLoopCrossfadeDuration(soundName: soundName, duration: duration)
        let desiredCrossfadeFrames = Int((desiredCrossfadeSeconds * sampleRate).rounded())
        let crossfadeFrames = min(max(desiredCrossfadeFrames, 256), frameLength / 4)
        guard crossfadeFrames >= 256, frameLength > crossfadeFrames * 2 else { return nil }

        let outputFrameCount = frameLength - crossfadeFrames
        let linearFrameCount = outputFrameCount - crossfadeFrames
        guard outputFrameCount > 0,
              linearFrameCount > 0,
              let output = AVAudioPCMBuffer(
                pcmFormat: source.format,
                frameCapacity: AVAudioFrameCount(outputFrameCount)
              ),
              let outputChannels = output.floatChannelData else {
            return nil
        }

        output.frameLength = AVAudioFrameCount(outputFrameCount)

        for channel in 0..<channelCount {
            let sourcePointer = sourceChannels[channel]
            let outputPointer = outputChannels[channel]

            for frame in 0..<linearFrameCount {
                outputPointer[frame] = sourcePointer[crossfadeFrames + frame]
            }

            for frame in 0..<crossfadeFrames {
                let t = Double(frame) / Double(max(1, crossfadeFrames - 1))
                let fadeOut = Float(cos(t * .pi / 2))
                let fadeIn = Float(sin(t * .pi / 2))
                let tailSample = sourcePointer[linearFrameCount + crossfadeFrames + frame]
                let headSample = sourcePointer[frame]
                outputPointer[linearFrameCount + frame] = tailSample * fadeOut + headSample * fadeIn
            }
        }

        return output
    }

    private func ambientLoopCrossfadeDuration(soundName: String, duration: TimeInterval) -> TimeInterval {
        switch soundName {
        case "Kitchen Timer":
            return min(1.0, max(0.4, duration * 0.10))
        default:
            if duration >= 45 {
                return 6.0
            } else if duration >= 20 {
                return 4.0
            } else {
                return min(2.0, max(0.5, duration * 0.12))
            }
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
        selectedOutputDeviceUID = uid
        applyOutputDevice(uid: uid, restartIfNeeded: true)
    }

    private func applyOutputDevice(uid: String?, restartIfNeeded: Bool) {
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

        if restartIfNeeded, wasRunning, shouldBePlayingAmbient {
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
                if AudioObjectGetPropertyDataSize(id, &outputAddress, 0, nil, &outputSize) == noErr
                    && outputSize >= UInt32(MemoryLayout<AudioBufferList>.size) {
                    let rawBufferList = UnsafeMutableRawPointer.allocate(
                        byteCount: Int(outputSize),
                        alignment: MemoryLayout<AudioBufferList>.alignment
                    )
                    defer { rawBufferList.deallocate() }
                    let bufferListPointer = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
                    if AudioObjectGetPropertyData(id, &outputAddress, 0, nil, &outputSize, rawBufferList) == noErr {
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

    private func rebuildAmbientEngine() {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )

        ambientPlayerNode.stop()
        if ambientEngine.isRunning {
            ambientEngine.stop()
        }
        ambientEngine.reset()

        if ambientPlayerNode.engine === ambientEngine {
            ambientEngine.detach(ambientPlayerNode)
        }
        if varispeedNode.engine === ambientEngine {
            ambientEngine.detach(varispeedNode)
        }

        ambientEngine = AVAudioEngine()
        ambientPlayerNode = AVAudioPlayerNode()
        varispeedNode = AVAudioUnitVarispeed()
        lastAppliedPlaybackRate = 1.0
        setupAmbientEngine()
        ambientEngine.mainMixerNode.outputVolume = masterVolume
        applyOutputDevice(uid: selectedOutputDeviceUID, restartIfNeeded: false)
        observeEngineConfigChanges()
    }

    private func observeEngineConfigChanges() {
        NotificationCenter.default.removeObserver(
            self,
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: ambientEngine
        )
    }

    @objc private func handleEngineConfigChange(_ notification: Notification) {
        guard let engine = notification.object as? AVAudioEngine else { return }

        // AVAudioEngine posts this notification on an internal audio queue. Rebuilding
        // or releasing the engine from that callback can deadlock its teardown.
        DispatchQueue.main.async { [weak self, weak engine] in
            guard let self,
                  let engine,
                  engine === self.ambientEngine else { return }
            self.beginEngineConfigurationRecovery()
        }
    }

    private func beginEngineConfigurationRecovery() {
        audioRouteRecoveryNeedsEngineRebuild = true
        if !audioRouteIsRecovering {
            audioRouteIsRecovering = true
            stopAmbientInternal()
            updateAudioActivity()
        }

        audioRouteRecoveryCoordinator.scheduleWhileActive(delay: 0.75) { [weak self] in
            self?.finishAudioRouteRecovery()
        }
    }

    private func observeWorkspaceAudioRecoveryNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleWorkspaceAudioWillSuspend),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWorkspaceAudioWillSuspend),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleUserSessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWorkspaceAudioDidResume),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleWorkspaceAudioDidResume),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleUserSessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleWorkspaceAudioWillSuspend(_ notification: Notification) {
        let reason: AudioRouteRecoveryCoordinator.SuspensionReason
        switch notification.name {
        case NSWorkspace.willSleepNotification:
            reason = .systemSleep
        case NSWorkspace.screensDidSleepNotification:
            reason = .screenSleep
        default:
            return
        }

        performAudioRouteMutationOnMain { [weak self] in
            self?.suspendAudioRoute(reason: reason)
        }
    }

    private func suspendAudioRoute(reason: AudioRouteRecoveryCoordinator.SuspensionReason) {
        audioRouteRecoveryCoordinator.suspend(reason: reason)
        audioRouteIsRecovering = true
        stopAmbientInternal()
        updateAudioActivity()
    }

    @objc private func handleWorkspaceAudioDidResume(_ notification: Notification) {
        let reason: AudioRouteRecoveryCoordinator.SuspensionReason
        switch notification.name {
        case NSWorkspace.didWakeNotification:
            reason = .systemSleep
        case NSWorkspace.screensDidWakeNotification:
            reason = .screenSleep
        default:
            return
        }

        performAudioRouteMutationOnMain { [weak self] in
            self?.resumeAudioRoute(reason: reason, delay: 2.0)
        }
    }

    @objc private func handleUserSessionDidResignActive(_ notification: Notification) {
        performAudioRouteMutationOnMain { [weak self] in
            guard let self else { return }
            self.userSessionIsInactive = true
            self.suspendAudioRoute(reason: .inactiveSession)
        }
    }

    @objc private func handleUserSessionDidBecomeActive(_ notification: Notification) {
        performAudioRouteMutationOnMain { [weak self] in
            guard let self else { return }
            self.userSessionIsInactive = false
            self.resumeAudioRoute(reason: .inactiveSession, delay: 1.0)
        }
    }

    private func resumeAudioRoute(
        reason: AudioRouteRecoveryCoordinator.SuspensionReason,
        delay: TimeInterval
    ) {
        let outcome = audioRouteRecoveryCoordinator.resume(reason: reason, delay: delay) { [weak self] in
            self?.finishAudioRouteRecovery()
        }

        switch outcome {
        case .ignored:
            return
        case .waiting:
            audioRouteIsRecovering = true
        case .scheduled:
            audioRouteIsRecovering = true
            refreshOutputDevices()
        }
    }

    private func performAudioRouteMutationOnMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }

    private func finishAudioRouteRecovery() {
        if audioRouteRecoveryNeedsEngineRebuild {
            audioRouteRecoveryNeedsEngineRebuild = false
            rebuildAmbientEngine()
        }
        audioRouteIsRecovering = false
        updateAudioActivity()

        guard shouldBePlayingAmbient,
              !isMuted,
              !userSessionIsInactive else { return }

        resumeAmbient()
        updateAudioActivity()
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
