import Foundation
import Testing
@testable import SessionFlow

struct TimelineProjectedSessionDragTests {
    @Test func beginAndResetManageSnapshot() {
        var drag = TimelineProjectedSessionDrag()
        let sessions = [session(id: UUID(), title: "A", start: date(9), end: date(10))]

        drag.begin(with: sessions)

        #expect(drag.hasSnapshot)
        #expect(drag.sessionsForDisplacementPass()?.map(\.title) == ["A"])

        drag.reset()

        #expect(!drag.hasSnapshot)
        #expect(drag.sessionsForDisplacementPass() == nil)
    }

    @Test func prepareCommitRestoresSnapshotWhenPreviewIsMissingOrUnchanged() {
        var drag = TimelineProjectedSessionDrag()
        let id = UUID()
        let original = session(id: id, title: "A", start: date(9), end: date(10))
        drag.begin(with: [original])

        let missing = drag.prepareCommit(
            for: original,
            previewStart: nil,
            previewEnd: date(10),
            currentSessions: []
        )
        #expect(missing == .restore([original]))

        let unchanged = drag.prepareCommit(
            for: original,
            previewStart: date(9),
            previewEnd: date(10),
            currentSessions: []
        )
        #expect(unchanged == .restore([original]))
    }

    @Test func prepareCommitAppliesPreviewToSnapshotAndBuildsUndoChange() {
        var drag = TimelineProjectedSessionDrag()
        let movingId = UUID()
        let otherId = UUID()
        let moving = session(id: movingId, title: "Move Me", start: date(9), end: date(10))
        let other = session(id: otherId, title: "Other", start: date(11), end: date(12))
        let snapshot = [moving, other]
        drag.begin(with: snapshot)

        let decision = drag.prepareCommit(
            for: moving,
            previewStart: date(10),
            previewEnd: date(11),
            currentSessions: []
        )

        guard case .commit(let plan) = decision else {
            Issue.record("Expected commit plan")
            return
        }

        #expect(plan.sessions.map(\.id) == [movingId, otherId])
        #expect(plan.sessions[0].startTime == date(10))
        #expect(plan.sessions[0].endTime == date(11))
        #expect(plan.sessions[1].startTime == date(11))

        let post = [
            session(id: movingId, title: "Move Me", start: date(10), end: date(11)),
            session(id: otherId, title: "Other", start: date(12), end: date(13))
        ]
        let undo = plan.undoChange(description: "Move Move Me", postSnapshot: post)

        #expect(undo.sessionId == movingId)
        #expect(undo.oldStartTime == date(9))
        #expect(undo.newStartTime == date(10))
        #expect(undo.description == "Move Move Me")
        #expect(undo.sessionsSnapshot == snapshot)
        #expect(undo.postSnapshot == post)
    }

    @Test func prepareCommitFallsBackToCurrentSessionsWhenSnapshotIsMissing() {
        let drag = TimelineProjectedSessionDrag()
        let id = UUID()
        let original = session(id: id, title: "A", start: date(9), end: date(10))

        let decision = drag.prepareCommit(
            for: original,
            previewStart: date(10),
            previewEnd: date(11),
            currentSessions: [original]
        )

        guard case .commit(let plan) = decision else {
            Issue.record("Expected commit plan")
            return
        }

        #expect(plan.sessions.first?.startTime == date(10))
        #expect(plan.sessionsSnapshot == nil)
    }

    @Test func prepareCommitRestoresSnapshotWhenSessionIsMissing() {
        var drag = TimelineProjectedSessionDrag()
        let original = session(id: UUID(), title: "A", start: date(9), end: date(10))
        let snapshot = [session(id: UUID(), title: "Other", start: date(11), end: date(12))]
        drag.begin(with: snapshot)

        let decision = drag.prepareCommit(
            for: original,
            previewStart: date(10),
            previewEnd: date(11),
            currentSessions: [original]
        )

        #expect(decision == .restore(snapshot))
    }

    private func session(id: UUID, title: String, start: Date, end: Date) -> ScheduledSession {
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
