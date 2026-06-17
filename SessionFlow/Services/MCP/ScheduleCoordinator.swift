import Foundation

enum DeleteScope: String {
    case all
    case future
}

struct ExistingSessionSummary: Equatable {
    let work: Int
    let side: Int
    let deep: Int
    let titles: Set<String>
}

struct ScheduleDaySnapshot {
    let date: Date
    let busySlots: [BusyTimeSlot]
    let planningExists: Bool
    let existingSessions: ExistingSessionSummary
    let availability: (availableMinutes: Int, possibleWorkSessions: Int, possibleSideSessions: Int, possibleDeepSessions: Int)
}

/// Drives schedule preview / commit / delete the way ContentView does, but parameterized by an
/// explicit date and start time so the MCP agent (and tests) can operate on any day independently
/// of the open window's UI state. Reuses the same `SchedulingEngine` and calendar APIs the UI uses.
@MainActor
final class ScheduleCoordinator {
    private let engine: SchedulingEngine
    private let calendar: any CalendarWriting

    init(engine: SchedulingEngine, calendar: any CalendarWriting) {
        self.engine = engine
        self.calendar = calendar
    }

    private func syncCalendarWindow() {
        calendar.scheduleEndHour = engine.scheduleEndHour
    }

    /// Today → current time rounded up to the next 5 minutes; other days → the configured default hour.
    func defaultStartTime(for date: Date) -> Date {
        let cal = Calendar.current
        guard cal.isDateInToday(date) else {
            return cal.date(bySettingHour: engine.defaultStartHour, minute: 0, second: 0, of: date) ?? date
        }
        let now = Date()
        let minute = cal.component(.minute, from: now)
        let bump = minute % 5 == 0 ? 0 : (5 - minute % 5)
        let floored = cal.date(bySettingHour: cal.component(.hour, from: now), minute: minute, second: 0, of: now) ?? now
        return cal.date(byAdding: .minute, value: bump, to: floored) ?? now
    }

    private func existingSessions(for date: Date) -> ExistingSessionSummary {
        let existing = calendar.countExistingSessions(
            for: date,
            workCalendar: engine.workCalendarDescriptor,
            sideCalendar: engine.sideCalendarDescriptor,
            deepConfig: engine.deepSessionConfig
        )
        return ExistingSessionSummary(
            work: existing.work,
            side: existing.side,
            deep: existing.deep,
            titles: existing.titles
        )
    }

    func daySnapshot(date: Date, startTime: Date? = nil, extraBusySlots: [BusyTimeSlot] = []) async -> ScheduleDaySnapshot {
        syncCalendarWindow()
        await calendar.fetchEvents(for: date)
        return daySnapshotFromFetched(
            date: date,
            startTime: startTime ?? defaultStartTime(for: date),
            busySlots: calendar.busySlotsForFetchedDate(date) + extraBusySlots
        )
    }

    func daySnapshotFromFetched(date: Date, startTime: Date, busySlots: [BusyTimeSlot]) -> ScheduleDaySnapshot {
        syncCalendarWindow()
        let planningExists = calendar.hasPlanningSession(for: date, planningEventName: "Planning")
        let existing = existingSessions(for: date)
        let availability = engine.calculateAvailability(
            startTime: startTime,
            baseDate: date,
            busySlots: busySlots
        )
        return ScheduleDaySnapshot(
            date: date,
            busySlots: busySlots,
            planningExists: planningExists,
            existingSessions: existing,
            availability: availability
        )
    }

    @discardableResult
    func rebuildPreview(date: Date, startTime: Date, snapshot: ScheduleDaySnapshot) -> [ScheduledSession] {
        let wasFrozen = engine.sessionsFrozen
        _ = engine.generateSchedule(
            startTime: startTime,
            baseDate: date,
            busySlots: snapshot.busySlots,
            includePlanning: !snapshot.planningExists,
            existingSessions: (
                work: snapshot.existingSessions.work,
                side: snapshot.existingSessions.side,
                deep: snapshot.existingSessions.deep
            ),
            existingTitles: snapshot.existingSessions.titles
        )
        if !wasFrozen {
            engine.projectedSessionsDate = Calendar.current.startOfDay(for: date)
        }
        return engine.projectedSessions
    }

    @discardableResult
    func regeneratePreviewFromFetched(date: Date, startTime: Date, busySlots: [BusyTimeSlot]) -> [ScheduledSession] {
        let snapshot = daySnapshotFromFetched(date: date, startTime: startTime, busySlots: busySlots)
        return rebuildPreview(date: date, startTime: startTime, snapshot: snapshot)
    }

    /// Rebuilds the in-app preview (`engine.projectedSessions`) for the given day. No calendar writes.
    @discardableResult
    func regeneratePreview(date: Date, startTime: Date? = nil, extraBusySlots: [BusyTimeSlot] = []) async -> [ScheduledSession] {
        let resolvedStartTime = startTime ?? defaultStartTime(for: date)
        let snapshot = await daySnapshot(date: date, startTime: resolvedStartTime, extraBusySlots: extraBusySlots)
        return rebuildPreview(date: date, startTime: resolvedStartTime, snapshot: snapshot)
    }

    func availability(date: Date, startTime: Date? = nil) async
        -> (availableMinutes: Int, possibleWorkSessions: Int, possibleSideSessions: Int, possibleDeepSessions: Int) {
        let snapshot = await daySnapshot(date: date, startTime: startTime ?? defaultStartTime(for: date))
        return snapshot.availability
    }

    /// Writes the current preview to the real calendar (excluding long rests), then clears the preview.
    func commit(date: Date) async -> (success: Int, failed: Int, eventIds: [String]) {
        syncCalendarWindow()
        let sessions = engine.projectedSessions.filter { $0.type != .bigRest }
        guard previewMatches(date: date) else {
            engine.schedulingMessage = "Regenerate the schedule for this day before scheduling."
            return (0, sessions.count, [])
        }
        let result = calendar.createSessions(sessions)
        engine.schedulingMessage = result.failed == 0
            ? "Scheduled \(result.success) sessions"
            : "Scheduled \(result.success), failed \(result.failed)"
        engine.sessionsFrozen = false
        await calendar.fetchEvents(for: date)
        engine.projectedSessions = []
        engine.projectedSessionsDate = nil
        return result
    }

    private func previewMatches(date: Date) -> Bool {
        guard let previewDate = engine.projectedSessionsDate else {
            return engine.projectedSessions.isEmpty
        }
        return Calendar.current.isDate(previewDate, inSameDayAs: date)
    }

    /// Deletes SessionFlow-tagged events on the session calendars for the day. Never touches untagged events.
    func deleteSessions(date: Date, scope: DeleteScope) async -> (deleted: Int, failed: Int) {
        syncCalendarWindow()
        let calendars = engine.sessionCalendarDescriptors
        let result: (deleted: Int, failed: Int)
        switch scope {
        case .all:
            result = calendar.deleteSessionEvents(
                for: date, sessionNames: nil, fromCalendars: calendars, requireSessionTag: true
            )
        case .future:
            let cutoff = Calendar.current.isDateInToday(date) ? Date() : Calendar.current.startOfDay(for: date)
            result = calendar.deleteFutureSessionEvents(
                for: date, after: cutoff, sessionNames: nil, fromCalendars: calendars, requireSessionTag: true
            )
        }
        await calendar.fetchEvents(for: date)
        return result
    }

    func moveCommittedEvent(eventId: String, newStart: Date, newEnd: Date) -> Bool {
        calendar.updateEventTime(eventId: eventId, newStart: newStart, newEnd: newEnd)
    }
}
