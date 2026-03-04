import Foundation
import SwiftUI

// MARK: - Scheduling Engine
/// Core scheduling algorithm ported from AppleScript
class SchedulingEngine: ObservableObject {
    // MARK: - Configuration
    // MARK: - Configuration
    @Published var workSessions: Int = 5 { didSet { saveState() } }
    @Published var sideSessions: Int = 2 { didSet { saveState() } }
    @Published var workSessionName: String = "Work Session" { didSet { saveState() } }
    @Published var sideSessionName: String = "Side Session" { didSet { saveState() } }
    @Published var workSessionDuration: Int = 40 { didSet { saveState() } }
    @Published var sideSessionDuration: Int = 30 { didSet { saveState() } }
    @Published var planningDuration: Int = 15 { didSet { saveState() } }
    @Published var restDuration: Int = 20 { didSet { saveState() } }
    @Published var schedulePlanning: Bool = true { didSet { saveState() } }
    @Published var pattern: SchedulePattern = .alternating { didSet { saveState() } }
    @Published var workSessionsPerCycle: Int = 2 { didSet { saveState() } }
    @Published var sideSessionsPerCycle: Int = 2 { didSet { saveState() } }
    @Published var sideFirst: Bool = false { didSet { saveState() } } // New
    @Published var workCalendarName: String = "Work" { didSet { saveState() } }
    @Published var sideCalendarName: String = "Side Tasks" { didSet { saveState() } }
    @Published var workCalendarIdentifier: String? { didSet { saveState() } }
    @Published var sideCalendarIdentifier: String? { didSet { saveState() } }
    @Published var hideNightHours: Bool = UserDefaults.standard.object(forKey: "TaskScheduler.HideNightHours") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hideNightHours, forKey: "TaskScheduler.HideNightHours") }
    }
    @Published var awareExistingTasks: Bool = UserDefaults.standard.object(forKey: "TaskScheduler.AwareExistingTasks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(awareExistingTasks, forKey: "TaskScheduler.AwareExistingTasks") }
    }
    @Published var showDidYouKnowCard: Bool = UserDefaults.standard.object(forKey: "TaskScheduler.ShowDidYouKnowCard") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDidYouKnowCard, forKey: "TaskScheduler.ShowDidYouKnowCard") }
    }
    @Published var dayStartHour: Int = (UserDefaults.standard.object(forKey: "TaskScheduler.DayStartHour") as? Int) ?? 6 {
        didSet { UserDefaults.standard.set(dayStartHour, forKey: "TaskScheduler.DayStartHour") }
    }
    @Published var dayEndHour: Int = (UserDefaults.standard.object(forKey: "TaskScheduler.DayEndHour") as? Int) ?? 24 {
        didSet { UserDefaults.standard.set(dayEndHour, forKey: "TaskScheduler.DayEndHour") }
    }
    @Published var scheduleEndHour: Int = (UserDefaults.standard.object(forKey: "TaskScheduler.ScheduleEndHour") as? Int) ?? 24 {
        didSet { UserDefaults.standard.set(scheduleEndHour, forKey: "TaskScheduler.ScheduleEndHour") }
    }
    @Published var flexibleSideScheduling: Bool = UserDefaults.standard.object(forKey: "TaskScheduler.FlexibleSideScheduling") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(flexibleSideScheduling, forKey: "TaskScheduler.FlexibleSideScheduling")
            saveState()
        }
    }
    
    
    // Task lists and enablement
    @Published var workTasks: String = UserDefaults.standard.string(forKey: "TaskScheduler.WorkTasks") ?? "" {
        didSet { UserDefaults.standard.set(workTasks, forKey: "TaskScheduler.WorkTasks") }
    }
    @Published var sideTasks: String = UserDefaults.standard.string(forKey: "TaskScheduler.SideTasks") ?? "" {
        didSet { UserDefaults.standard.set(sideTasks, forKey: "TaskScheduler.SideTasks") }
    }
    @Published var deepTasks: String = UserDefaults.standard.string(forKey: "TaskScheduler.DeepTasks") ?? "" {
        didSet { UserDefaults.standard.set(deepTasks, forKey: "TaskScheduler.DeepTasks") }
    }
    @Published var useWorkTasks: Bool = UserDefaults.standard.bool(forKey: "TaskScheduler.UseWorkTasks") {
        didSet { UserDefaults.standard.set(useWorkTasks, forKey: "TaskScheduler.UseWorkTasks") }
    }
    @Published var useSideTasks: Bool = UserDefaults.standard.bool(forKey: "TaskScheduler.UseSideTasks") {
        didSet { UserDefaults.standard.set(useSideTasks, forKey: "TaskScheduler.UseSideTasks") }
    }
    @Published var useDeepTasks: Bool = UserDefaults.standard.bool(forKey: "TaskScheduler.UseDeepTasks") {
        didSet { UserDefaults.standard.set(useDeepTasks, forKey: "TaskScheduler.UseDeepTasks") }
    }
    
    @Published var sideRestDuration: Int = 15 { didSet { saveState() } }
    @Published var deepRestDuration: Int = 20 { didSet { saveState() } }
    
    @Published var deepSessionConfig: DeepSessionConfig = .default { didSet { saveState() } }
    @Published var bigRestConfig: BigRestConfig = .default { didSet { saveState() } }

    // MARK: - State Tracking
    @Published var currentPresetId: UUID? {
        didSet {
             // Save the ID if it changes (though saveState covers the config, we might want to know which preset was "base")
             UserDefaults.standard.set(currentPresetId?.uuidString, forKey: "TaskScheduler.CurrentPresetId")
        }
    }
    
    // MARK: - Scheduling Settings
    private let existingEventBuffer: Int = 10 // minutes
    private let roundingInterval: Int = 5 // Changed to 5 minutes for better precision
    private let maxSchedulingHour: Int = 24
    
    // MARK: - Scheduled Output
    @Published var projectedSessions: [ScheduledSession] = []
    @Published var schedulingMessage: String = ""
    @Published var quotasSatisfied: Bool = false
    @Published var sessionsFrozen: Bool = false

    var hasNoSessionTargets: Bool {
        workSessions == 0 && sideSessions == 0 && (!deepSessionConfig.enabled || deepSessionConfig.sessionCount == 0) && !schedulePlanning
    }
    
    // MARK: - Initialization
    
    init() {
        loadState()
        
        // Load last preset ID if exists (though loadState should handle logic, we track the ID separately)
        if let idStr = UserDefaults.standard.string(forKey: "TaskScheduler.CurrentPresetId"),
           let id = UUID(uuidString: idStr) {
            self.currentPresetId = id
        }
    }
    
    // MARK: - Apply Preset
    
    func applyPreset(_ preset: Preset) {
        // Temporarily disable save to avoid multiple writes? optional.
        workSessions = preset.workSessionCount
        sideSessions = preset.sideSessionCount
        workSessionName = preset.workSessionName
        sideSessionName = preset.sideSessionName
        workSessionDuration = preset.workSessionDuration
        sideSessionDuration = preset.sideSessionDuration
        planningDuration = preset.planningDuration
        restDuration = preset.restDuration
        
        // New params
        sideRestDuration = preset.sideRestDuration
        deepRestDuration = preset.deepRestDuration
        sideSessionsPerCycle = preset.sideSessionsPerCycle
        deepSessionConfig = preset.deepSessionConfig
        sideFirst = preset.sideFirst
        flexibleSideScheduling = preset.flexibleSideScheduling
        bigRestConfig = preset.bigRestConfig

        schedulePlanning = preset.schedulePlanning
        pattern = preset.pattern
        workSessionsPerCycle = preset.workSessionsPerCycle
        workCalendarName = preset.calendarMapping.workCalendarName
        sideCalendarName = preset.calendarMapping.sideCalendarName
        workCalendarIdentifier = preset.calendarMapping.workCalendarIdentifier
        sideCalendarIdentifier = preset.calendarMapping.sideCalendarIdentifier
        
        
        currentPresetId = preset.id
        saveState()
    }
    
    // MARK: - Save as Preset
    
    func saveAsPreset(name: String, icon: String) -> Preset {
        return Preset(
            name: name,
            icon: icon,
            workSessionCount: workSessions,
            sideSessionCount: sideSessions,
            workSessionName: workSessionName,
            sideSessionName: sideSessionName,
            workSessionDuration: workSessionDuration,
            sideSessionDuration: sideSessionDuration,
            planningDuration: planningDuration,
            restDuration: restDuration,
            sideRestDuration: sideRestDuration,
            deepRestDuration: deepRestDuration,
            schedulePlanning: schedulePlanning,
            pattern: pattern,
            workSessionsPerCycle: workSessionsPerCycle,
            sideSessionsPerCycle: sideSessionsPerCycle,
            sideFirst: sideFirst,
            deepSessionConfig: deepSessionConfig,
            flexibleSideScheduling: flexibleSideScheduling,
            bigRestConfig: bigRestConfig,
            calendarMapping: CalendarMapping(
                workCalendarName: workCalendarName,
                sideCalendarName: sideCalendarName,
                workCalendarIdentifier: workCalendarIdentifier,
                sideCalendarIdentifier: sideCalendarIdentifier
            )
        )
    }
    

    /// Calculates the effective end-of-day based on scheduleEndHour.
    /// If scheduleEndHour > 24, extends into the next calendar day (e.g. 26 = 2 AM next day).
    func effectiveEndOfDay(for baseDate: Date) -> Date {
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: baseDate)!)
        if scheduleEndHour <= 24 {
            return nextMidnight
        }
        return calendar.date(byAdding: .hour, value: scheduleEndHour - 24, to: nextMidnight)!
    }

    // MARK: - Core Scheduling Algorithm
    
    func generateSchedule(
        startTime: Date,
        baseDate: Date,
        busySlots: [BusyTimeSlot],
        includePlanning: Bool,
        existingSessions: (work: Int, side: Int, deep: Int)? = nil,
        existingTitles: Set<String>? = nil
    ) -> [ScheduledSession] {
        // Don't regenerate if sessions are frozen (manual alignment in progress)
        if sessionsFrozen { return projectedSessions }

        var sessions: [ScheduledSession] = []
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: baseDate)
        let endOfDay = effectiveEndOfDay(for: baseDate)
        
        let roundedStart = roundToNextInterval(startTime)
        var currentTime = max(roundedStart, startOfDay)
        
        let bufferDuration = TimeInterval(existingEventBuffer * 60)
        var planningNeeded = includePlanning && schedulePlanning
        
        // Generate session order based on pattern
        let sessionOrder = SessionOrderGenerator(
            pattern: pattern,
            workSessions: workSessions,
            sideSessions: sideSessions,
            workSessionsPerCycle: workSessionsPerCycle,
            sideSessionsPerCycle: sideSessionsPerCycle,
            sideFirst: sideFirst
        ).generateOrder()
        
        var sessionIndex = 0
        var workCount = 0
        var sideCount = 0
        var deepCount = 0
        var regularSessionsScheduled = 0
        var regularCountAtLastDeep = 0
        var cumulativeSessionMinutes = 0
        var bigRestCount = 0
        
        if awareExistingTasks, let existing = existingSessions {
            workCount = existing.work
            sideCount = existing.side
            deepCount = existing.deep
            regularSessionsScheduled = workCount + sideCount
            regularCountAtLastDeep = regularSessionsScheduled
        }
        
        var attempts = 0
        let maxAttempts = 500
        
        // Prepare task titles
        var workTitles = workTasks.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var sideTitles = sideTasks.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        var deepTitles = deepTasks.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        // Smart allocation: Remove titles that already exist on the calendar today
        if let existing = existingTitles {
            workTitles = workTitles.filter { !existing.contains($0) }
            sideTitles = sideTitles.filter { !existing.contains($0) }
            deepTitles = deepTitles.filter { !existing.contains($0) }
        }
        
        var projectedWorkCount = 0
        var projectedSideCount = 0
        var projectedDeepCount = 0
        
        while (workCount < workSessions || sideCount < sideSessions || planningNeeded || (deepSessionConfig.enabled && deepCount < deepSessionConfig.sessionCount)) && attempts < maxAttempts {
            attempts += 1
            
            if currentTime >= endOfDay {
                schedulingMessage = "Reached end of day."
                break
            }
            
            var sessionType: SessionType
            var sessionDuration: Int
            var sessionTitle: String
            var calendarName: String
            var calendarIdentifier: String?
            var sessionTag: String
            var isDeep = false
            
            if planningNeeded {
                sessionType = .planning
                sessionDuration = planningDuration
                sessionTitle = "Planning"
                calendarName = workCalendarName
                calendarIdentifier = workCalendarIdentifier
                sessionTag = "#plan"
            } else {
                let sessionsSinceLastDeep = regularSessionsScheduled - regularCountAtLastDeep

                // For the first deep session, use injectAfterEvery; for 2nd+, use andThenGap
                let requiredSlots = deepCount == 0 ? deepSessionConfig.injectAfterEvery : deepSessionConfig.andThenGap

                // Special handling for requiredSlots == 0: inject immediately
                let shouldInjectDeepImmediately = deepSessionConfig.enabled
                    && deepCount < deepSessionConfig.sessionCount
                    && requiredSlots == 0

                // Normal injection logic: inject after N regular sessions
                let shouldInjectDeep = deepSessionConfig.enabled
                    && deepCount < deepSessionConfig.sessionCount
                    && regularSessionsScheduled > 0
                    && requiredSlots > 0

                if shouldInjectDeepImmediately || (shouldInjectDeep && sessionsSinceLastDeep >= requiredSlots) {
                     sessionType = .deep
                     sessionDuration = deepSessionConfig.duration
                     
                     if useDeepTasks && deepCount < deepTitles.count {
                         sessionTitle = deepTitles[deepCount]
                     } else {
                         sessionTitle = deepSessionConfig.name
                     }
                     
                     calendarName = deepSessionConfig.calendarName
                     calendarIdentifier = deepSessionConfig.calendarIdentifier
                     sessionTag = "#deep"
                     isDeep = true
                 } else if sessionIndex < sessionOrder.count {
                    let proposedType = sessionOrder[sessionIndex]
                    
                    if (proposedType == .work && workCount >= workSessions) ||
                       (proposedType == .side && sideCount >= sideSessions) {
                        sessionIndex += 1
                        continue
                    }
                    
                    sessionType = proposedType
                    switch sessionType {
                    case .work:
                        sessionDuration = workSessionDuration
                        sessionTitle = (useWorkTasks && projectedWorkCount < workTitles.count) ? workTitles[projectedWorkCount] : workSessionName
                        calendarName = workCalendarName
                        calendarIdentifier = workCalendarIdentifier
                        sessionTag = "#work"
                    case .side:
                        sessionDuration = sideSessionDuration
                        sessionTitle = (useSideTasks && projectedSideCount < sideTitles.count) ? sideTitles[projectedSideCount] : sideSessionName
                        calendarName = sideCalendarName
                        calendarIdentifier = sideCalendarIdentifier
                        sessionTag = "#side"
                    case .planning, .deep, .bigRest:
                         sessionDuration = workSessionDuration
                         sessionTitle = "Unknown"
                         calendarName = workCalendarName
                         calendarIdentifier = workCalendarIdentifier
                         sessionTag = ""
                    }
                } else {
                    if workCount < workSessions {
                        sessionType = .work
                        sessionDuration = workSessionDuration
                        sessionTitle = (useWorkTasks && projectedWorkCount < workTitles.count) ? workTitles[projectedWorkCount] : workSessionName
                        calendarName = workCalendarName
                        calendarIdentifier = workCalendarIdentifier
                        sessionTag = "#work"
                    } else if sideCount < sideSessions {
                        sessionType = .side
                        sessionDuration = sideSessionDuration
                        sessionTitle = (useSideTasks && projectedSideCount < sideTitles.count) ? sideTitles[projectedSideCount] : sideSessionName
                        calendarName = sideCalendarName
                        calendarIdentifier = sideCalendarIdentifier
                        sessionTag = "#side"
                    } else if deepSessionConfig.enabled && deepCount < deepSessionConfig.sessionCount {
                         sessionType = .deep
                         sessionDuration = deepSessionConfig.duration
                         sessionTitle = (useDeepTasks && projectedDeepCount < deepTitles.count) ? deepTitles[projectedDeepCount] : deepSessionConfig.name
                         calendarName = deepSessionConfig.calendarName
                         calendarIdentifier = deepSessionConfig.calendarIdentifier
                         sessionTag = "#deep"
                         isDeep = true
                    } else {
                        break
                    }
                }
            }
            
            let potentialEnd = currentTime.addingTimeInterval(TimeInterval(sessionDuration * 60))
            
            if potentialEnd > endOfDay {
                schedulingMessage = "Cannot fit remaining sessions."
                break
            }
            
            let conflict = findConflict(start: currentTime, end: potentialEnd, busySlots: busySlots, buffer: bufferDuration)
            
            if let conflictEnd = conflict {
                if !planningNeeded && !isDeep {
                    // Try swapping work <-> side when one doesn't fit
                    // If flexibleSideScheduling is enabled, also try fitting side in smaller gaps
                    if let alt = tryAlternativeSession(
                        currentTime: currentTime,
                        conflictEnd: conflictEnd,
                        currentType: sessionType,
                        workCount: workCount,
                        sideCount: sideCount,
                        busySlots: busySlots,
                        buffer: bufferDuration,
                        endOfDay: endOfDay,
                        workTitles: workTitles,
                        sideTitles: sideTitles,
                        projectedWorkCount: projectedWorkCount,
                        projectedSideCount: projectedSideCount,
                        flexibleSideScheduling: flexibleSideScheduling
                    ) {
                        sessions.append(alt)
                        if alt.type == .work {
                            workCount += 1
                            projectedWorkCount += 1
                        } else {
                            sideCount += 1
                            projectedSideCount += 1
                        }
                        regularSessionsScheduled += 1
                        let appliedRest = alt.type == .side ? sideRestDuration : restDuration
                        currentTime = roundToNextInterval(alt.endTime.addingTimeInterval(TimeInterval(appliedRest * 60)))
                        continue
                    }
                } else if isDeep {
                    // Deep session can't fit - try to fill the gap with work/side instead
                    // The deep session will be rescheduled after we have more regular sessions
                    if let alt = tryFillGapWithRegularSession(
                        currentTime: currentTime,
                        workCount: workCount,
                        sideCount: sideCount,
                        busySlots: busySlots,
                        buffer: bufferDuration,
                        endOfDay: endOfDay,
                        workTitles: workTitles,
                        sideTitles: sideTitles,
                        projectedWorkCount: projectedWorkCount,
                        projectedSideCount: projectedSideCount,
                        sessionIndex: sessionIndex,
                        sessionOrder: sessionOrder
                    ) {
                        sessions.append(alt)
                        if alt.type == .work {
                            workCount += 1
                            projectedWorkCount += 1
                        } else {
                            sideCount += 1
                            projectedSideCount += 1
                        }
                        regularSessionsScheduled += 1
                        sessionIndex += 1
                        let appliedRest = alt.type == .side ? sideRestDuration : restDuration
                        currentTime = roundToNextInterval(alt.endTime.addingTimeInterval(TimeInterval(appliedRest * 60)))
                        continue
                    }
                }
                currentTime = roundToNextInterval(conflictEnd)
                continue
            }
            
            let session = ScheduledSession(
                type: sessionType,
                title: sessionTitle,
                startTime: currentTime,
                endTime: potentialEnd,
                calendarName: calendarName,
                calendarIdentifier: calendarIdentifier,
                notes: sessionTag
            )
            sessions.append(session)
            
            var appliedRest = restDuration
            
            if planningNeeded {
                planningNeeded = false
                appliedRest = max(5, restDuration / 2)
            } else if isDeep {
                deepCount += 1
                projectedDeepCount += 1
                regularCountAtLastDeep = regularSessionsScheduled
                appliedRest = deepRestDuration
            } else {
                switch sessionType {
                case .work:
                    workCount += 1
                    projectedWorkCount += 1
                    regularSessionsScheduled += 1
                    appliedRest = restDuration
                case .side:
                    sideCount += 1
                    projectedSideCount += 1
                    regularSessionsScheduled += 1
                    appliedRest = sideRestDuration
                default: break
                }
                sessionIndex += 1
            }
            
            // Long Rest injection: track cumulative session time and inject when threshold reached
            cumulativeSessionMinutes += sessionDuration
            let deepQuotaMetNow = !deepSessionConfig.enabled || deepCount >= deepSessionConfig.sessionCount
            let allQuotasMet = workCount >= workSessions && sideCount >= sideSessions && deepQuotaMetNow
            if bigRestConfig.enabled && !allQuotasMet && bigRestCount < bigRestConfig.count && cumulativeSessionMinutes >= bigRestConfig.afterMinutes {
                // Big Rest starts right after the session (no rest gap before it)
                let restStart = roundToNextInterval(potentialEnd)
                let restEnd = restStart.addingTimeInterval(TimeInterval(bigRestConfig.duration * 60))
                if restEnd <= endOfDay {
                    let bigRest = ScheduledSession(
                        type: .bigRest,
                        title: "Long Rest",
                        startTime: restStart,
                        endTime: restEnd,
                        calendarName: calendarName,
                        notes: "#break"
                    )
                    sessions.append(bigRest)
                    bigRestCount += 1
                    cumulativeSessionMinutes = 0
                    // Next session starts immediately after big rest (no extra rest gap)
                    currentTime = roundToNextInterval(restEnd)
                } else {
                    currentTime = roundToNextInterval(potentialEnd.addingTimeInterval(TimeInterval(appliedRest * 60)))
                }
            } else {
                currentTime = roundToNextInterval(potentialEnd.addingTimeInterval(TimeInterval(appliedRest * 60)))
            }
        }
        
        projectedSessions = sessions

        let deepQuotaMet = !deepSessionConfig.enabled || deepCount >= deepSessionConfig.sessionCount
        quotasSatisfied = workCount >= workSessions && sideCount >= sideSessions && deepQuotaMet

        var existingNote = ""
        if awareExistingTasks, let existing = existingSessions {
            let total = existing.work + existing.side + existing.deep
            if total > 0 {
                existingNote = " (Found \(total) existing sessions)"
            }
        }

        // Build quota detail when not satisfied
        func quotaDetail() -> String {
            var parts: [String] = []
            if workCount < workSessions {
                parts.append("\(workSessions - workCount) work")
            }
            if sideCount < sideSessions {
                parts.append("\(sideSessions - sideCount) side")
            }
            if deepSessionConfig.enabled && deepCount < deepSessionConfig.sessionCount {
                parts.append("\(deepSessionConfig.sessionCount - deepCount) deep")
            }
            return parts.isEmpty ? "" : " Still need: \(parts.joined(separator: ", "))."
        }

        let totalTarget = workSessions + sideSessions + (deepSessionConfig.enabled ? deepSessionConfig.sessionCount : 0)

        if sessions.isEmpty {
            if totalTarget == 0 && !planningNeeded {
                schedulingMessage = "No sessions configured."
            } else if quotasSatisfied {
                schedulingMessage = "Daily quota met by existing sessions." + existingNote
            } else {
                schedulingMessage = "No suitable time slots found." + quotaDetail() + existingNote
            }
        } else if !quotasSatisfied {
            schedulingMessage = "Projected \(sessions.count) sessions." + quotaDetail() + existingNote
        } else {
            schedulingMessage = "Successfully projected \(sessions.count) sessions." + existingNote
        }
        
        return sessions
    }
    
    // MARK: - Try Alternative Session
    
    /// Tries to fit a different session type in a gap that's too small for the preferred type
    /// When flexibleSideScheduling is OFF, only tries swapping if both types fit perfectly
    /// When flexibleSideScheduling is ON, also tries fitting sides in smaller gaps
    private func tryAlternativeSession(
        currentTime: Date,
        conflictEnd: Date,
        currentType: SessionType,
        workCount: Int,
        sideCount: Int,
        busySlots: [BusyTimeSlot],
        buffer: TimeInterval,
        endOfDay: Date,
        workTitles: [String],
        sideTitles: [String],
        projectedWorkCount: Int,
        projectedSideCount: Int,
        flexibleSideScheduling: Bool
    ) -> ScheduledSession? {
        // If flexibleSideScheduling is OFF, don't try alternative session types at all
        // This prevents sides from filling gaps when work doesn't fit
        guard flexibleSideScheduling else {
            return nil
        }
        
        // If we can't fit a work session, try side (and vice versa)
        let alternativeType: SessionType
        let alternativeDuration: Int
        let alternativeTitle: String
        let alternativeCalendar: String
        let alternativeCalendarIdentifier: String?
        
        if currentType == .work && sideCount < sideSessions {
            alternativeType = .side
            alternativeDuration = sideSessionDuration
            alternativeCalendar = sideCalendarName
            alternativeCalendarIdentifier = sideCalendarIdentifier
            alternativeTitle = (useSideTasks && projectedSideCount < sideTitles.count) ? sideTitles[projectedSideCount] : sideSessionName
        } else if currentType == .side && workCount < workSessions {
            alternativeType = .work
            alternativeDuration = workSessionDuration
            alternativeCalendar = workCalendarName
            alternativeCalendarIdentifier = workCalendarIdentifier
            alternativeTitle = (useWorkTasks && projectedWorkCount < workTitles.count) ? workTitles[projectedWorkCount] : workSessionName
        } else {
            return nil
        }
        
        let potentialEnd = currentTime.addingTimeInterval(TimeInterval(alternativeDuration * 60))
        
        // Check if fits before day end
        if potentialEnd > endOfDay {
            return nil
        }
        
        // Check for conflicts
        let conflict = findConflict(
            start: currentTime,
            end: potentialEnd,
            busySlots: busySlots,
            buffer: buffer
        )
        
        if conflict == nil {
            return ScheduledSession(
                type: alternativeType,
                title: alternativeTitle,
                startTime: currentTime,
                endTime: potentialEnd,
                calendarName: alternativeCalendar,
                calendarIdentifier: alternativeCalendarIdentifier,
                notes: alternativeType == .work ? "#work" : "#side"
            )
        }
        
        // If flexibleSideScheduling is enabled and we're trying to fit a work session,
        // also try fitting a side session in the available gap before the conflict
        // This allows sides to be scheduled in smaller gaps that work sessions can't fit into
        if currentType == .work && sideCount < sideSessions {
            let gapDuration = conflictEnd.timeIntervalSince(currentTime)
            let sideDuration = TimeInterval(sideSessionDuration * 60)
            
            // Check if side session fits in the gap (even if it's smaller than work duration)
            if gapDuration >= sideDuration {
                let sideEnd = currentTime.addingTimeInterval(sideDuration)
                
                // Double-check no conflicts and that it fits before end of day
                if sideEnd <= endOfDay {
                    let sideConflict = findConflict(
                        start: currentTime,
                        end: sideEnd,
                        busySlots: busySlots,
                        buffer: buffer
                    )
                    
                    if sideConflict == nil {
                        let sideTitle = (useSideTasks && projectedSideCount < sideTitles.count) ? sideTitles[projectedSideCount] : sideSessionName
                        return ScheduledSession(
                            type: .side,
                            title: sideTitle,
                            startTime: currentTime,
                            endTime: sideEnd,
                            calendarName: sideCalendarName,
                            calendarIdentifier: sideCalendarIdentifier,
                            notes: "#side"
                        )
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Try Fill Gap With Regular Session (when Deep can't fit)
    
    /// When a deep session can't fit due to a conflict, try to fill the gap with work/side sessions
    private func tryFillGapWithRegularSession(
        currentTime: Date,
        workCount: Int,
        sideCount: Int,
        busySlots: [BusyTimeSlot],
        buffer: TimeInterval,
        endOfDay: Date,
        workTitles: [String],
        sideTitles: [String],
        projectedWorkCount: Int,
        projectedSideCount: Int,
        sessionIndex: Int,
        sessionOrder: [SessionType]
    ) -> ScheduledSession? {
        // Check if we still need work or side sessions
        let needWork = workCount < workSessions
        let needSide = sideCount < sideSessions
        
        if !needWork && !needSide {
            return nil
        }
        
        // Determine preferred order based on pattern
        var sessionsToTry: [(SessionType, Int, String, String, String?)] = []
        
        // Check what the next session in order would be
        if sessionIndex < sessionOrder.count {
            let preferredType = sessionOrder[sessionIndex]
            if preferredType == .work && needWork {
                let title = (useWorkTasks && projectedWorkCount < workTitles.count) ? workTitles[projectedWorkCount] : workSessionName
                sessionsToTry.append((.work, workSessionDuration, workCalendarName, title, workCalendarIdentifier))
            } else if preferredType == .side && needSide {
                let title = (useSideTasks && projectedSideCount < sideTitles.count) ? sideTitles[projectedSideCount] : sideSessionName
                sessionsToTry.append((.side, sideSessionDuration, sideCalendarName, title, sideCalendarIdentifier))
            }
        }
        
        // Add alternatives if we still need them
        if needWork && !sessionsToTry.contains(where: { $0.0 == .work }) {
            let title = (useWorkTasks && projectedWorkCount < workTitles.count) ? workTitles[projectedWorkCount] : workSessionName
            sessionsToTry.append((.work, workSessionDuration, workCalendarName, title, workCalendarIdentifier))
        }
        if needSide && !sessionsToTry.contains(where: { $0.0 == .side }) {
            let title = (useSideTasks && projectedSideCount < sideTitles.count) ? sideTitles[projectedSideCount] : sideSessionName
            sessionsToTry.append((.side, sideSessionDuration, sideCalendarName, title, sideCalendarIdentifier))
        }
        
        // Try each session type
        for (sessionType, duration, calendarName, title, calendarIdentifier) in sessionsToTry {
            let potentialEnd = currentTime.addingTimeInterval(TimeInterval(duration * 60))
            
            // Check if fits before day end
            if potentialEnd > endOfDay {
                continue
            }
            
            // Check for conflicts
            let conflict = findConflict(
                start: currentTime,
                end: potentialEnd,
                busySlots: busySlots,
                buffer: buffer
            )
            
            if conflict == nil {
                return ScheduledSession(
                    type: sessionType,
                    title: title,
                    startTime: currentTime,
                    endTime: potentialEnd,
                    calendarName: calendarName,
                    calendarIdentifier: calendarIdentifier,
                    notes: sessionType == .work ? "#work" : "#side"
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    /// Rounds the given date UP to the next interval boundary (e.g., 15-minute mark)
    private func roundToNextInterval(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let minutes = components.minute ?? 0
        
        let remainder = minutes % roundingInterval
        
        // If already on an interval boundary, return as-is
        if remainder == 0 {
            // Create a clean date without seconds
            var cleanComponents = components
            cleanComponents.second = 0
            return calendar.date(from: cleanComponents) ?? date
        }
        
        // Otherwise, round up to next interval
        let minutesToAdd = roundingInterval - remainder
        
        return calendar.date(byAdding: .minute, value: minutesToAdd, to: date) ?? date
    }
    
    // MARK: - Single Session Projection
    
    func projectSingleSession(
        type: SessionType,
        startTime: Date,
        baseDate: Date,
        busySlots: [BusyTimeSlot]
    ) -> ScheduledSession? {
        let endOfDay = effectiveEndOfDay(for: baseDate)
        let bufferDuration = TimeInterval(existingEventBuffer * 60)
        
        var currentTime = roundToNextInterval(startTime)
        let sessionDuration: Int
        switch type {
        case .work: sessionDuration = workSessionDuration
        case .side: sessionDuration = sideSessionDuration
        case .planning: sessionDuration = planningDuration
        case .deep: sessionDuration = deepSessionConfig.duration
        case .bigRest: sessionDuration = bigRestConfig.duration
        }

        var attempts = 0
        let maxAttempts = 100
        
        while attempts < maxAttempts {
            attempts += 1
            
            if currentTime >= endOfDay {
                return nil
            }
            
            let potentialEnd = currentTime.addingTimeInterval(TimeInterval(sessionDuration * 60))
            
            if potentialEnd > endOfDay {
                return nil
            }
            
            let conflict = findConflict(
                start: currentTime,
                end: potentialEnd,
                busySlots: busySlots,
                buffer: bufferDuration
            )
            
            if let conflictEnd = conflict {
                currentTime = roundToNextInterval(conflictEnd)
                continue
            }
            
            // Found a slot
            let calendar: String
            let calendarIdentifier: String?
            switch type {
            case .work:
                calendar = workCalendarName
                calendarIdentifier = workCalendarIdentifier
            case .side:
                calendar = sideCalendarName
                calendarIdentifier = sideCalendarIdentifier
            case .deep:
                calendar = deepSessionConfig.calendarName
                calendarIdentifier = deepSessionConfig.calendarIdentifier
            case .planning:
                calendar = workCalendarName // Planning uses work calendar
                calendarIdentifier = workCalendarIdentifier
            case .bigRest:
                calendar = workCalendarName
                calendarIdentifier = workCalendarIdentifier
            }
            
            return ScheduledSession(
                type: type,
                title: type == .planning ? "Planning" : type.rawValue + " Session",
                startTime: currentTime,
                endTime: potentialEnd,
                calendarName: calendar,
                calendarIdentifier: calendarIdentifier,
                notes: type == .work ? "#work" : (type == .side ? "#side" : (type == .planning ? "#plan" : "#deep"))
            )
        }
        
        return nil
    }
    
    private func findConflict(
        start: Date,
        end: Date,
        busySlots: [BusyTimeSlot],
        buffer: TimeInterval
    ) -> Date? {
        for slot in busySlots {
            let effectiveStart = slot.startTime.addingTimeInterval(-buffer)
            let effectiveEnd = slot.endTime.addingTimeInterval(buffer)
            
            // Check for overlap
            if start < effectiveEnd && end > effectiveStart {
                return effectiveEnd
            }
        }
        return nil
    }
    
    // MARK: - Availability Stats
    
    func calculateAvailability(
        startTime: Date,
        baseDate: Date,
        busySlots: [BusyTimeSlot]
    ) -> (availableMinutes: Int, possibleWorkSessions: Int, possibleSideSessions: Int, possibleDeepSessions: Int) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: baseDate)
        let endOfDay = effectiveEndOfDay(for: baseDate)
        
        let effectiveStart = max(startTime, startOfDay)
        
        var totalAvailable = 0
        var currentTime = effectiveStart
        let bufferDuration = TimeInterval(existingEventBuffer * 60)
        
        // Sort busy slots by start time
        let sortedSlots = busySlots.sorted { $0.startTime < $1.startTime }
        
        for slot in sortedSlots {
            let effectiveStart = slot.startTime.addingTimeInterval(-bufferDuration)
            
            if currentTime < effectiveStart && effectiveStart < endOfDay {
                let gapMinutes = Int(effectiveStart.timeIntervalSince(currentTime) / 60)
                totalAvailable += max(0, gapMinutes)
            }
            
            let effectiveEnd = slot.endTime.addingTimeInterval(bufferDuration)
            if effectiveEnd > currentTime {
                currentTime = effectiveEnd
            }
        }
        
        // Add remaining time until end of day
        if currentTime < endOfDay {
            let remainingMinutes = Int(endOfDay.timeIntervalSince(currentTime) / 60)
            totalAvailable += max(0, remainingMinutes)
        }
        
        // Calculate possible sessions (with rest between)
        let workWithRest = workSessionDuration + restDuration
        let sideWithRest = sideSessionDuration + restDuration
        let deepWithRest = deepSessionConfig.duration + deepRestDuration
        
        let possibleWork = totalAvailable / max(1, workWithRest)
        let possibleSide = totalAvailable / max(1, sideWithRest)
        let possibleDeep = totalAvailable / max(1, deepWithRest)
        
        return (totalAvailable, possibleWork, possibleSide, possibleDeep)
    }
    
    // MARK: - State Persistence
    
    private var isLoadingState = false
    
    private func saveState() {
        guard !isLoadingState else { return }
        
        let state = Preset(
            id: UUID(), // Dummy ID
            name: "Current State", // Dummy Name
            icon: "gear", // Dummy Icon
            workSessionCount: workSessions,
            sideSessionCount: sideSessions,
            workSessionName: workSessionName,
            sideSessionName: sideSessionName,
            workSessionDuration: workSessionDuration,
            sideSessionDuration: sideSessionDuration,
            planningDuration: planningDuration,
            restDuration: restDuration,
            sideRestDuration: sideRestDuration,
            deepRestDuration: deepRestDuration,
            schedulePlanning: schedulePlanning,
            pattern: pattern,
            workSessionsPerCycle: workSessionsPerCycle,
            sideSessionsPerCycle: sideSessionsPerCycle,
            sideFirst: sideFirst,
            deepSessionConfig: deepSessionConfig,
            flexibleSideScheduling: flexibleSideScheduling,
            bigRestConfig: bigRestConfig,
            calendarMapping: CalendarMapping(
                workCalendarName: workCalendarName,
                sideCalendarName: sideCalendarName,
                workCalendarIdentifier: workCalendarIdentifier,
                sideCalendarIdentifier: sideCalendarIdentifier
            )
        )

        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: "TaskScheduler.SavedState")
        }
    }
    
    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: "TaskScheduler.SavedState"),
              var state = try? JSONDecoder().decode(Preset.self, from: data) else {
            return
        }
        
        // Migrate saved state to current version if needed
        state.migrateToCurrentVersion()
        
        isLoadingState = true
        defer { isLoadingState = false }
        
        workSessions = state.workSessionCount
        sideSessions = state.sideSessionCount
        workSessionName = state.workSessionName
        sideSessionName = state.sideSessionName
        workSessionDuration = state.workSessionDuration
        sideSessionDuration = state.sideSessionDuration
        planningDuration = state.planningDuration
        restDuration = state.restDuration
        sideRestDuration = state.sideRestDuration
        deepRestDuration = state.deepRestDuration
        schedulePlanning = state.schedulePlanning
        pattern = state.pattern
        workSessionsPerCycle = state.workSessionsPerCycle
        sideSessionsPerCycle = state.sideSessionsPerCycle
        sideFirst = state.sideFirst
        deepSessionConfig = state.deepSessionConfig
        flexibleSideScheduling = state.flexibleSideScheduling
        bigRestConfig = state.bigRestConfig
        workCalendarName = state.calendarMapping.workCalendarName
        sideCalendarName = state.calendarMapping.sideCalendarName
        workCalendarIdentifier = state.calendarMapping.workCalendarIdentifier
        sideCalendarIdentifier = state.calendarMapping.sideCalendarIdentifier
    }
    
    func isPresetModified(_ preset: Preset) -> Bool {
        return workSessions != preset.workSessionCount ||
               sideSessions != preset.sideSessionCount ||
               workSessionName != preset.workSessionName ||
               sideSessionName != preset.sideSessionName ||
               workSessionDuration != preset.workSessionDuration ||
               sideSessionDuration != preset.sideSessionDuration ||
               planningDuration != preset.planningDuration ||
               restDuration != preset.restDuration ||
               sideRestDuration != preset.sideRestDuration ||
               deepRestDuration != preset.deepRestDuration ||
               schedulePlanning != preset.schedulePlanning ||
               pattern != preset.pattern ||
               workSessionsPerCycle != preset.workSessionsPerCycle ||
               sideSessionsPerCycle != preset.sideSessionsPerCycle ||
               sideFirst != preset.sideFirst ||
               deepSessionConfig != preset.deepSessionConfig ||
               flexibleSideScheduling != preset.flexibleSideScheduling ||
               bigRestConfig != preset.bigRestConfig ||
               workCalendarName != preset.calendarMapping.workCalendarName ||
               sideCalendarName != preset.calendarMapping.sideCalendarName ||
               workCalendarIdentifier != preset.calendarMapping.workCalendarIdentifier ||
               sideCalendarIdentifier != preset.calendarMapping.sideCalendarIdentifier
    }
    
    func reconcileCalendars(with service: CalendarService) {
        func sync(name: inout String, identifier: inout String?) {
            if let id = identifier, let calendar = service.getCalendar(identifier: id) {
                if calendar.title != name {
                    name = calendar.title
                }
            } else if let calendar = service.getCalendar(named: name) {
                identifier = calendar.calendarIdentifier
                name = calendar.title
            }
        }
        
        sync(name: &workCalendarName, identifier: &workCalendarIdentifier)
        sync(name: &sideCalendarName, identifier: &sideCalendarIdentifier)
        
        if let id = deepSessionConfig.calendarIdentifier,
           let calendar = service.getCalendar(identifier: id),
           calendar.title != deepSessionConfig.calendarName {
            var config = deepSessionConfig
            config.calendarName = calendar.title
            deepSessionConfig = config
        } else if service.getCalendar(named: deepSessionConfig.calendarName) != nil {
            if deepSessionConfig.calendarIdentifier == nil,
               let calendar = service.getCalendar(named: deepSessionConfig.calendarName) {
                var config = deepSessionConfig
                config.calendarIdentifier = calendar.calendarIdentifier
                config.calendarName = calendar.title
                deepSessionConfig = config
            }
        }
    }

    // MARK: - Projected Session Displacement

    /// Returns the rest duration (in seconds) that follows a given session type.
    private func restAfterSession(_ type: SessionType) -> TimeInterval {
        switch type {
        case .bigRest: return 0  // Long Rest is rest itself — no gap after it
        case .side: return TimeInterval(sideRestDuration * 60)
        case .deep: return TimeInterval(deepRestDuration * 60)
        default: return TimeInterval(restDuration * 60)
        }
    }

    /// Displaces projected sessions that overlap with the dragged session,
    /// pushing them forward in time while respecting calendar busy slots,
    /// rest durations between sessions, and the earliest allowed time boundary.
    /// Rest is added after each displaced session but NOT around the dragged item.
    func displaceProjectedSessions(
        draggedSessionId: UUID,
        draggedStart: Date,
        draggedEnd: Date,
        busySlots: [BusyTimeSlot],
        earliestTime: Date
    ) {
        let bufferDuration = TimeInterval(existingEventBuffer * 60)

        // Obstacles track both the raw end and the padded end (with rest).
        // Long Rest sessions ignore rest padding and can start at rawEnd.
        var obstacles: [(start: Date, rawEnd: Date, paddedEnd: Date)] = busySlots.map {
            let s = $0.startTime.addingTimeInterval(-bufferDuration)
            let e = $0.endTime.addingTimeInterval(bufferDuration)
            return (s, e, e)
        }
        // Dragged session is an obstacle without rest padding
        obstacles.append((draggedStart, draggedEnd, draggedEnd))
        obstacles.sort { $0.start < $1.start }

        // Collect non-dragged sessions sorted by start time
        let otherIndices = projectedSessions.enumerated()
            .filter { $0.element.id != draggedSessionId }
            .sorted { $0.element.startTime < $1.element.startTime }

        for (idx, session) in otherIndices {
            let duration = session.endTime.timeIntervalSince(session.startTime)
            let isBigRest = session.type == .bigRest
            var candidateStart = max(session.startTime, earliestTime)

            // Push forward until no overlap with any obstacle
            var settled = false
            while !settled {
                let candidateEnd = candidateStart.addingTimeInterval(duration)
                // Long Rest ignores rest padding — uses rawEnd; others use paddedEnd
                let effectiveEnd: (Date, Date, Date) -> Date = { _, raw, padded in isBigRest ? raw : padded }
                if let blocker = obstacles.first(where: { candidateStart < effectiveEnd($0.start, $0.rawEnd, $0.paddedEnd) && candidateEnd > $0.start }) {
                    candidateStart = effectiveEnd(blocker.start, blocker.rawEnd, blocker.paddedEnd)
                } else {
                    settled = true
                }
            }

            let newEnd = candidateStart.addingTimeInterval(duration)
            projectedSessions[idx].startTime = candidateStart
            projectedSessions[idx].endTime = newEnd

            // This placed session + its rest becomes an obstacle for subsequent ones
            let rest = restAfterSession(session.type)
            obstacles.append((candidateStart, newEnd, newEnd.addingTimeInterval(rest)))
            obstacles.sort { $0.start < $1.start }
        }
    }
}
