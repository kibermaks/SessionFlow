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

    enum UndoableChange: Equatable {
        case time(EventTimeChange)
        case delete(EventDeleteSnapshot)
        case schedule(ScheduleSnapshot)
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

    func recordDelete(_ snapshot: EventDeleteSnapshot) {
        undoStack.append(.delete(snapshot))
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
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
        case .delete:
            break  // Caller will push redo after restore (needs new eventId)
        case .schedule:
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
        case .delete(let snap):
            return .delete(snap)
        case .schedule(let snap):
            return .schedule(snap)
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
        case .delete(let snap):
            return .delete(snap)
        case .schedule(let snap):
            return .schedule(snap)
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
