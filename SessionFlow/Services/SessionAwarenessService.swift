import Foundation
import SwiftUI
import Combine

class SessionAwarenessService: ObservableObject {

    // MARK: - Published state

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "SessionFlow.SessionAwarenessEnabled")
            if isEnabled || hasActiveShortcuts {
                startTimer()
            } else {
                stopTimer()
            }
            if !isEnabled {
                audioService?.stopAmbient()
                clearActiveState()
            }
        }
    }

    /// Whether any shortcut trigger is enabled (timer must keep running for detection)
    var hasActiveShortcuts: Bool {
        config.shortcuts.approaching.isEnabled || config.shortcuts.started.isEnabled || config.shortcuts.ended.isEnabled
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
    @Published var nextSessionEndTime: Date? = nil
    @Published var nextSessionIsBusySlot: Bool = false
    @Published var nextSessionCalendarColor: Color? = nil

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
            // Keep timer running if shortcuts need it
            if hasActiveShortcuts && timer == nil {
                startTimer()
            }
            // Sync mute settings to audio service
            if let audioService = audioService {
                if audioService.muteEnabled != config.muteEnabled {
                    audioService.muteEnabled = config.muteEnabled
                }
                if audioService.micAwareEnabled != config.micAwareEnabled {
                    audioService.micAwareEnabled = config.micAwareEnabled
                }
            }
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
    let shortcutService = ShortcutService()
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

    // Cached slots — refreshed every 30s or immediately when calendar data changes
    private var cachedNowSlots: [BusyTimeSlot] = []
    private var lastSlotsFetch: Date = .distantPast
    private let slotsFetchInterval: TimeInterval = 30
    private var calendarCancellable: AnyCancellable?

    /// Returns the demo-override time if enabled, otherwise real Date()
    private var effectiveNow: Date {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "devNowLineOverrideEnabled") else { return Date() }
        let hour = defaults.integer(forKey: "devNowLineOverrideHour")
        let minute = defaults.integer(forKey: "devNowLineOverrideMinute")
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        return cal.date(byAdding: .hour, value: hour, to: dayStart)
            .flatMap { cal.date(byAdding: .minute, value: minute, to: $0) } ?? Date()
    }

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

        // Apply saved master volume and mute settings
        audioService.setMasterVolume(config.masterVolume)
        audioService.muteEnabled = config.muteEnabled
        audioService.micAwareEnabled = config.micAwareEnabled

        // Invalidate slot cache whenever calendar data changes (drag, move, create, delete)
        calendarCancellable = calendarService.$lastRefresh
            .dropFirst()
            .sink { [weak self] _ in self?.lastSlotsFetch = .distantPast }

        if isEnabled || hasActiveShortcuts {
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
        for tag in ["#work", "#side", "#deep", "#plan", "#break"] + SessionRating.allTags {
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
        // Avoid .common — causes SwiftUI Menu submenus in contextMenu to flicker
        tick() // immediate first tick
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Core tick

    private func tick() {
        let now = effectiveNow
        currentTime = now

        guard let calendarService = calendarService else {
            clearActiveState()
            return
        }

        // Refresh cached slots every 30s (not every tick)
        if now.timeIntervalSince(lastSlotsFetch) >= slotsFetchInterval {
            cachedNowSlots = calendarService.fetchNowSlots(referenceTime: now)
            lastSlotsFetch = now
        }
        let todaySlots = cachedNowSlots

        // 1. Try to find active tagged session
        if let slot = findActiveTaggedSession(in: todaySlots, at: now) {
            let sessionType = CalendarService.sessionType(fromNotes: slot.notes)
            activateSession(slot: slot, sessionType: sessionType, isBusySlot: false, at: now)
        }
        // 2. Try non-tagged event if enabled
        else if config.trackOtherEvents, let slot = findActiveBusySlot(in: todaySlots, at: now) {
            activateSession(slot: slot, sessionType: nil, isBusySlot: true, at: now)
        }
        // 3. No active session
        else {
            if wasActive, let prevId = previousEventId, let start = sessionStartTime, let end = sessionEndTime {
                // Save tracking state so we can restore if same event reappears (calendar refresh gap)
                lastEndedEventId = currentEventId
                savedPresenceReminderTime = lastPresenceReminderTime
                savedEndingSoonPlayed = hasPlayedEndingSoon

                // Only play end sound + feedback if the session ended naturally
                // (Now passed the end time), not if event was moved away
                let isNaturalEnd = now >= end
                triggerSessionEnd(
                    eventId: prevId,
                    sessionTitle: currentSessionTitle,
                    sessionType: currentSessionType,
                    startTime: start,
                    endTime: end,
                    isNaturalEnd: isNaturalEnd
                )
            }
            clearActiveState()
        }

        // Audio/visual features require awareness enabled
        if isEnabled {
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
        }

        // Update next session
        updateNextSession(in: todaySlots, at: now)

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
            .filter { slot in
                // Include tagged sessions always; include untagged events when trackOtherEvents is on
                CalendarService.sessionType(fromNotes: slot.notes) != nil || config.trackOtherEvents
            }
            .sorted { $0.startTime < $1.startTime }

        if let next = upcoming.first {
            let type = CalendarService.sessionType(fromNotes: next.notes)
            let isBusy = type == nil
            if nextSessionTitle != next.title { nextSessionTitle = next.title }
            if nextSessionType != type { nextSessionType = type }
            if nextSessionStartTime != next.startTime { nextSessionStartTime = next.startTime }
            if nextSessionEndTime != next.endTime { nextSessionEndTime = next.endTime }
            if nextSessionIsBusySlot != isBusy { nextSessionIsBusySlot = isBusy }
            let calColor = isBusy ? next.calendarColor : nil
            if nextSessionCalendarColor != calColor { nextSessionCalendarColor = calColor }

            // Schedule "Approaching" shortcut
            shortcutService.scheduleApproaching(
                sessionId: next.id,
                session: .init(title: next.title, type: type, isBusySlot: isBusy,
                               startTime: next.startTime, endTime: next.endTime),
                config: config.shortcuts
            )
        } else {
            if nextSessionTitle != nil { nextSessionTitle = nil }
            if nextSessionType != nil { nextSessionType = nil }
            if nextSessionStartTime != nil { nextSessionStartTime = nil }
            if nextSessionEndTime != nil { nextSessionEndTime = nil }
            if nextSessionIsBusySlot != false { nextSessionIsBusySlot = false }
            if nextSessionCalendarColor != nil { nextSessionCalendarColor = nil }
            shortcutService.cancelApproaching()
        }
    }

    // MARK: - State management

    private func activateSession(slot: BusyTimeSlot, sessionType: SessionType?, isBusySlot: Bool, at now: Date) {
        let isNewSession = currentEventId != slot.id

        // Update identity properties on new session, and keep title/notes/type in sync for live edits
        if isNewSession {
            currentEventId = slot.id
            isBusySlotMode = isBusySlot
            busySlotCalendarColor = isBusySlot ? slot.calendarColor : nil
            busySlotCalendarName = isBusySlot ? slot.calendarName : nil
        }
        if currentSessionTitle != slot.title { currentSessionTitle = slot.title }
        if currentSessionType != sessionType { currentSessionType = sessionType }
        if currentEventNotes != slot.notes { currentEventNotes = slot.notes }

        // Start/end times may change if the event is dragged — always keep in sync
        if sessionStartTime != slot.startTime { sessionStartTime = slot.startTime }
        if sessionEndTime != slot.endTime { sessionEndTime = slot.endTime }

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

            if isEnabled {
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

            // Fire "Session Started" shortcut (skip if joining mid-event)
            if !isJoiningMidEvent {
                shortcutService.fire(
                    trigger: .started,
                    session: .init(title: slot.title, type: sessionType, isBusySlot: isBusySlot,
                                   startTime: slot.startTime, endTime: slot.endTime),
                    config: config.shortcuts
                )
            }
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

    private func triggerSessionEnd(
        eventId: String,
        sessionTitle: String,
        sessionType: SessionType?,
        startTime: Date,
        endTime: Date,
        isNaturalEnd: Bool
    ) {
        // Shortcuts fire independently of awareness
        if isNaturalEnd {
            shortcutService.fire(
                trigger: .ended,
                session: .init(title: sessionTitle, type: sessionType, isBusySlot: sessionType == nil,
                               startTime: startTime, endTime: endTime),
                config: config.shortcuts
            )
        }

        // Audio and feedback require awareness enabled
        guard isEnabled else { return }

        audioService?.stopAmbient()

        if isNaturalEnd && config.endSound.isPlayable {
            audioService?.playTransition(config: config.endSound)
        }

        if isNaturalEnd,
           config.productivityEnabled,
           sessionType != nil || config.trackOtherEvents {
            sessionFeedbackPending = SessionFeedback(
                eventId: eventId,
                sessionTitle: sessionTitle,
                sessionType: sessionType,
                startTime: startTime,
                endTime: endTime
            )

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
        calendarService?.setFeedbackTag(eventId: feedback.eventId, rating: rating)
        if let cs = calendarService { Task { await cs.fetchEvents(for: Date()) } }
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
