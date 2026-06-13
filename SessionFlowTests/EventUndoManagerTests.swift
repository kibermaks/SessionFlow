import Foundation
import Testing
@testable import SessionFlow

struct EventUndoManagerTests {
    @Test func scheduleRedoRefreshesNextUndoEventIds() {
        let manager = EventUndoManager()
        let session = scheduledSession(id: UUID(), title: "Focus", start: date(9), end: date(10))

        manager.recordSchedule(EventUndoManager.ScheduleSnapshot(eventIds: ["old-event"], sessions: [session]))

        guard case .schedule(let undoSnapshot) = manager.undo() else {
            Issue.record("Expected schedule undo")
            return
        }
        #expect(undoSnapshot.eventIds == ["old-event"])

        guard case .schedule(let redoSnapshot) = manager.redo() else {
            Issue.record("Expected schedule redo")
            return
        }
        #expect(redoSnapshot.eventIds == ["old-event"])

        manager.updateTopUndoSchedule(EventUndoManager.ScheduleSnapshot(eventIds: ["new-event"], sessions: [session]))

        guard case .schedule(let secondUndoSnapshot) = manager.undo() else {
            Issue.record("Expected second schedule undo")
            return
        }
        #expect(secondUndoSnapshot.eventIds == ["new-event"])
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
