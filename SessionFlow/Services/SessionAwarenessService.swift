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
            if requiresTrackingTimer {
                startTimer()
            } else {
                stopTimer()
            }
            if !isEnabled {
                audioService?.stopAmbient()
                // Only tear down detection state when no feature still needs session tracking.
                if !requiresTrackingTimer {
                    clearActiveState()
                    endRestState()
                }
            }
        }
    }

    /// Whether the global shortcuts switch is on AND any trigger is enabled.
    /// When true, the tick timer must keep running so shortcut detection works
    /// even if Session Awareness itself is disabled.
    var hasActiveShortcuts: Bool {
        guard config.shortcuts.globalEnabled else { return false }
        return config.shortcuts.approaching.isEnabled || config.shortcuts.started.isEnabled || config.shortcuts.endingSoon.isEnabled || config.shortcuts.ended.isEnabled ||
        config.shortcuts.restStarted.isEnabled || config.shortcuts.restEnded.isEnabled || config.shortcuts.restEndingSoon.isEnabled
    }

    private var requiresTrackingTimer: Bool {
        isEnabled || hasActiveShortcuts || config.harshModeEnabled
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

    // Harsh Mode
    @Published var harshModePrompt: HarshModePrompt? = nil
    private static let debugHarshModeEventPrefix = "sessionflow-debug-commit-mode-"
    static let harshDelayMinuteOptions = [1, 2, 3, 4, 5, 10, 15, 20]

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
    private var sessionAudioStartGeneration = 0

    // MARK: - Config

    @Published var config: SessionAwarenessConfig {
        didSet {
            config.save()
            isEnabled = config.enabled
            // Keep timer running if any tracking-backed feature needs it.
            if requiresTrackingTimer && timer == nil {
                startTimer()
            } else if !requiresTrackingTimer && timer != nil {
                stopTimer()
                clearActiveState()
                endRestState()
            }
            // If shortcuts global toggle just flipped off, drop any pending approaching timer
            if oldValue.shortcuts.globalEnabled && !config.shortcuts.globalEnabled {
                shortcutService.cancelApproaching()
            }
            if !config.harshModeEnabled && harshModePrompt != nil {
                harshModePrompt = nil
            }
            // Sync mute settings to audio service — only when the config
            // values actually changed in this mutation. Otherwise an unrelated
            // settings tweak would clobber a mute toggled from the mini player
            // or bottom panel (those paths write audioService directly).
            if let audioService = audioService {
                if oldValue.muteEnabled != config.muteEnabled {
                    audioService.muteEnabled = config.muteEnabled
                }
                if oldValue.micAwareEnabled != config.micAwareEnabled {
                    audioService.micAwareEnabled = config.micAwareEnabled
                }
            }
            // Dynamic: update ambient sound if settings change mid-session or mid-rest
            if let audioService = audioService {
                if isActive {
                    let soundConfig: SessionSoundConfig
                    if let type = currentSessionType {
                        soundConfig = config.soundConfig(for: type)
                    } else if isBusySlotMode {
                        soundConfig = config.otherEventsSound
                    } else {
                        return
                    }
                    audioService.updateAmbientIfPlaying(config: soundConfig)
                } else if isResting {
                    audioService.updateAmbientIfPlaying(config: config.restSound)
                }
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
    private var hasFiredEndingSoonShortcut: Bool = false

    // Rest tracking internals
    private var wasResting: Bool = false
    private var hasPlayedRestEndingSoon: Bool = false

    // Tracking state preservation for calendar refresh gaps
    private var lastEndedEventId: String? = nil
    private var savedPresenceReminderTime: Date? = nil
    private var savedEndingSoonPlayed: Bool = false
    private var savedEndingSoonShortcutFired: Bool = false
    private var savedSessionMuted: Bool = false
    private var harshStartBypassedEventIds: Set<String> = []
    private var harshEndBypassedEventIds: Set<String> = []
    private var harshGoalCapturedEventIds: Set<String> = []
    private var harshReviewCapturedEventIds: Set<String> = []
    private var harshPromptSnoozeUntilByID: [String: Date] = [:]
    private var harshLifecycleStartedEventIds: Set<String> = []
    private var harshLifecycleEndedEventIds: Set<String> = []
    private var harshEndPendingMutedByID: [String: Bool] = [:]

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
        audioService.setOutputDevice(uid: config.outputDeviceUID)
        audioService.muteEnabled = config.muteEnabled
        audioService.micAwareEnabled = config.micAwareEnabled

        // Invalidate slot cache whenever calendar data changes (drag, move, create, delete)
        calendarCancellable = calendarService.$lastRefresh
            .dropFirst()
            .sink { [weak self] _ in self?.lastSlotsFetch = .distantPast }

        if requiresTrackingTimer {
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
        var result = HarshModeSessionNotes.removingManagedBlocks(from: notes)
        for tag in FlowFlexibilityNotes.sessionFlowTags + FlowFlexibilityNotes.allTags + SessionRating.allTags + SessionAlignment.allTags {
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
                savedEndingSoonShortcutFired = hasFiredEndingSoonShortcut
                savedSessionMuted = isSessionMuted

                // Only play end sound + feedback if the session ended naturally
                // (Now passed the end time), not if event was moved away
                let isNaturalEnd = now >= end
                triggerSessionEnd(
                    eventId: prevId,
                    sessionTitle: currentSessionTitle,
                    sessionType: currentSessionType,
                    startTime: start,
                    endTime: end,
                    notes: currentEventNotes,
                    isNaturalEnd: isNaturalEnd
                )
            }
            clearActiveState()
        }

        let isHarshStartBlocked = isCurrentHarshStartBlocked(now: now)
        let isHarshEndPromptPending = harshModePrompt?.phase == .end

        // Audio/visual features require awareness enabled
        if isEnabled {
            // Phase 3: Presence reminder (suppressed when session-muted)
            if isActive && !isHarshStartBlocked && config.presenceReminderEnabled && !isSessionMuted {
                checkPresenceReminder(at: now)
            }

            // Phase 3: Ending soon (suppressed when session-muted)
            if isActive && !isHarshStartBlocked && !hasPlayedEndingSoon && config.endingSoonSound.isPlayable && !isSessionMuted {
                if remaining <= 120 && remaining > 0 {
                    audioService?.playTransition(config: config.endingSoonSound)
                    hasPlayedEndingSoon = true
                    triggerFlash(.endingSoon)
                }
            }

            // Phase 3: Accelerando — update playback rate (skip when session-muted)
            if isActive && !isHarshStartBlocked && !isSessionMuted {
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

        // Ending soon shortcut — fires regardless of awareness state
        if isActive && !isHarshStartBlocked && !hasFiredEndingSoonShortcut {
            let leadMinutes = config.shortcuts.endingSoon.leadTimeMinutes ?? 2
            let leadSeconds = TimeInterval(leadMinutes * 60)
            if remaining <= leadSeconds && remaining > 0 {
                hasFiredEndingSoonShortcut = true
                shortcutService.fire(
                    trigger: .endingSoon,
                    session: .init(title: currentSessionTitle, type: currentSessionType, isBusySlot: isBusySlotMode,
                                   startTime: sessionStartTime ?? now, endTime: sessionEndTime ?? now),
                    config: config.shortcuts
                )
            }
        }

        // Update next session
        updateNextSession(in: todaySlots, at: now)

        // Rest tracking — runs whenever awareness OR shortcut detection is active
        if (isEnabled || hasActiveShortcuts) && !isActive && !isHarshEndPromptPending {
            checkRestState(in: todaySlots, at: now)
        } else if isResting && !isHarshEndPromptPending {
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
        if restStartTime != restStart { restStartTime = restStart }
        if restEndTime != restEnd { restEndTime = restEnd }
        if restAfterSessionType != prevType { restAfterSessionType = prevType }

        if isNewRest {
            isResting = true
            hasPlayedRestEndingSoon = false

            // Play rest ambient (awareness only)
            if isEnabled && !isSessionMuted {
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

        // Accelerando for rest (awareness only)
        if isEnabled && !isSessionMuted {
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
        let shouldWaitForHarshStart = shouldGateHarshStart(
            eventId: slot.id,
            sessionType: sessionType,
            isBusySlot: isBusySlot,
            notes: slot.notes,
            now: now
        )

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
                hasFiredEndingSoonShortcut = savedEndingSoonShortcutFired
                if savedSessionMuted {
                    isSessionMuted = true
                    sessionMutedEventId = slot.id
                }
            } else {
                lastPresenceReminderTime = nil
                hasPlayedEndingSoon = false
                hasFiredEndingSoonShortcut = false
            }
            lastEndedEventId = nil
            savedPresenceReminderTime = nil
            savedEndingSoonPlayed = false
            savedEndingSoonShortcutFired = false
            savedSessionMuted = false

            // If we're joining mid-event (elapsed > 10s), skip start transition — just play ambient
            let isJoiningMidEvent = elapsed > 10

            // When joining mid-event, suppress the endingSoon shortcut so it doesn't
            // fire late for sessions we never tracked from the start. This needs to
            // run regardless of awareness state — otherwise toggling off awareness
            // would re-fire endingSoon late once shortcut detection re-attaches.
            if isJoiningMidEvent && !shouldWaitForHarshStart {
                let endingSoonLeadMinutes = config.shortcuts.endingSoon.leadTimeMinutes ?? 2
                if remaining <= TimeInterval(endingSoonLeadMinutes * 60) {
                    hasFiredEndingSoonShortcut = true
                }
            }

            if isEnabled && !shouldWaitForHarshStart {
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

                if !isSessionMuted {
                    playSessionStartAudio(sessionType: sessionType, skipTransition: isJoiningMidEvent)
                }
            }

            // Fire "Session Started" shortcut (skip if joining mid-event)
            if !isJoiningMidEvent && !shouldWaitForHarshStart {
                shortcutService.fire(
                    trigger: .started,
                    session: .init(title: slot.title, type: sessionType, isBusySlot: isBusySlot,
                                   startTime: slot.startTime, endTime: slot.endTime),
                    config: config.shortcuts
                )
            }
        }

        presentHarshModeStartPromptIfNeeded(slot: slot, sessionType: sessionType, isBusySlot: isBusySlot)
    }

    private func clearActiveState() {
        cancelPendingSessionAudioStart()
        if let prompt = harshModePrompt, prompt.phase == .start, prompt.eventId == currentEventId {
            harshModePrompt = nil
        }
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
        hasFiredEndingSoonShortcut = false
    }

    // MARK: - Harsh Mode

    private func isHarshModeEligible(sessionType: SessionType?, isBusySlot: Bool) -> Bool {
        guard config.harshModeEnabled, !isBusySlot, let sessionType else {
            return false
        }
        return config.harshModeSessionTypes.matches(sessionType)
    }

    private func isHarshStartAccepted(eventId: String, notes: String?) -> Bool {
        !HarshModeSessionNotes.goals(from: notes).isEmpty || harshGoalCapturedEventIds.contains(eventId)
    }

    private func shouldGateHarshStart(
        eventId: String,
        sessionType: SessionType?,
        isBusySlot: Bool,
        notes: String?,
        now: Date
    ) -> Bool {
        guard isHarshModeEligible(sessionType: sessionType, isBusySlot: isBusySlot) else { return false }
        guard config.harshModeRequireStartGoals else { return false }
        guard !isHarshStartAccepted(eventId: eventId, notes: notes) else { return false }
        return !harshStartBypassedEventIds.contains(eventId)
    }

    private func isCurrentHarshStartBlocked(now: Date) -> Bool {
        guard let eventId = currentEventId else { return false }
        return shouldGateHarshStart(
            eventId: eventId,
            sessionType: currentSessionType,
            isBusySlot: isBusySlotMode,
            notes: currentEventNotes,
            now: now
        )
    }

    private func shouldGateHarshEnd(
        eventId: String,
        sessionType: SessionType?,
        notes: String?,
        isNaturalEnd: Bool,
        now: Date
    ) -> Bool {
        guard isNaturalEnd else { return false }
        guard isHarshModeEligible(sessionType: sessionType, isBusySlot: false) else { return false }
        guard config.harshModeRequireEndRating || config.harshModeRequireReviewNote else { return false }
        if config.harshModeRequireStartGoals {
            guard isHarshStartAccepted(eventId: eventId, notes: notes) else { return false }
        }
        guard !harshReviewCapturedEventIds.contains(eventId),
              !harshEndBypassedEventIds.contains(eventId),
              !harshLifecycleEndedEventIds.contains(eventId) else { return false }
        return !isHarshPromptSnoozed(phase: .end, eventId: eventId, now: now)
    }

    private func shouldSuppressHarshEndWithoutStart(
        eventId: String,
        sessionType: SessionType?,
        notes: String?,
        isNaturalEnd: Bool
    ) -> Bool {
        guard isNaturalEnd else { return false }
        guard isHarshModeEligible(sessionType: sessionType, isBusySlot: false) else { return false }
        guard config.harshModeRequireStartGoals else { return false }
        return !isHarshStartAccepted(eventId: eventId, notes: notes)
    }

    private func presentHarshModeStartPromptIfNeeded(slot: BusyTimeSlot, sessionType: SessionType?, isBusySlot: Bool) {
        guard shouldGateHarshStart(
            eventId: slot.id,
            sessionType: sessionType,
            isBusySlot: isBusySlot,
            notes: slot.notes,
            now: effectiveNow
        ) else { return }
        guard !isHarshPromptSnoozed(phase: .start, eventId: slot.id, now: effectiveNow) else { return }
        guard !harshGoalCapturedEventIds.contains(slot.id),
              !harshStartBypassedEventIds.contains(slot.id) else { return }
        if harshModePrompt?.phase == .start && harshModePrompt?.eventId == slot.id {
            return
        }

        let nextSlot = nextBlockingSlot(after: slot.endTime, excluding: slot.id, in: cachedNowSlots)

        harshModePrompt = HarshModePrompt(
            phase: .start,
            eventId: slot.id,
            sessionTitle: slot.title,
            sessionType: sessionType,
            startTime: slot.startTime,
            endTime: slot.endTime,
            notes: slot.notes,
            nextTaskTitle: nextSlot?.title,
            nextTaskStartTime: nextSlot?.startTime
        )
    }

    private func presentHarshModeEndPromptIfNeeded(
        eventId: String,
        sessionTitle: String,
        sessionType: SessionType?,
        startTime: Date,
        endTime: Date,
        notes: String?
    ) {
        guard shouldGateHarshEnd(
            eventId: eventId,
            sessionType: sessionType,
            notes: notes,
            isNaturalEnd: true,
            now: effectiveNow
        ) else { return }
        guard !harshReviewCapturedEventIds.contains(eventId),
              !harshEndBypassedEventIds.contains(eventId) else { return }
        if harshModePrompt?.phase == .end && harshModePrompt?.eventId == eventId {
            return
        }
        let nextSlot = nextBlockingSlot(after: endTime, excluding: eventId, in: cachedNowSlots)

        harshModePrompt = HarshModePrompt(
            phase: .end,
            eventId: eventId,
            sessionTitle: sessionTitle,
            sessionType: sessionType,
            startTime: startTime,
            endTime: endTime,
            notes: notes,
            nextTaskTitle: nextSlot?.title,
            nextTaskStartTime: nextSlot?.startTime
        )
    }

    func debugPresentHarshModeStartPrompt() {
        harshModePrompt = debugHarshModePrompt(phase: .start)
    }

    func debugPresentHarshModeEndPrompt() {
        harshModePrompt = debugHarshModePrompt(phase: .end)
    }

    func debugDismissHarshModePrompt() {
        harshModePrompt = nil
    }

    private func debugHarshModePrompt(phase: HarshModePromptPhase) -> HarshModePrompt {
        let now = currentTime
        let fallbackStart = phase == .start
            ? now
            : Calendar.current.date(byAdding: .minute, value: -40, to: now) ?? now
        let start = sessionStartTime ?? fallbackStart
        let fallbackEnd = phase == .start
            ? Calendar.current.date(byAdding: .minute, value: 40, to: start) ?? now
            : now
        var end = sessionEndTime ?? fallbackEnd
        if end <= start {
            end = Calendar.current.date(byAdding: .minute, value: 40, to: start) ?? start
        }

        return HarshModePrompt(
            phase: phase,
            eventId: currentEventId ?? "\(Self.debugHarshModeEventPrefix)\(UUID().uuidString)",
            sessionTitle: currentSessionTitle.isEmpty ? "Commit Mode Test Session" : currentSessionTitle,
            sessionType: currentSessionType ?? .work,
            startTime: start,
            endTime: end,
            notes: currentEventNotes ?? "Manual developer test prompt.",
            nextTaskTitle: nil,
            nextTaskStartTime: nil
        )
    }

    private static func isDebugHarshModeEvent(_ eventId: String) -> Bool {
        eventId.hasPrefix(debugHarshModeEventPrefix)
    }

    func availableHarshDelayMinutes(for prompt: HarshModePrompt) -> [Int] {
        if Self.isDebugHarshModeEvent(prompt.eventId) {
            return Self.harshDelayMinuteOptions
        }
        return Self.harshDelayMinuteOptions.filter { delayedTiming(for: prompt, minutes: $0) != nil }
    }

    func submitHarshDelay(minutes: Int) -> Bool {
        guard let prompt = harshModePrompt else { return false }

        if Self.isDebugHarshModeEvent(prompt.eventId) {
            harshModePrompt = nil
            return true
        }

        guard let timing = delayedTiming(for: prompt, minutes: minutes) else { return false }
        guard calendarService?.updateEventTime(eventId: prompt.eventId, newStart: timing.start, newEnd: timing.end) == true else {
            return false
        }

        // Re-enter tracking immediately; do not mark goal/review captured so the gate returns later.
        harshPromptSnoozeUntilByID[prompt.id] = timing.snoozeUntil
        sessionStartTime = timing.start
        sessionEndTime = timing.end
        remaining = max(0, timing.end.timeIntervalSince(effectiveNow))
        progress = max(0, min(1, effectiveNow.timeIntervalSince(timing.start) / max(1, timing.end.timeIntervalSince(timing.start))))
        lastSlotsFetch = .distantPast
        calendarService?.refreshCurrentEvents()
        harshModePrompt = nil
        tick()
        return true
    }

    private func delayedTiming(for prompt: HarshModePrompt, minutes: Int) -> (start: Date, end: Date, snoozeUntil: Date)? {
        let now = effectiveNow
        var slots = cachedNowSlots
        if (slots.isEmpty || lastSlotsFetch == .distantPast), let calendarService {
            slots = calendarService.fetchNowSlots(referenceTime: now)
        }

        let nextStart = nextBlockingSlot(after: prompt.endTime, excluding: prompt.eventId, in: slots)?.startTime
            ?? prompt.nextTaskStartTime
        return Self.harshDelayTiming(
            phase: prompt.phase,
            startTime: prompt.startTime,
            endTime: prompt.endTime,
            now: now,
            minutes: minutes,
            nextTaskStart: nextStart
        )
    }

    static func harshDelayTiming(
        phase: HarshModePromptPhase,
        startTime: Date,
        endTime: Date,
        now: Date,
        minutes: Int,
        nextTaskStart: Date?
    ) -> (start: Date, end: Date, snoozeUntil: Date)? {
        guard minutes > 0 else { return nil }

        let delay = TimeInterval(minutes * 60)
        let snoozeUntil = now.addingTimeInterval(delay)
        let requestedStart: Date
        let requestedEnd: Date

        switch phase {
        case .start:
            requestedStart = startTime.addingTimeInterval(delay)
            requestedEnd = endTime.addingTimeInterval(delay)
        case .end:
            requestedStart = startTime
            requestedEnd = max(now, endTime).addingTimeInterval(delay)
        }

        if let nextTaskStart, requestedEnd > nextTaskStart { return nil }
        guard requestedEnd > now else { return nil }
        guard phase == .start || requestedEnd > endTime else { return nil }
        return (requestedStart, requestedEnd, snoozeUntil)
    }

    private func nextBlockingSlot(after date: Date, excluding eventId: String, in slots: [BusyTimeSlot]) -> BusyTimeSlot? {
        slots
            .filter { $0.id != eventId && $0.startTime >= date }
            .sorted {
                if $0.startTime == $1.startTime { return $0.endTime < $1.endTime }
                return $0.startTime < $1.startTime
            }
            .first
    }

    private func isHarshPromptSnoozed(phase: HarshModePromptPhase, eventId: String, now: Date) -> Bool {
        let promptID = "\(eventId)-\(phase.rawValue)"
        guard let snoozeUntil = harshPromptSnoozeUntilByID[promptID] else { return false }
        if snoozeUntil > now {
            return true
        }
        harshPromptSnoozeUntilByID[promptID] = nil
        return false
    }

    // MARK: - Session transitions

    private func cancelPendingSessionAudioStart() {
        sessionAudioStartGeneration += 1
    }

    private func triggerSessionEnd(
        eventId: String,
        sessionTitle: String,
        sessionType: SessionType?,
        startTime: Date,
        endTime: Date,
        notes: String?,
        isNaturalEnd: Bool
    ) {
        if shouldSuppressHarshEndWithoutStart(
            eventId: eventId,
            sessionType: sessionType,
            notes: notes,
            isNaturalEnd: isNaturalEnd
        ) {
            cancelPendingSessionAudioStart()
            if isEnabled {
                audioService?.stopAmbient()
            }
            return
        }

        if shouldGateHarshEnd(
            eventId: eventId,
            sessionType: sessionType,
            notes: notes,
            isNaturalEnd: isNaturalEnd,
            now: effectiveNow
        ) {
            harshEndPendingMutedByID["\(eventId)-\(HarshModePromptPhase.end.rawValue)"] = isSessionMuted
            cancelPendingSessionAudioStart()
            presentHarshModeEndPromptIfNeeded(
                eventId: eventId,
                sessionTitle: sessionTitle,
                sessionType: sessionType,
                startTime: startTime,
                endTime: endTime,
                notes: notes
            )
            return
        }

        fireSessionEndLifecycle(
            eventId: eventId,
            sessionTitle: sessionTitle,
            sessionType: sessionType,
            startTime: startTime,
            endTime: endTime,
            isNaturalEnd: isNaturalEnd,
            wasSessionMuted: isSessionMuted
        )
    }

    private func fireSessionEndLifecycle(
        eventId: String,
        sessionTitle: String,
        sessionType: SessionType?,
        startTime: Date,
        endTime: Date,
        isNaturalEnd: Bool,
        wasSessionMuted: Bool
    ) {
        // Shortcuts fire on ALL session end transitions (natural end or drag-away)
        shortcutService.fire(
            trigger: .ended,
            session: .init(title: sessionTitle, type: sessionType, isBusySlot: sessionType == nil,
                           startTime: startTime, endTime: endTime),
            config: config.shortcuts
        )

        cancelPendingSessionAudioStart()

        // If we were in rest when session ended (shouldn't normally happen, but safety)
        if isResting { endRestState() }

        // Audio and feedback require awareness enabled
        guard isEnabled else { return }

        audioService?.stopAmbient()
        if wasSessionMuted {
            audioService?.stopTransition()
        }

        if isNaturalEnd && !wasSessionMuted && config.endSound.isPlayable {
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
            feedbackDismissTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.sessionFeedbackPending = nil
                }
            }
        }
    }

    private func fireHarshStartLifecycle(prompt: HarshModePrompt, title: String) {
        guard currentEventId == prompt.eventId, isActive else { return }
        guard !harshLifecycleStartedEventIds.contains(prompt.eventId) else { return }
        harshLifecycleStartedEventIds.insert(prompt.eventId)

        let now = effectiveNow
        lastPresenceReminderTime = now
        hasPlayedEndingSoon = false
        hasFiredEndingSoonShortcut = false

        if isEnabled {
            triggerFlash(.sessionStarted)
            if !isSessionMuted {
                playSessionStartAudio(sessionType: prompt.sessionType, skipTransition: false)
            }
        }

        shortcutService.fire(
            trigger: .started,
            session: .init(
                title: title,
                type: prompt.sessionType,
                isBusySlot: false,
                startTime: prompt.startTime,
                endTime: prompt.endTime
            ),
            config: config.shortcuts
        )
    }

    private func fireHarshEndLifecycle(prompt: HarshModePrompt) {
        guard !harshLifecycleEndedEventIds.contains(prompt.eventId) else { return }
        harshLifecycleEndedEventIds.insert(prompt.eventId)

        let promptID = prompt.id
        let wasSessionMuted = harshEndPendingMutedByID[promptID] ?? isSessionMuted
        harshEndPendingMutedByID[promptID] = nil

        fireSessionEndLifecycle(
            eventId: prompt.eventId,
            sessionTitle: prompt.sessionTitle,
            sessionType: prompt.sessionType,
            startTime: prompt.startTime,
            endTime: prompt.endTime,
            isNaturalEnd: true,
            wasSessionMuted: wasSessionMuted
        )
    }

    private func playSessionStartAudio(sessionType: SessionType?, skipTransition: Bool = false) {
        guard let audioService = audioService, !isSessionMuted else { return }
        sessionAudioStartGeneration += 1
        let generation = sessionAudioStartGeneration
        let targetEventId = currentEventId

        // Play start transition sound (skip if joining mid-event)
        let playTransition = !skipTransition && config.startSound.isPlayable
        var transitionDuration: TimeInterval = 0
        if playTransition {
            transitionDuration = audioService.playTransition(config: config.startSound)
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
            let delay: TimeInterval = transitionDuration > 0 ? min(transitionDuration, 3.0) : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak audioService] in
                guard let self,
                      let audioService,
                      generation == self.sessionAudioStartGeneration,
                      self.isEnabled,
                      self.isActive,
                      !self.isSessionMuted,
                      self.currentEventId == targetEventId else { return }

                audioService.playAmbient(config: soundConfig)
                // Apply speed/accelerando immediately so the first sound is already modified
                audioService.updatePlaybackRate(progress: self.progress, accelerando: accelConfig)
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
        guard let audioService = audioService, isActive || isResting else { return }

        let soundConfig: SessionSoundConfig
        let accelConfig: AccelerandoConfig
        let currentProgress: Double
        if isResting {
            soundConfig = config.restSound
            accelConfig = config.restSoundAccelerando
            currentProgress = restProgress
        } else if let type = currentSessionType {
            soundConfig = config.soundConfig(for: type)
            accelConfig = config.accelerandoConfig(for: type)
            currentProgress = progress
        } else if isBusySlotMode {
            soundConfig = config.otherEventsSound
            accelConfig = config.otherEventsSoundAccelerando
            currentProgress = progress
        } else {
            return
        }

        if soundConfig.isPlayable && !audioService.isMuted && !isSessionMuted {
            audioService.playAmbient(config: soundConfig)
            audioService.updatePlaybackRate(progress: currentProgress, accelerando: accelConfig)
        }
    }

    // MARK: - Feedback actions

    func submitHarshGoals(title: String, goals: [String]) -> Bool {
        guard let prompt = harshModePrompt, prompt.phase == .start else { return false }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedGoals = goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleanedTitle.isEmpty else { return false }
        guard cleanedGoals.count >= max(1, config.harshModeMinimumGoals) else { return false }
        if Self.isDebugHarshModeEvent(prompt.eventId) {
            currentSessionTitle = cleanedTitle
            harshGoalCapturedEventIds.insert(prompt.eventId)
            harshPromptSnoozeUntilByID[prompt.id] = nil
            harshModePrompt = nil
            return true
        }

        let sourceNotes = currentEventId == prompt.eventId ? currentEventNotes : prompt.notes
        let updatedNotes = HarshModeSessionNotes.applyingGoals(cleanedGoals, to: sourceNotes)
        guard calendarService?.updateEvent(eventId: prompt.eventId, title: cleanedTitle, notes: updatedNotes, url: nil) == true else {
            return false
        }

        if let sessionType = prompt.sessionType {
            SessionNameHistory.shared.addName(cleanedTitle, for: sessionType)
            TaskLineHistory.shared.addLines(cleanedGoals, for: sessionType)
        }
        if currentEventId == prompt.eventId {
            currentSessionTitle = cleanedTitle
            currentEventNotes = updatedNotes
        }
        harshGoalCapturedEventIds.insert(prompt.eventId)
        harshPromptSnoozeUntilByID[prompt.id] = nil
        fireHarshStartLifecycle(prompt: prompt, title: cleanedTitle)
        harshModePrompt = nil
        calendarService?.refreshCurrentEvents()
        return true
    }

    func submitHarshReview(rating: SessionRating?, alignment: SessionAlignment?, reflection: String, goals: [String]) -> Bool {
        guard let prompt = harshModePrompt, prompt.phase == .end else { return false }
        let cleanedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedGoals = goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !config.harshModeRequireEndRating || rating != nil else { return false }
        guard !config.harshModeRequireEndRating || alignment != nil else { return false }
        guard !config.harshModeRequireReviewNote || !cleanedReflection.isEmpty else { return false }
        if Self.isDebugHarshModeEvent(prompt.eventId) {
            harshReviewCapturedEventIds.insert(prompt.eventId)
            harshPromptSnoozeUntilByID[prompt.id] = nil
            sessionFeedbackPending = nil
            feedbackDismissTimer?.invalidate()
            harshModePrompt = nil
            return true
        }

        let notesWithGoals = HarshModeSessionNotes.applyingGoals(cleanedGoals, to: prompt.notes)
        let updatedNotes = HarshModeSessionNotes.applyingReview(rating: rating, alignment: alignment, reflection: cleanedReflection, to: notesWithGoals)
        guard calendarService?.updateEvent(eventId: prompt.eventId, title: nil, notes: updatedNotes, url: nil) == true else {
            return false
        }

        if let sessionType = prompt.sessionType {
            TaskLineHistory.shared.addLines(cleanedGoals, for: sessionType)
        }
        if currentEventId == prompt.eventId {
            currentEventNotes = updatedNotes
        }
        harshReviewCapturedEventIds.insert(prompt.eventId)
        harshPromptSnoozeUntilByID[prompt.id] = nil
        fireHarshEndLifecycle(prompt: prompt)
        sessionFeedbackPending = nil
        feedbackDismissTimer?.invalidate()
        harshModePrompt = nil
        calendarService?.refreshCurrentEvents()
        return true
    }

    func emergencyBreakHarshMode() {
        guard let prompt = harshModePrompt else { return }
        switch prompt.phase {
        case .start:
            harshStartBypassedEventIds.insert(prompt.eventId)
        case .end:
            harshEndBypassedEventIds.insert(prompt.eventId)
            fireHarshEndLifecycle(prompt: prompt)
        }
        harshPromptSnoozeUntilByID[prompt.id] = nil
        harshEndPendingMutedByID[prompt.id] = nil
        harshModePrompt = nil
    }

    func submitFeedback(rating: SessionRating) {
        guard let feedback = sessionFeedbackPending else { return }
        calendarService?.setFeedbackTag(eventId: feedback.eventId, rating: rating)
        calendarService?.refreshCurrentEvents()
        feedbackDismissTimer?.invalidate()
        sessionFeedbackPending = nil
    }

    func submitFeedback(rating: SessionRating, alignment: SessionAlignment) {
        guard let feedback = sessionFeedbackPending else { return }
        calendarService?.setReviewTags(eventId: feedback.eventId, rating: rating, alignment: alignment)
        calendarService?.refreshCurrentEvents()
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
            cancelPendingSessionAudioStart()
            isSessionMuted = true
            sessionMutedEventId = isActive ? currentEventId : nil
            audioService?.stopAmbient()
            audioService?.stopTransition()
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
