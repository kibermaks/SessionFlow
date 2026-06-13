import Foundation

protocol TimelineUndoCalendarApplying: AnyObject {
    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool
    func deleteEvent(identifier: String) -> Bool
    func restoreEvent(_ snapshot: EventDeleteSnapshot) -> String?
    func createSessions(_ sessions: [ScheduledSession]) -> (success: Int, failed: Int, eventIds: [String])
    func setFeedbackTag(eventId: String, rating: SessionRating) -> Bool
    func clearFeedbackTag(eventId: String) -> Bool
    func setAlignmentTag(eventId: String, alignment: SessionAlignment) -> Bool
    func clearAlignmentTag(eventId: String) -> Bool
    func updateEvent(eventId: String, title: String?, notes: String?, url: URL?, updateURL: Bool) -> Bool
}

extension CalendarService: TimelineUndoCalendarApplying {}

enum TimelineUndoRedoApplier {
    enum Direction: Equatable {
        case undo(hasRemainingSessionChanges: Bool)
        case redo
    }

    struct ScheduleState: Equatable {
        var projectedSessions: [ScheduledSession]
        var sessionsFrozen: Bool
    }

    struct EventTimeUpdate: Equatable {
        let eventId: String
        let newStart: Date
        let newEnd: Date
    }

    enum UndoManagerFollowUp: Equatable {
        case pushRedoForRestoredDelete(original: EventDeleteSnapshot, newEventId: String)
        case pushRedoForRestoredDeleteBatch(originals: [EventDeleteSnapshot], newEventIds: [String])
        case pushRedoForUndoneCreate(EventDeleteSnapshot)
        case updateTopUndoCreate(EventDeleteSnapshot)
        case updateTopUndoSchedule(EventUndoManager.ScheduleSnapshot)
    }

    struct Result: Equatable {
        var optimisticTimeUpdates: [EventTimeUpdate] = []
        var shouldFetchEvents = false
        var selectedSlotRefreshId: String?
        var undoManagerFollowUps: [UndoManagerFollowUp] = []
    }

    static func apply(
        _ change: EventUndoManager.UndoableChange,
        direction: Direction,
        calendar: TimelineUndoCalendarApplying,
        schedule: inout ScheduleState
    ) -> Result {
        switch change {
        case .time(let timeChange):
            return applyTimeChange(timeChange, direction: direction, calendar: calendar, schedule: &schedule)
        case .timeBatch(let items):
            return applyTimeBatch(items, calendar: calendar)
        case .delete(let snapshot):
            return applyDelete(snapshot, direction: direction, calendar: calendar)
        case .deleteBatch(let snapshots):
            return applyDeleteBatch(snapshots, direction: direction, calendar: calendar)
        case .schedule(let snapshot):
            return applySchedule(snapshot, direction: direction, calendar: calendar, schedule: &schedule)
        case .create(let snapshot):
            return applyCreate(snapshot, direction: direction, calendar: calendar)
        case .feedback(let change):
            return applyFeedback(change, calendar: calendar)
        case .alignment(let change):
            return applyAlignment(change, calendar: calendar)
        case .content(let change):
            return applyContent(change, calendar: calendar)
        }
    }

    private static func applyTimeChange(
        _ change: EventUndoManager.EventTimeChange,
        direction: Direction,
        calendar: TimelineUndoCalendarApplying,
        schedule: inout ScheduleState
    ) -> Result {
        guard let sessionId = change.sessionId else {
            guard calendar.updateEventTime(
                eventId: change.eventId,
                newStart: change.newStartTime,
                newEnd: change.newEndTime
            ) else {
                return Result()
            }
            return Result(
                optimisticTimeUpdates: [
                    EventTimeUpdate(
                        eventId: change.eventId,
                        newStart: change.newStartTime,
                        newEnd: change.newEndTime
                    )
                ],
                shouldFetchEvents: true
            )
        }

        switch direction {
        case .undo(let hasRemainingSessionChanges):
            if let snapshot = change.sessionsSnapshot {
                schedule.projectedSessions = snapshot
            } else {
                updateSession(sessionId, in: &schedule.projectedSessions, start: change.newStartTime, end: change.newEndTime)
            }
            if schedule.sessionsFrozen && !hasRemainingSessionChanges {
                schedule.sessionsFrozen = false
            }
        case .redo:
            schedule.sessionsFrozen = true
            if let snapshot = change.postSnapshot {
                schedule.projectedSessions = snapshot
            } else {
                updateSession(sessionId, in: &schedule.projectedSessions, start: change.newStartTime, end: change.newEndTime)
            }
        }

        return Result()
    }

    private static func applyTimeBatch(
        _ changes: [EventUndoManager.EventTimeChange],
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        var result = Result(shouldFetchEvents: true)
        for change in changes {
            if calendar.updateEventTime(eventId: change.eventId, newStart: change.newStartTime, newEnd: change.newEndTime) {
                result.optimisticTimeUpdates.append(EventTimeUpdate(
                    eventId: change.eventId,
                    newStart: change.newStartTime,
                    newEnd: change.newEndTime
                ))
            }
        }
        return result
    }

    private static func applyDelete(
        _ snapshot: EventDeleteSnapshot,
        direction: Direction,
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        switch direction {
        case .undo:
            guard let newId = calendar.restoreEvent(snapshot) else { return Result() }
            return Result(
                shouldFetchEvents: true,
                undoManagerFollowUps: [.pushRedoForRestoredDelete(original: snapshot, newEventId: newId)]
            )
        case .redo:
            return calendar.deleteEvent(identifier: snapshot.eventId)
                ? Result(shouldFetchEvents: true)
                : Result()
        }
    }

    private static func applyDeleteBatch(
        _ snapshots: [EventDeleteSnapshot],
        direction: Direction,
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        switch direction {
        case .undo:
            var newIds: [String] = []
            for snapshot in snapshots {
                if let newId = calendar.restoreEvent(snapshot) {
                    newIds.append(newId)
                }
            }
            guard !newIds.isEmpty else { return Result() }
            return Result(
                shouldFetchEvents: true,
                undoManagerFollowUps: [
                    .pushRedoForRestoredDeleteBatch(
                        originals: Array(snapshots.prefix(newIds.count)),
                        newEventIds: newIds
                    )
                ]
            )
        case .redo:
            var didDelete = false
            for snapshot in snapshots {
                if calendar.deleteEvent(identifier: snapshot.eventId) {
                    didDelete = true
                }
            }
            return didDelete ? Result(shouldFetchEvents: true) : Result()
        }
    }

    private static func applySchedule(
        _ snapshot: EventUndoManager.ScheduleSnapshot,
        direction: Direction,
        calendar: TimelineUndoCalendarApplying,
        schedule: inout ScheduleState
    ) -> Result {
        switch direction {
        case .undo:
            for eventId in snapshot.eventIds {
                _ = calendar.deleteEvent(identifier: eventId)
            }
            schedule.projectedSessions.append(contentsOf: snapshot.sessions)
            schedule.projectedSessions.sort { $0.startTime < $1.startTime }
            schedule.sessionsFrozen = true
            return Result(shouldFetchEvents: true)
        case .redo:
            let createResult = calendar.createSessions(snapshot.sessions)
            guard createResult.success > 0 else { return Result() }
            let scheduledIds = Set(snapshot.sessions.map(\.id))
            schedule.projectedSessions.removeAll { scheduledIds.contains($0.id) }
            return Result(
                shouldFetchEvents: true,
                undoManagerFollowUps: [
                    .updateTopUndoSchedule(EventUndoManager.ScheduleSnapshot(
                        eventIds: createResult.eventIds,
                        sessions: snapshot.sessions
                    ))
                ]
            )
        }
    }

    private static func applyCreate(
        _ snapshot: EventDeleteSnapshot,
        direction: Direction,
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        switch direction {
        case .undo:
            guard calendar.deleteEvent(identifier: snapshot.eventId) else { return Result() }
            return Result(
                shouldFetchEvents: true,
                undoManagerFollowUps: [.pushRedoForUndoneCreate(snapshot)]
            )
        case .redo:
            guard let newId = calendar.restoreEvent(snapshot) else { return Result() }
            return Result(
                shouldFetchEvents: true,
                undoManagerFollowUps: [.updateTopUndoCreate(snapshot.withEventId(newId))]
            )
        }
    }

    private static func applyFeedback(
        _ change: EventUndoManager.FeedbackChange,
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        if let rating = change.newRating {
            _ = calendar.setFeedbackTag(eventId: change.eventId, rating: rating)
        } else {
            _ = calendar.clearFeedbackTag(eventId: change.eventId)
        }
        return Result(shouldFetchEvents: true, selectedSlotRefreshId: change.eventId)
    }

    private static func applyAlignment(
        _ change: EventUndoManager.AlignmentChange,
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        if let alignment = change.newAlignment {
            _ = calendar.setAlignmentTag(eventId: change.eventId, alignment: alignment)
        } else {
            _ = calendar.clearAlignmentTag(eventId: change.eventId)
        }
        return Result(shouldFetchEvents: true, selectedSlotRefreshId: change.eventId)
    }

    private static func applyContent(
        _ change: EventUndoManager.EventContentChange,
        calendar: TimelineUndoCalendarApplying
    ) -> Result {
        let success: Bool
        switch change.change {
        case .title(_, let new):
            success = calendar.updateEvent(eventId: change.eventId, title: new, notes: nil, url: nil, updateURL: false)
        case .notes(_, let new):
            success = calendar.updateEvent(eventId: change.eventId, title: nil, notes: new ?? "", url: nil, updateURL: false)
        case .url(_, let new):
            success = calendar.updateEvent(eventId: change.eventId, title: nil, notes: nil, url: new, updateURL: true)
        }
        return success
            ? Result(shouldFetchEvents: true, selectedSlotRefreshId: change.eventId)
            : Result()
    }

    private static func updateSession(
        _ sessionId: UUID,
        in sessions: inout [ScheduledSession],
        start: Date,
        end: Date
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].startTime = start
        sessions[index].endTime = end
    }
}

private extension EventDeleteSnapshot {
    func withEventId(_ eventId: String) -> EventDeleteSnapshot {
        EventDeleteSnapshot(
            eventId: eventId,
            title: title,
            notes: notes,
            url: url,
            startDate: startDate,
            endDate: endDate,
            calendarIdentifier: calendarIdentifier,
            calendarName: calendarName
        )
    }
}
