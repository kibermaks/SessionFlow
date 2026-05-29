import Foundation

/// The subset of `CalendarService` operations the MCP agent layer depends on. `CalendarService`
/// conforms as-is; tests substitute a fake so no test ever writes to the real EventKit store.
protocol CalendarWriting: AnyObject {
    var scheduleEndHour: Int { get set }

    func fetchEvents(for date: Date) async
    func busySlotsForFetchedDate(_ date: Date) -> [BusyTimeSlot]
    func hasPlanningSession(for date: Date, planningEventName: String) -> Bool
    func countExistingSessions(
        for date: Date,
        workCalendar: CalendarDescriptor,
        sideCalendar: CalendarDescriptor,
        deepConfig: DeepSessionConfig?
    ) -> (work: Int, side: Int, deep: Int, titles: Set<String>)
    func createSessions(_ sessions: [ScheduledSession]) -> (success: Int, failed: Int, eventIds: [String])
    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool
    func deleteSessionEvents(
        for date: Date,
        sessionNames: [String]?,
        fromCalendars calendarsToDelete: [CalendarDescriptor],
        requireSessionTag: Bool
    ) -> (deleted: Int, failed: Int)
    func deleteFutureSessionEvents(
        for date: Date,
        after cutoffTime: Date,
        sessionNames: [String]?,
        fromCalendars calendarsToDelete: [CalendarDescriptor],
        requireSessionTag: Bool
    ) -> (deleted: Int, failed: Int)
}

extension CalendarService: CalendarWriting {}
