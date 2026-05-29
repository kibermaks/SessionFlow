import Foundation

enum DeleteScope: String {
    case all
    case future
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

    private func workSideDescriptors() -> (work: CalendarDescriptor, side: CalendarDescriptor) {
        (
            CalendarDescriptor(name: engine.workCalendarName, identifier: engine.workCalendarIdentifier),
            CalendarDescriptor(name: engine.sideCalendarName, identifier: engine.sideCalendarIdentifier)
        )
    }

    private func sessionCalendars() -> [CalendarDescriptor] {
        var calendars: [CalendarDescriptor] = [
            CalendarDescriptor(name: engine.workCalendarName, identifier: engine.workCalendarIdentifier),
            CalendarDescriptor(name: engine.sideCalendarName, identifier: engine.sideCalendarIdentifier),
        ]
        if engine.deepSessionConfig.enabled {
            calendars.append(CalendarDescriptor(
                name: engine.deepSessionConfig.calendarName,
                identifier: engine.deepSessionConfig.calendarIdentifier
            ))
        }
        var unique: [CalendarDescriptor] = []
        for descriptor in calendars {
            let duplicate = unique.contains {
                ($0.identifier != nil && $0.identifier == descriptor.identifier) ||
                ($0.identifier == nil && $0.name == descriptor.name)
            }
            if !duplicate { unique.append(descriptor) }
        }
        return unique
    }

    /// Rebuilds the in-app preview (`engine.projectedSessions`) for the given day. No calendar writes.
    @discardableResult
    func regeneratePreview(date: Date, startTime: Date? = nil, extraBusySlots: [BusyTimeSlot] = []) async -> [ScheduledSession] {
        syncCalendarWindow()
        await calendar.fetchEvents(for: date)
        let busy = calendar.busySlotsForFetchedDate(date) + extraBusySlots
        let planningExists = calendar.hasPlanningSession(for: date, planningEventName: "Planning")
        let (work, side) = workSideDescriptors()
        let existing = calendar.countExistingSessions(
            for: date, workCalendar: work, sideCalendar: side, deepConfig: engine.deepSessionConfig
        )
        _ = engine.generateSchedule(
            startTime: startTime ?? defaultStartTime(for: date),
            baseDate: date,
            busySlots: busy,
            includePlanning: !planningExists,
            existingSessions: (work: existing.work, side: existing.side, deep: existing.deep),
            existingTitles: existing.titles
        )
        return engine.projectedSessions
    }

    func availability(date: Date, startTime: Date? = nil) async
        -> (availableMinutes: Int, possibleWorkSessions: Int, possibleSideSessions: Int, possibleDeepSessions: Int) {
        syncCalendarWindow()
        await calendar.fetchEvents(for: date)
        let busy = calendar.busySlotsForFetchedDate(date)
        return engine.calculateAvailability(
            startTime: startTime ?? defaultStartTime(for: date), baseDate: date, busySlots: busy
        )
    }

    /// Writes the current preview to the real calendar (excluding long rests), then clears the preview.
    func commit(date: Date) async -> (success: Int, failed: Int, eventIds: [String]) {
        syncCalendarWindow()
        let sessions = engine.projectedSessions.filter { $0.type != .bigRest }
        let result = calendar.createSessions(sessions)
        engine.schedulingMessage = result.failed == 0
            ? "Scheduled \(result.success) sessions"
            : "Scheduled \(result.success), failed \(result.failed)"
        engine.sessionsFrozen = false
        await calendar.fetchEvents(for: date)
        engine.projectedSessions = []
        return result
    }

    /// Deletes SessionFlow-tagged events on the session calendars for the day. Never touches untagged events.
    func deleteSessions(date: Date, scope: DeleteScope) async -> (deleted: Int, failed: Int) {
        syncCalendarWindow()
        let calendars = sessionCalendars()
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
