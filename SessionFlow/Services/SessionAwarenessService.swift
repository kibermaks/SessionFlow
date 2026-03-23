import Foundation
import SwiftUI
import Combine

/// Holds the properties that change every tick (1 Hz) so that observers
/// of SessionAwarenessService (e.g. settings panels) are not re-rendered
/// every second unless they explicitly observe this object.
class SessionTimeState: ObservableObject {
    @Published var currentTime: Date = Date()
    @Published var elapsed: TimeInterval = 0
    @Published var remaining: TimeInterval = 0
    @Published var progress: Double = 0
    @Published var restElapsed: TimeInterval = 0
    @Published var restRemaining: TimeInterval = 0
    @Published var restProgress: Double = 0
}

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
                endRestState()
            }
        }
    }

    /// Whether any shortcut trigger is enabled (timer must keep running for detection)
    var hasActiveShortcuts: Bool {
        config.shortcuts.approaching.isEnabled || config.shortcuts.started.isEnabled || config.shortcuts.ended.isEnabled ||
        config.shortcuts.restStarted.isEnabled || config.shortcuts.restEnded.isEnabled || config.shortcuts.restEndingSoon.isEnabled
    }

    // Active session state
    @Published var isActive: Bool = false
    @Published var currentSessionTitle: String = ""
    @Published var currentSessionType: SessionType? = nil
    @Published var currentEventId: String? = nil
    @Published var currentEventNotes: String? = nil
    @Published var sessionStartTime: Date? = nil
    @Published var sessionEndTime: Date? = nil
    /// Ticking state (1 Hz). Isolated so settings views don't re-render every second.
    let timeState = SessionTimeState()
    var elapsed: TimeInterval {
        get { timeState.elapsed }
        set { timeState.elapsed = newValue }
    }
    var remaining: TimeInterval {
        get { timeState.remaining }
        set { timeState.remaining = newValue }
    }
    var progress: Double {
        get { timeState.progress }
        set { timeState.progress = newValue }
    }

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

    // Current time (updated every second) — proxied through timeState
    var currentTime: Date {
        get { timeState.currentTime }
        set { timeState.currentTime = newValue }
    }

    // Time display mode (clickable cycle)
    @Published var timeDisplayMode: TimeDisplayMode = .remaining

    // Mini-player collapsed state (NOT persisted)
    @Published var isCollapsed: Bool = false

    // Flash trigger for attention events (presence reminder, ending soon, start)
    enum FlashType { case presenceReminder, endingSoon, sessionStarted }
    @Published var flashTrigger: FlashType? = nil

    // Skip sounds until next session (mute current session only)
    @Published var isSessionMuted: Bool = false
    private var sessionMutedEventId: String? = nil

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

    // Rest tracking state
    @Published var isResting: Bool = false
    @Published var restStartTime: Date? = nil
    @Published var restEndTime: Date? = nil
    var restElapsed: TimeInterval {
        get { timeState.restElapsed }
        set { timeState.restElapsed = newValue }
    }
    var restRemaining: TimeInterval {
        get { timeState.restRemaining }
        set { timeState.restRemaining = newValue }
    }
    var restProgress: Double {
        get { timeState.restProgress }
        set { timeState.restProgress = newValue }
    }
    @Published var restAfterSessionType: SessionType? = nil

    // Rest durations (synced from scheduling engine, in minutes)
    var restDurations: [SessionType: Int] = [:]

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

    // Rest tracking internals
    private var wasResting: Bool = false
    private var hasPlayedRestEndingSoon: Bool = false

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
            endRestState()
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
            // If transitioning from rest to active, fire restEnded first
            if isResting { endRestState() }
            activateSession(slot: slot, sessionType: sessionType, isBusySlot: false, at: now)
        }
        // 2. Try non-tagged event if enabled
        else if config.trackOtherEvents, let slot = findActiveBusySlot(in: todaySlots, at: now) {
            if isResting { endRestState() }
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
            // Phase 3: Presence reminder (suppressed when session-muted)
            if isActive && config.presenceReminderEnabled && !isSessionMuted {
                checkPresenceReminder(at: now)
            }

            // Phase 3: Ending soon (suppressed when session-muted)
            if isActive && !hasPlayedEndingSoon && config.endingSoonSound.isPlayable && !isSessionMuted {
                if remaining <= 120 && remaining > 0 {
                    audioService?.playTransition(config: config.endingSoonSound)
                    hasPlayedEndingSoon = true
                    triggerFlash(.endingSoon)
                }
            }

            // Phase 3: Accelerando — update playback rate (skip when session-muted)
            if isActive && !isSessionMuted {
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

        // Rest tracking (always active when awareness is enabled)
        if isEnabled && !isActive {
            checkRestState(in: todaySlots, at: now)
        } else if isResting {
            endRestState()
        }

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

    // MARK: - Rest tracking

    private func checkRestState(in slots: [BusyTimeSlot], at now: Date) {
        // Find the most recently ended tagged session
        let pastTagged = slots
            .filter { $0.endTime <= now && CalendarService.sessionType(fromNotes: $0.notes) != nil }
            .sorted { $0.endTime > $1.endTime }

        guard let prevSlot = pastTagged.first,
              let prevType = CalendarService.sessionType(fromNotes: prevSlot.notes) else {
            if isResting { endRestState() }
            return
        }

        // Get expected rest duration for this session type
        guard let restMinutes = restDurations[prevType], restMinutes > 0 else {
            if isResting { endRestState() }
            return
        }

        let restStart = prevSlot.endTime
        let restEnd = restStart.addingTimeInterval(TimeInterval(restMinutes * 60))

        // Check we're in the rest window
        guard now >= restStart && now < restEnd else {
            if isResting { endRestState() }
            return
        }

        // Make sure no session started in this gap
        let sessionInGap = slots.contains { slot in
            slot.startTime >= restStart && slot.startTime < restEnd &&
            (CalendarService.sessionType(fromNotes: slot.notes) != nil ||
             (config.trackOtherEvents && CalendarService.sessionType(fromNotes: slot.notes) == nil))
        }
        if sessionInGap {
            if isResting { endRestState() }
            return
        }

        // We're in a rest period
        let isNewRest = !isResting
        let total = restEnd.timeIntervalSince(restStart)
        restElapsed = now.timeIntervalSince(restStart)
        restRemaining = restEnd.timeIntervalSince(now)
        restProgress = total > 0 ? min(1.0, max(0.0, restElapsed / total)) : 0
        restStartTime = restStart
        restEndTime = restEnd
        restAfterSessionType = prevType

        if isNewRest {
            isResting = true
            hasPlayedRestEndingSoon = false

            // Play rest ambient
            if !isSessionMuted {
                audioService?.playAmbient(config: config.restSound)
            }

            // Fire rest started shortcut
            shortcutService.fire(
                trigger: .restStarted,
                session: .init(title: "Rest", type: prevType, isBusySlot: false,
                               startTime: restStart, endTime: restEnd),
                config: config.shortcuts
            )
        }

        // Rest ending soon
        let leadMinutes = config.shortcuts.restEndingSoon.leadTimeMinutes ?? 2
        let leadSeconds = TimeInterval(leadMinutes * 60)
        if !hasPlayedRestEndingSoon && restRemaining <= leadSeconds && restRemaining > 0 {
            hasPlayedRestEndingSoon = true
            shortcutService.fire(
                trigger: .restEndingSoon,
                session: .init(title: "Rest", type: prevType, isBusySlot: false,
                               startTime: restStart, endTime: restEnd),
                config: config.shortcuts
            )
        }

        // Accelerando for rest
        if !isSessionMuted {
            audioService?.updatePlaybackRate(progress: restProgress, accelerando: config.restSoundAccelerando)
        }
    }

    private func endRestState() {
        let wasInRest = isResting
        isResting = false

        if wasInRest {
            audioService?.stopAmbient()

            // Fire rest ended shortcut
            if let start = restStartTime, let end = restEndTime {
                shortcutService.fire(
                    trigger: .restEnded,
                    session: .init(title: "Rest", type: restAfterSessionType, isBusySlot: false,
                                   startTime: start, endTime: end),
                    config: config.shortcuts
                )
            }
        }

        restStartTime = nil
        restEndTime = nil
        restElapsed = 0
        restRemaining = 0
        restProgress = 0
        restAfterSessionType = nil
        hasPlayedRestEndingSoon = false
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

            // Auto-clear session mute when a different session starts
            if isSessionMuted && sessionMutedEventId != slot.id {
                isSessionMuted = false
                sessionMutedEventId = nil
            }
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
                } else {
                    triggerFlash(.sessionStarted)
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
        if isSessionMuted { isSessionMuted = false; sessionMutedEventId = nil }
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
        // Shortcuts fire on ALL session end transitions (natural end or drag-away)
        shortcutService.fire(
            trigger: .ended,
            session: .init(title: sessionTitle, type: sessionType, isBusySlot: sessionType == nil,
                           startTime: startTime, endTime: endTime),
            config: config.shortcuts
        )

        // If we were in rest when session ended (shouldn't normally happen, but safety)
        if isResting { endRestState() }

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

    // MARK: - App termination flush

    /// Fire pending end/restEnded shortcuts synchronously before the app terminates.
    func flushOnTermination() {
        if isActive, let start = sessionStartTime, let end = sessionEndTime {
            shortcutService.fireAndForget(
                trigger: .ended,
                session: .init(title: currentSessionTitle, type: currentSessionType,
                               isBusySlot: isBusySlotMode, startTime: start, endTime: end),
                config: config.shortcuts
            )
        } else if isResting, let start = restStartTime, let end = restEndTime {
            shortcutService.fireAndForget(
                trigger: .restEnded,
                session: .init(title: "Rest", type: restAfterSessionType, isBusySlot: false,
                               startTime: start, endTime: end),
                config: config.shortcuts
            )
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

    // MARK: - Session mute (skip until next)

    func toggleSessionMute() {
        if isSessionMuted {
            isSessionMuted = false
            sessionMutedEventId = nil
            // Resume ambient if there's an active session or rest
            if isActive {
                playSessionStartAudio(sessionType: currentSessionType, skipTransition: true)
            } else if isResting {
                audioService?.playAmbient(config: config.restSound)
            }
        } else {
            isSessionMuted = true
            sessionMutedEventId = currentEventId
            audioService?.stopAmbient()
        }
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
