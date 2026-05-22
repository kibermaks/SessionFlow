import Foundation
import SwiftUI

/// Snapshot for delete/restore. eventId is the calendar event identifier.
/// When undoing a delete, we restore from title/notes/url/dates/calendar.
/// When redoing a delete, we delete the event by eventId.
struct EventDeleteSnapshot: Equatable {
    let eventId: String
    let title: String
    let notes: String?
    let url: URL?
    let startDate: Date
    let endDate: Date
    let calendarIdentifier: String?
    let calendarName: String
}

/// Tracks move/resize/delete operations on calendar events for undo/redo.
/// Custom class to avoid conflicts with SwiftUI's text field UndoManager.
class EventUndoManager: ObservableObject {

    /// Snapshot for undoing a batch schedule (create → delete on undo, restore on redo).
    struct ScheduleSnapshot: Equatable {
        let eventIds: [String]
        let sessions: [ScheduledSession]  // projected sessions to restore on undo
    }

    struct FeedbackChange: Equatable {
        let eventId: String
        let oldRating: SessionRating?
        let newRating: SessionRating?
    }

    struct EventContentChange: Equatable {
        enum FieldChange: Equatable {
            case title(old: String, new: String)
            case notes(old: String?, new: String?)
            case url(old: URL?, new: URL?)
        }
        let eventId: String
        let change: FieldChange
        let description: String
    }

    enum UndoableChange: Equatable {
        case time(EventTimeChange)
        case timeBatch([EventTimeChange])  // atomic multi-event move (e.g. group drag)
        case delete(EventDeleteSnapshot)
        case deleteBatch([EventDeleteSnapshot])  // atomic multi-event delete
        case schedule(ScheduleSnapshot)
        case create(EventDeleteSnapshot)  // undo = delete, redo = restore
        case feedback(FeedbackChange)
        case content(EventContentChange)
    }

    struct EventTimeChange: Equatable {
        let eventId: String
        let sessionId: UUID?  // non-nil for projected session changes
        let oldStartTime: Date
        let oldEndTime: Date
        let newStartTime: Date
        let newEndTime: Date
        let description: String  // e.g. "Move Meeting" or "Resize Meeting"
        /// Full snapshot of all projected sessions before this change (for displacement undo).
        let sessionsSnapshot: [ScheduledSession]?
        /// Full snapshot of all projected sessions after this change (for displacement redo).
        let postSnapshot: [ScheduledSession]?

        init(eventId: String, oldStartTime: Date, oldEndTime: Date, newStartTime: Date, newEndTime: Date, description: String) {
            self.eventId = eventId
            self.sessionId = nil
            self.oldStartTime = oldStartTime
            self.oldEndTime = oldEndTime
            self.newStartTime = newStartTime
            self.newEndTime = newEndTime
            self.description = description
            self.sessionsSnapshot = nil
            self.postSnapshot = nil
        }

        init(sessionId: UUID, oldStartTime: Date, oldEndTime: Date, newStartTime: Date, newEndTime: Date, description: String, sessionsSnapshot: [ScheduledSession]? = nil, postSnapshot: [ScheduledSession]? = nil) {
            self.eventId = ""
            self.sessionId = sessionId
            self.oldStartTime = oldStartTime
            self.oldEndTime = oldEndTime
            self.newStartTime = newStartTime
            self.newEndTime = newEndTime
            self.description = description
            self.sessionsSnapshot = sessionsSnapshot
            self.postSnapshot = postSnapshot
        }
    }

    /// Whether the undo stack contains any projected session changes (for unfreeze tracking)
    var hasSessionChanges: Bool {
        undoStack.contains { change in
            if case .time(let tc) = change { return tc.sessionId != nil }
            return false
        }
    }

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [UndoableChange] = []
    private var redoStack: [UndoableChange] = []
    private let maxStackSize = 50

    func record(_ change: EventTimeChange) {
        undoStack.append(.time(change))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateState()
    }

    /// Record a batch of simultaneous time changes (group drag of multiple events).
    /// Atomically undone/redone as a single user action.
    func recordBatch(_ changes: [EventTimeChange]) {
        guard !changes.isEmpty else { return }
        if changes.count == 1 {
            record(changes[0])
            return
        }
        undoStack.append(.timeBatch(changes))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateState()
    }

    func recordDelete(_ snapshot: EventDeleteSnapshot) {
        undoStack.append(.delete(snapshot))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateState()
    }

    func recordDeleteBatch(_ snapshots: [EventDeleteSnapshot]) {
        guard !snapshots.isEmpty else { return }
        if snapshots.count == 1 { recordDelete(snapshots[0]); return }
        undoStack.append(.deleteBatch(snapshots))
        if undoStack.count > maxStackSize { undoStack.removeFirst() }
        redoStack.removeAll()
        updateState()
    }

    /// Call after undoing a deleteBatch. Pushes redo entry with the new event ids.
    func pushRedoForRestoredDeleteBatch(originals: [EventDeleteSnapshot], newEventIds: [String]) {
        let updated = zip(originals, newEventIds).map { orig, newId in
            EventDeleteSnapshot(eventId: newId, title: orig.title, notes: orig.notes, url: orig.url,
                                startDate: orig.startDate, endDate: orig.endDate,
                                calendarIdentifier: orig.calendarIdentifier, calendarName: orig.calendarName)
        }
        redoStack.append(.deleteBatch(updated))
        updateState()
    }

    func recordCreate(_ snapshot: EventDeleteSnapshot) {
        undoStack.append(.create(snapshot))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateState()
    }

    func recordFeedback(_ change: FeedbackChange) {
        undoStack.append(.feedback(change))
        if undoStack.count > maxStackSize { undoStack.removeFirst() }
        redoStack.removeAll()
        updateState()
    }

    func recordContent(_ change: EventContentChange) {
        undoStack.append(.content(change))
        if undoStack.count > maxStackSize { undoStack.removeFirst() }
        redoStack.removeAll()
        updateState()
    }

    func recordSchedule(_ snapshot: ScheduleSnapshot) {
        undoStack.append(.schedule(snapshot))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        updateState()
    }

    /// Returns the change to apply for undo, or nil if stack is empty.
    func undo() -> UndoableChange? {
        guard let change = undoStack.popLast() else { return nil }
        switch change {
        case .time:
            redoStack.append(change)
        case .timeBatch:
            redoStack.append(change)
        case .delete:
            break  // Caller will push redo after restore (needs new eventId)
        case .deleteBatch:
            break  // Caller will push redo after restore (needs new eventIds)
        case .schedule:
            redoStack.append(change)
        case .create:
            break  // Caller will push redo after delete (needs new eventId after re-create)
        case .feedback:
            redoStack.append(change)
        case .content:
            redoStack.append(change)
        }
        updateState()
        switch change {
        case .time(let tc):
            if let sid = tc.sessionId {
                return .time(EventTimeChange(
                    sessionId: sid,
                    oldStartTime: tc.newStartTime,
                    oldEndTime: tc.newEndTime,
                    newStartTime: tc.oldStartTime,
                    newEndTime: tc.oldEndTime,
                    description: "Undo \(tc.description)",
                    sessionsSnapshot: tc.sessionsSnapshot,
                    postSnapshot: tc.postSnapshot
                ))
            }
            return .time(EventTimeChange(
                eventId: tc.eventId,
                oldStartTime: tc.newStartTime,
                oldEndTime: tc.newEndTime,
                newStartTime: tc.oldStartTime,
                newEndTime: tc.oldEndTime,
                description: "Undo \(tc.description)"
            ))
        case .timeBatch(let items):
            let inverted = items.map { tc in
                EventTimeChange(
                    eventId: tc.eventId,
                    oldStartTime: tc.newStartTime,
                    oldEndTime: tc.newEndTime,
                    newStartTime: tc.oldStartTime,
                    newEndTime: tc.oldEndTime,
                    description: "Undo \(tc.description)"
                )
            }
            return .timeBatch(inverted)
        case .delete(let snap):
            return .delete(snap)
        case .deleteBatch(let snaps):
            return .deleteBatch(snaps)
        case .schedule(let snap):
            return .schedule(snap)
        case .create(let snap):
            return .create(snap)
        case .feedback(let fc):
            return .feedback(FeedbackChange(eventId: fc.eventId, oldRating: fc.newRating, newRating: fc.oldRating))
        case .content(let cc):
            let inverted: EventContentChange.FieldChange
            switch cc.change {
            case .title(let old, let new):
                inverted = .title(old: new, new: old)
            case .notes(let old, let new):
                inverted = .notes(old: new, new: old)
            case .url(let old, let new):
                inverted = .url(old: new, new: old)
            }
            return .content(EventContentChange(eventId: cc.eventId, change: inverted, description: "Undo \(cc.description)"))
        }
    }

    /// Call after undoing a delete (restoring event). Pushes redo entry with the new event id.
    func pushRedoForRestoredDelete(original: EventDeleteSnapshot, newEventId: String) {
        redoStack.append(.delete(EventDeleteSnapshot(
            eventId: newEventId,
            title: original.title,
            notes: original.notes,
            url: original.url,
            startDate: original.startDate,
            endDate: original.endDate,
            calendarIdentifier: original.calendarIdentifier,
            calendarName: original.calendarName
        )))
        updateState()
    }

    /// Call after undoing a create (deleting event). Pushes redo entry so re-creation is possible.
    func pushRedoForUndoneCreate(_ snapshot: EventDeleteSnapshot) {
        redoStack.append(.create(snapshot))
        updateState()
    }

    /// After undoing a schedule, caller provides new event IDs from re-creating sessions.
    func pushRedoForScheduleUndo(_ snapshot: ScheduleSnapshot) {
        // Replace the redo entry with updated event IDs
        if let idx = redoStack.lastIndex(where: {
            if case .schedule = $0 { return true }
            return false
        }) {
            redoStack[idx] = .schedule(snapshot)
        }
        updateState()
    }

    /// Returns the change to re-apply, or nil if stack is empty.
    func redo() -> UndoableChange? {
        guard let change = redoStack.popLast() else { return nil }
        undoStack.append(change)
        updateState()
        switch change {
        case .time:
            return change
        case .timeBatch:
            return change
        case .delete(let snap):
            return .delete(snap)
        case .deleteBatch(let snaps):
            return .deleteBatch(snaps)
        case .schedule(let snap):
            return .schedule(snap)
        case .create(let snap):
            return .create(snap)
        case .feedback:
            return change
        case .content:
            return change
        }
    }

    /// After redoing a create, update the undo stack's top `.create` entry with the new event ID.
    func updateTopUndoCreateId(_ snapshot: EventDeleteSnapshot) {
        if let idx = undoStack.lastIndex(where: {
            if case .create = $0 { return true }
            return false
        }) {
            undoStack[idx] = .create(snapshot)
        }
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateState()
    }

    private func updateState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
