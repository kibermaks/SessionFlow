import Foundation

struct TimelineProjectedSessionDrag {
    struct CommitPlan: Equatable {
        let sessionId: UUID
        let sessions: [ScheduledSession]
        let draggedStart: Date
        let draggedEnd: Date
        let originalStart: Date
        let originalEnd: Date
        let sessionsSnapshot: [ScheduledSession]?

        func undoChange(description: String, postSnapshot: [ScheduledSession]) -> EventUndoManager.EventTimeChange {
            EventUndoManager.EventTimeChange(
                sessionId: sessionId,
                oldStartTime: originalStart,
                oldEndTime: originalEnd,
                newStartTime: draggedStart,
                newEndTime: draggedEnd,
                description: description,
                sessionsSnapshot: sessionsSnapshot,
                postSnapshot: postSnapshot
            )
        }
    }

    enum CommitDecision: Equatable {
        case restore([ScheduledSession]?)
        case commit(CommitPlan)
    }

    private(set) var sessionsSnapshot: [ScheduledSession]?

    var hasSnapshot: Bool {
        sessionsSnapshot != nil
    }

    mutating func begin(with sessions: [ScheduledSession]) {
        sessionsSnapshot = sessions
    }

    mutating func reset() {
        sessionsSnapshot = nil
    }

    func sessionsForDisplacementPass() -> [ScheduledSession]? {
        sessionsSnapshot
    }

    func prepareCommit(
        for session: ScheduledSession,
        previewStart: Date?,
        previewEnd: Date?,
        currentSessions: [ScheduledSession]
    ) -> CommitDecision {
        guard let previewStart, let previewEnd else {
            return .restore(sessionsSnapshot)
        }
        guard previewStart != session.startTime || previewEnd != session.endTime else {
            return .restore(sessionsSnapshot)
        }

        var sessions = sessionsSnapshot ?? currentSessions
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
            return .restore(sessionsSnapshot)
        }

        sessions[index].startTime = previewStart
        sessions[index].endTime = previewEnd

        return .commit(CommitPlan(
            sessionId: session.id,
            sessions: sessions,
            draggedStart: previewStart,
            draggedEnd: previewEnd,
            originalStart: session.startTime,
            originalEnd: session.endTime,
            sessionsSnapshot: sessionsSnapshot
        ))
    }
}
