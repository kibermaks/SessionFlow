import Foundation
import SwiftUI
import Combine

class SessionAwarenessService: ObservableObject {

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "SessionFlow.SessionAwarenessEnabled")
            if isEnabled {
                startTimer()
            } else {
                stopTimer()
                audioService?.stopAmbient()
                clearActiveState()
            }
        }
    }

    // Active session state
    @Published var isActive: Bool = false
    @Published var currentSessionTitle: String = ""
    @Published var currentSessionType: SessionType? = nil
    @Published var currentEventId: String? = nil
    @Published var currentEventNotes: String? = nil
    @Published var sessionStartTime: Date? = nil
    @Published var sessionEndTime: Date? = nil
    @Published var elapsed: TimeInterval = 0
    @Published var remaining: TimeInterval = 0
    @Published var progress: Double = 0

    // Non-tagged busy slot mode
    @Published var isBusySlotMode: Bool = false
    @Published var busySlotCalendarColor: Color? = nil
    @Published var busySlotCalendarName: String? = nil

    // Next session state
    @Published var nextSessionTitle: String? = nil
    @Published var nextSessionType: SessionType? = nil
    @Published var nextSessionStartTime: Date? = nil

    // Feedback
    @Published var sessionFeedbackPending: SessionFeedback? = nil

    // Current time (updated every second)
    @Published var currentTime: Date = Date()

    // Time display mode (clickable cycle)
    @Published var timeDisplayMode: TimeDisplayMode = .remaining

    // Mini-player collapsed state (NOT persisted)
    @Published var isCollapsed: Bool = false

    // Flash trigger for attention events (presence reminder, ending soon)
    enum FlashType { case presenceReminder, endingSoon }
    @Published var flashTrigger: FlashType? = nil

    // MARK: - Config

    @Published var config: SessionAwarenessConfig {
        didSet {
            config.save()
            isEnabled = config.enabled
            // Dynamic: update ambient sound if settings change mid-session
            if isActive, let audioService = audioService {
                let soundConfig: SessionSoundConfig
                if let type = currentSessionType {
                    soundConfig = config.soundConfig(for: type)
                } else if isBusySlotMode {
                    soundConfig = config.otherEventsSound
                } else {
                    return
                }
                audioService.updateAmbientIfPlaying(config: soundConfig)
            }
        }
    }

    // MARK: - Dependencies

    private weak var calendarService: CalendarService?
    private var audioService: SessionAudioService?
    private var timer: Timer?
    private var wasActive: Bool = false
    private var previousEventId: String? = nil
    private var previousSessionEndTime: Date? = nil
    private var feedbackDismissTimer: Timer?

    // Phase 3: Presence reminder tracking
    private var lastPresenceReminderTime: Date? = nil

    // Phase 3: Ending soon tracking
    private var hasPlayedEndingSoon: Bool = false

    // Tracking state preservation for calendar refresh gaps
    private var lastEndedEventId: String? = nil
    private var savedPresenceReminderTime: Date? = nil
    private var savedEndingSoonPlayed: Bool = false

    // MARK: - Init

    init() {
        let savedConfig = SessionAwarenessConfig.load()
        self.config = savedConfig
        self.isEnabled = savedConfig.enabled
        self.timeDisplayMode = savedConfig.timeDisplayMode
    }

    // MARK: - Lifecycle

    func start(calendarService: CalendarService, audioService: SessionAudioService) {
        self.calendarService = calendarService
        self.audioService = audioService

        // Apply saved master volume
        audioService.setMasterVolume(config.masterVolume)

        // Clean old feedback entries
        SessionFeedbackStore.shared.clearOldEntries(keepingDate: Date())

        if isEnabled {
            startTimer()
        }
    }

    func stop() {
        stopTimer()
    }

    // MARK: - Time display

    func cycleTimeDisplay() {
        switch timeDisplayMode {
        case .remaining: timeDisplayMode = .elapsed
        case .elapsed: timeDisplayMode = .remaining
        }
        config.timeDisplayMode = timeDisplayMode
    }

    // MARK: - Notes helper

    static func strippedNotes(_ notes: String?) -> String? {
        guard let notes = notes, !notes.isEmpty else { return nil }
        var result = notes
        for tag in ["#work", "#side", "#deep", "#plan", "#break"] {
            result = result.replacingOccurrences(of: tag, with: "", options: .caseInsensitive)
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        RunLoop.current.add(timer!, forMode: .common)
        tick() // immediate first tick
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Core tick

    private func tick() {
        let now = Date()
        currentTime = now

        guard let calendarService = calendarService else {
            clearActiveState()
            return
        }

        // 1. Try to find active tagged session
        if let slot = findActiveTaggedSession(in: calendarService.busySlots, at: now) {
            let sessionType = CalendarService.sessionType(fromNotes: slot.notes)
            activateSession(slot: slot, sessionType: sessionType, isBusySlot: false, at: now)
        }
        // 2. Try non-tagged event if enabled
        else if config.trackOtherEvents, let slot = findActiveBusySlot(in: calendarService.busySlots, at: now) {
            activateSession(slot: slot, sessionType: nil, isBusySlot: true, at: now)
        }
        // 3. No active session
        else {
            if wasActive, let prevId = previousEventId {
                // Save tracking state so we can restore if same event reappears (calendar refresh gap)
                lastEndedEventId = currentEventId
                savedPresenceReminderTime = lastPresenceReminderTime
                savedEndingSoonPlayed = hasPlayedEndingSoon

                // Only play end sound + feedback if the session ended naturally
                // (Now passed the end time), not if event was moved away
                let isNaturalEnd = previousSessionEndTime.map { now >= $0 } ?? false
                triggerSessionEnd(eventId: prevId, isNaturalEnd: isNaturalEnd)
            }
            clearActiveState()
        }

        // Phase 3: Presence reminder
        if isActive && config.presenceReminderEnabled {
            checkPresenceReminder(at: now)
        }

        // Phase 3: Ending soon
        if isActive && !hasPlayedEndingSoon && config.endingSoonSound.isPlayable {
            if remaining <= 120 && remaining > 0 {
                audioService?.playTransition(config: config.endingSoonSound)
                hasPlayedEndingSoon = true
                triggerFlash(.endingSoon)
            }
        }

        // Phase 3: Accelerando — update playback rate
        if isActive {
            let accelConfig: AccelerandoConfig
            if let type = currentSessionType {
                accelConfig = config.accelerandoConfig(for: type)
            } else if isBusySlotMode {
                accelConfig = config.otherEventsSoundAccelerando
            } else {
                accelConfig = .init()
            }
            audioService?.updatePlaybackRate(progress: progress, accelerando: accelConfig)
        }

        // Update next session
        updateNextSession(in: calendarService.busySlots, at: now)

        wasActive = isActive
        previousEventId = currentEventId
        previousSessionEndTime = sessionEndTime
    }

    // MARK: - Presence reminder

    private func checkPresenceReminder(at now: Date) {
        let intervalSeconds = TimeInterval(config.presenceReminderIntervalMinutes * 60)
        let referenceTime = lastPresenceReminderTime ?? sessionStartTime ?? now

        if now.timeIntervalSince(referenceTime) >= intervalSeconds {
            audioService?.playTransition(config: config.presenceReminderSound)
            lastPresenceReminderTime = now
            triggerFlash(.presenceReminder)
        }
    }

    // MARK: - Session detection

    private func findActiveTaggedSession(in slots: [BusyTimeSlot], at now: Date) -> BusyTimeSlot? {
        slots
            .filter { $0.startTime <= now && now < $0.endTime }
            .filter { CalendarService.sessionType(fromNotes: $0.notes) != nil }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private func findActiveBusySlot(in slots: [BusyTimeSlot], at now: Date) -> BusyTimeSlot? {
        slots
            .filter { $0.startTime <= now && now < $0.endTime }
            .filter { CalendarService.sessionType(fromNotes: $0.notes) == nil }
            .sorted { $0.startTime < $1.startTime }
            .first
    }

    private func updateNextSession(in slots: [BusyTimeSlot], at now: Date) {
        let upcoming = slots
            .filter { $0.startTime > now }
            .filter { CalendarService.sessionType(fromNotes: $0.notes) != nil }
            .sorted { $0.startTime < $1.startTime }

        if let next = upcoming.first {
            let type = CalendarService.sessionType(fromNotes: next.notes)
            if nextSessionTitle != next.title { nextSessionTitle = next.title }
            if nextSessionType != type { nextSessionType = type }
            if nextSessionStartTime != next.startTime { nextSessionStartTime = next.startTime }
        } else {
            if nextSessionTitle != nil { nextSessionTitle = nil }
            if nextSessionType != nil { nextSessionType = nil }
            if nextSessionStartTime != nil { nextSessionStartTime = nil }
        }
    }

    // MARK: - State management

    private func activateSession(slot: BusyTimeSlot, sessionType: SessionType?, isBusySlot: Bool, at now: Date) {
        let isNewSession = currentEventId != slot.id

        // Only update identity properties when session changes (avoids redundant @Published writes)
        if isNewSession {
            currentEventId = slot.id
            currentSessionTitle = slot.title
            currentSessionType = sessionType
            currentEventNotes = slot.notes
            sessionStartTime = slot.startTime
            sessionEndTime = slot.endTime
            isBusySlotMode = isBusySlot
            busySlotCalendarColor = isBusySlot ? slot.calendarColor : nil
            busySlotCalendarName = isBusySlot ? slot.calendarName : nil
        }

        // Time values change every tick — update directly
        let total = slot.endTime.timeIntervalSince(slot.startTime)
        elapsed = now.timeIntervalSince(slot.startTime)
        remaining = slot.endTime.timeIntervalSince(now)
        progress = total > 0 ? min(1.0, max(0.0, elapsed / total)) : 0

        let wasActiveBeforeThisTick = isActive
        if !isActive { isActive = true }

        // Dismiss any pending feedback
        if sessionFeedbackPending != nil { sessionFeedbackPending = nil }
        feedbackDismissTimer?.invalidate()

        // Audio: start sound + ambient on new session
        if isNewSession && !wasActiveBeforeThisTick {
            // Check if this is the same event re-appearing after a brief gap (calendar refresh)
            if slot.id == lastEndedEventId {
                // Restore tracking state — don't re-trigger presence/ending sounds
                lastPresenceReminderTime = savedPresenceReminderTime
                hasPlayedEndingSoon = savedEndingSoonPlayed
            } else {
                lastPresenceReminderTime = nil
                hasPlayedEndingSoon = false
            }
            lastEndedEventId = nil
            savedPresenceReminderTime = nil
            savedEndingSoonPlayed = false

            // If we're joining mid-event (elapsed > 10s), skip start transition — just play ambient
            let isJoiningMidEvent = elapsed > 10

            // When joining mid-event, suppress immediate presence/ending triggers
            // (only fire when DateTime Now naturally crosses the next interval boundary)
            if isJoiningMidEvent {
                if lastPresenceReminderTime == nil {
                    // Anchor to last interval boundary so next reminder fires at a clean multiple
                    let intervalSeconds = TimeInterval(config.presenceReminderIntervalMinutes * 60)
                    let completedIntervals = Int(elapsed / intervalSeconds)
                    if completedIntervals > 0 {
                        lastPresenceReminderTime = slot.startTime.addingTimeInterval(Double(completedIntervals) * intervalSeconds)
                    }
                }
                if remaining <= 120 {
                    hasPlayedEndingSoon = true
                }
            }

            playSessionStartAudio(sessionType: sessionType, skipTransition: isJoiningMidEvent)
        }
    }

    private func clearActiveState() {
        if isActive { isActive = false }
        if !currentSessionTitle.isEmpty { currentSessionTitle = "" }
        if currentSessionType != nil { currentSessionType = nil }
        if currentEventId != nil { currentEventId = nil }
        if currentEventNotes != nil { currentEventNotes = nil }
        if sessionStartTime != nil { sessionStartTime = nil }
        if sessionEndTime != nil { sessionEndTime = nil }
        if elapsed != 0 { elapsed = 0 }
        if remaining != 0 { remaining = 0 }
        if progress != 0 { progress = 0 }
        if isBusySlotMode { isBusySlotMode = false }
        if busySlotCalendarColor != nil { busySlotCalendarColor = nil }
        if busySlotCalendarName != nil { busySlotCalendarName = nil }
        lastPresenceReminderTime = nil
        hasPlayedEndingSoon = false
    }

    // MARK: - Session transitions

    private func triggerSessionEnd(eventId: String, isNaturalEnd: Bool) {
        audioService?.stopAmbient()

        // Only play end sound if session ended naturally (Now passed end time)
        if isNaturalEnd && config.endSound.isPlayable {
            audioService?.playTransition(config: config.endSound)
        }

        // Create feedback prompt from the session that just ended (only for natural ends)
        if isNaturalEnd,
           let calendarService = calendarService,
           let slot = calendarService.busySlots.first(where: { $0.id == eventId }),
           CalendarService.sessionType(fromNotes: slot.notes) != nil {
            sessionFeedbackPending = SessionFeedback(
                eventId: slot.id,
                sessionTitle: slot.title,
                sessionType: CalendarService.sessionType(fromNotes: slot.notes),
                startTime: slot.startTime,
                endTime: slot.endTime
            )

            // Auto-dismiss feedback after 15 seconds
            feedbackDismissTimer?.invalidate()
            feedbackDismissTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.sessionFeedbackPending = nil
                }
            }
        }
    }

    private func playSessionStartAudio(sessionType: SessionType?, skipTransition: Bool = false) {
        guard let audioService = audioService else { return }

        // Play start transition sound (skip if joining mid-event)
        let playTransition = !skipTransition && config.startSound.isPlayable
        if playTransition {
            audioService.playTransition(config: config.startSound)
        }

        // Determine ambient sound config
        let soundConfig: SessionSoundConfig
        if let type = sessionType {
            soundConfig = config.soundConfig(for: type)
        } else {
            soundConfig = config.otherEventsSound
        }

        // Determine accelerando config for initial speed
        let accelConfig: AccelerandoConfig
        if let type = sessionType {
            accelConfig = config.accelerandoConfig(for: type)
        } else {
            accelConfig = config.otherEventsSoundAccelerando
        }

        if soundConfig.isPlayable {
            let delay: TimeInterval = playTransition ? 3.0 : 0
            let currentProgress = self.progress
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                audioService.playAmbient(config: soundConfig)
                // Apply speed/accelerando immediately so the first sound is already modified
                audioService.updatePlaybackRate(progress: currentProgress, accelerando: accelConfig)
            }
        }
    }

    // MARK: - Audio state refresh (e.g. after settings demo playback)

    func refreshAudioState() {
        guard let audioService = audioService, isActive else { return }

        let soundConfig: SessionSoundConfig
        if let type = currentSessionType {
            soundConfig = config.soundConfig(for: type)
        } else if isBusySlotMode {
            soundConfig = config.otherEventsSound
        } else {
            return
        }

        if soundConfig.isPlayable && !audioService.isMuted {
            audioService.playAmbient(config: soundConfig)
            // Re-apply current accelerando/speed
            let accelConfig: AccelerandoConfig
            if let type = currentSessionType {
                accelConfig = config.accelerandoConfig(for: type)
            } else {
                accelConfig = config.otherEventsSoundAccelerando
            }
            audioService.updatePlaybackRate(progress: progress, accelerando: accelConfig)
        }
    }

    // MARK: - Feedback actions

    func submitFeedback(rating: SessionRating) {
        guard let feedback = sessionFeedbackPending else { return }
        let entry = SessionFeedbackEntry(from: feedback, rating: rating)
        SessionFeedbackStore.shared.saveEntry(entry)
        feedbackDismissTimer?.invalidate()
        sessionFeedbackPending = nil
    }

    func dismissFeedback() {
        feedbackDismissTimer?.invalidate()
        sessionFeedbackPending = nil
    }

    // MARK: - Debug simulation

    func simulatePresenceReminder() {
        audioService?.playTransition(config: config.presenceReminderSound)
        triggerFlash(.presenceReminder)
    }

    func simulateEndingSoon() {
        audioService?.playTransition(config: config.endingSoonSound)
        triggerFlash(.endingSoon)
    }

    // MARK: - Flash

    private func triggerFlash(_ type: FlashType) {
        flashTrigger = type
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.flashTrigger = nil
        }
    }
}
