import Foundation
import Testing
@testable import SessionFlow

struct TimelineUndoRedoApplierTests {
    @Test func undoScheduleRestoresProjectedSessionsAndDeletesCreatedEvents() {
        let calendar = FakeUndoCalendar()
        let session = scheduledSession(id: UUID(), title: "Focus", start: date(10), end: date(11))
        let earlier = scheduledSession(id: UUID(), title: "Earlier", start: date(9), end: date(10))
        var schedule = TimelineUndoRedoApplier.ScheduleState(projectedSessions: [], sessionsFrozen: false)

        let result = TimelineUndoRedoApplier.apply(
            .schedule(EventUndoManager.ScheduleSnapshot(eventIds: ["event-a", "event-b"], sessions: [session, earlier])),
            direction: .undo(hasRemainingSessionChanges: false),
            calendar: calendar,
            schedule: &schedule
        )

        #expect(calendar.deletedEventIds == ["event-a", "event-b"])
        #expect(schedule.projectedSessions.map(\.title) == ["Earlier", "Focus"])
        #expect(schedule.sessionsFrozen)
        #expect(result.shouldFetchEvents)
        #expect(result.undoManagerFollowUps.isEmpty)
    }

    @Test func redoScheduleCreatesSessionsRemovesThemFromPreviewAndRefreshesUndoStack() {
        let sessionId = UUID()
        let session = scheduledSession(id: sessionId, title: "Focus", start: date(9), end: date(10))
        let other = scheduledSession(id: UUID(), title: "Later", start: date(11), end: date(12))
        let calendar = FakeUndoCalendar(createdEventIds: ["new-event"])
        var schedule = TimelineUndoRedoApplier.ScheduleState(
            projectedSessions: [session, other],
            sessionsFrozen: true
        )

        let result = TimelineUndoRedoApplier.apply(
            .schedule(EventUndoManager.ScheduleSnapshot(eventIds: ["old-event"], sessions: [session])),
            direction: .redo,
            calendar: calendar,
            schedule: &schedule
        )

        #expect(calendar.createdSessions.map(\.id) == [sessionId])
        #expect(schedule.projectedSessions.map(\.id) == [other.id])
        #expect(schedule.sessionsFrozen)
        #expect(result.shouldFetchEvents)
        #expect(result.undoManagerFollowUps == [
            .updateTopUndoSchedule(EventUndoManager.ScheduleSnapshot(eventIds: ["new-event"], sessions: [session]))
        ])
    }

    @Test func undoProjectedSessionTimeUsesSnapshotAndCanUnfreezeLastSessionChange() {
        let calendar = FakeUndoCalendar()
        let id = UUID()
        let current = scheduledSession(id: id, title: "Focus", start: date(10), end: date(11))
        let original = scheduledSession(id: id, title: "Focus", start: date(9), end: date(10))
        var schedule = TimelineUndoRedoApplier.ScheduleState(projectedSessions: [current], sessionsFrozen: true)

        let result = TimelineUndoRedoApplier.apply(
            .time(EventUndoManager.EventTimeChange(
                sessionId: id,
                oldStartTime: date(10),
                oldEndTime: date(11),
                newStartTime: date(9),
                newEndTime: date(10),
                description: "Undo Move Focus",
                sessionsSnapshot: [original],
                postSnapshot: [current]
            )),
            direction: .undo(hasRemainingSessionChanges: false),
            calendar: calendar,
            schedule: &schedule
        )

        #expect(schedule.projectedSessions == [original])
        #expect(!schedule.sessionsFrozen)
        #expect(result == TimelineUndoRedoApplier.Result())
    }

    @Test func eventTimeChangeProducesOptimisticUpdateOnlyWhenCalendarSucceeds() {
        let calendar = FakeUndoCalendar(failingEventIds: ["fail"])
        var schedule = TimelineUndoRedoApplier.ScheduleState(projectedSessions: [], sessionsFrozen: false)

        let success = TimelineUndoRedoApplier.apply(
            .time(EventUndoManager.EventTimeChange(
                eventId: "ok",
                oldStartTime: date(9),
                oldEndTime: date(10),
                newStartTime: date(10),
                newEndTime: date(11),
                description: "Move Focus"
            )),
            direction: .redo,
            calendar: calendar,
            schedule: &schedule
        )

        let failure = TimelineUndoRedoApplier.apply(
            .time(EventUndoManager.EventTimeChange(
                eventId: "fail",
                oldStartTime: date(9),
                oldEndTime: date(10),
                newStartTime: date(10),
                newEndTime: date(11),
                description: "Move Focus"
            )),
            direction: .redo,
            calendar: calendar,
            schedule: &schedule
        )

        #expect(success.optimisticTimeUpdates == [
            TimelineUndoRedoApplier.EventTimeUpdate(eventId: "ok", newStart: date(10), newEnd: date(11))
        ])
        #expect(success.shouldFetchEvents)
        #expect(failure == TimelineUndoRedoApplier.Result())
    }

    @Test func contentChangeRequestsSelectedSlotRefreshAfterSuccessfulUpdate() {
        let calendar = FakeUndoCalendar()
        var schedule = TimelineUndoRedoApplier.ScheduleState(projectedSessions: [], sessionsFrozen: false)

        let result = TimelineUndoRedoApplier.apply(
            .content(EventUndoManager.EventContentChange(
                eventId: "event",
                change: .notes(old: "old", new: nil),
                description: "Edit notes"
            )),
            direction: .redo,
            calendar: calendar,
            schedule: &schedule
        )

        #expect(calendar.updatedEvents.map(\.notes) == [""])
        #expect(result.shouldFetchEvents)
        #expect(result.selectedSlotRefreshId == "event")
    }

    private func scheduledSession(id: UUID, title: String, start: Date, end: Date) -> ScheduledSession {
        ScheduledSession(
            id: id,
            type: .work,
            title: title,
            startTime: start,
            endTime: end,
            calendarName: "Work"
        )
    }

    private func date(_ hour: Int) -> Date {
        let base = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 13))!
        return base.addingTimeInterval(TimeInterval(hour) * 3_600)
    }
}

private final class FakeUndoCalendar: TimelineUndoCalendarApplying {
    let createdEventIds: [String]
    let failingEventIds: Set<String>

    private(set) var movedEvents: [(id: String, start: Date, end: Date)] = []
    private(set) var deletedEventIds: [String] = []
    private(set) var restoredSnapshots: [EventDeleteSnapshot] = []
    private(set) var createdSessions: [ScheduledSession] = []
    private(set) var feedbackUpdates: [(eventId: String, rating: SessionRating?)] = []
    private(set) var alignmentUpdates: [(eventId: String, alignment: SessionAlignment?)] = []
    private(set) var updatedEvents: [(eventId: String, title: String?, notes: String?, url: URL?, updateURL: Bool)] = []

    init(createdEventIds: [String] = [], failingEventIds: Set<String> = []) {
        self.createdEventIds = createdEventIds
        self.failingEventIds = failingEventIds
    }

    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool {
        guard !failingEventIds.contains(eventId) else { return false }
        movedEvents.append((eventId, newStart, newEnd))
        return true
    }

    func deleteEvent(identifier: String) -> Bool {
        guard !failingEventIds.contains(identifier) else { return false }
        deletedEventIds.append(identifier)
        return true
    }

    func restoreEvent(_ snapshot: EventDeleteSnapshot) -> String? {
        guard !failingEventIds.contains(snapshot.eventId) else { return nil }
        restoredSnapshots.append(snapshot)
        return "restored-\(restoredSnapshots.count)"
    }

    func createSessions(_ sessions: [ScheduledSession]) -> (success: Int, failed: Int, eventIds: [String]) {
        createdSessions.append(contentsOf: sessions)
        return (createdEventIds.count, max(0, sessions.count - createdEventIds.count), createdEventIds)
    }

    func setFeedbackTag(eventId: String, rating: SessionRating) -> Bool {
        feedbackUpdates.append((eventId, rating))
        return true
    }

    func clearFeedbackTag(eventId: String) -> Bool {
        feedbackUpdates.append((eventId, nil))
        return true
    }

    func setAlignmentTag(eventId: String, alignment: SessionAlignment) -> Bool {
        alignmentUpdates.append((eventId, alignment))
        return true
    }

    func clearAlignmentTag(eventId: String) -> Bool {
        alignmentUpdates.append((eventId, nil))
        return true
    }

    func updateEvent(eventId: String, title: String?, notes: String?, url: URL?, updateURL: Bool) -> Bool {
        guard !failingEventIds.contains(eventId) else { return false }
        updatedEvents.append((eventId, title, notes, url, updateURL))
        return true
    }
}
