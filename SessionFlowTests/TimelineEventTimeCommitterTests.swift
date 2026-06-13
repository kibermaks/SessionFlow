import Foundation
import Testing
@testable import SessionFlow

struct TimelineEventTimeCommitterTests {
    @Test func unchangedTargetsDoNotWriteFetchOrCreateUndo() {
        let calendar = FakeTimeCommitCalendar()

        let result = TimelineEventTimeCommitter.commit([
            target(id: "event", oldStart: date(9), oldEnd: date(10), newStart: date(9), newEnd: date(10))
        ], calendar: calendar)

        #expect(calendar.updatedEvents.isEmpty)
        #expect(result == TimelineEventTimeCommitter.Result())
    }

    @Test func successfulTargetCreatesUndoAndOptimisticUpdate() {
        let calendar = FakeTimeCommitCalendar()

        let result = TimelineEventTimeCommitter.commit([
            target(id: "event", oldStart: date(9), oldEnd: date(10), newStart: date(10), newEnd: date(11))
        ], calendar: calendar)

        #expect(calendar.updatedEvents.map(\.eventId) == ["event"])
        #expect(result.shouldFetchEvents)
        #expect(result.undoChanges == [
            EventUndoManager.EventTimeChange(
                eventId: "event",
                oldStartTime: date(9),
                oldEndTime: date(10),
                newStartTime: date(10),
                newEndTime: date(11),
                description: "Move Focus"
            )
        ])
        #expect(result.optimisticUpdates == [
            TimelineEventTimeCommitter.EventTimeUpdate(
                eventId: "event",
                newStart: date(10),
                newEnd: date(11)
            )
        ])
    }

    @Test func failedTargetFetchesButDoesNotCreateUndoOrOptimisticUpdate() {
        let calendar = FakeTimeCommitCalendar(failingEventIds: ["event"])

        let result = TimelineEventTimeCommitter.commit([
            target(id: "event", oldStart: date(9), oldEnd: date(10), newStart: date(10), newEnd: date(11))
        ], calendar: calendar)

        #expect(calendar.updatedEvents.map(\.eventId) == ["event"])
        #expect(result.shouldFetchEvents)
        #expect(result.undoChanges.isEmpty)
        #expect(result.optimisticUpdates.isEmpty)
    }

    @Test func groupCommitKeepsOnlySuccessfulChangedTargets() {
        let calendar = FakeTimeCommitCalendar(failingEventIds: ["fail"])

        let result = TimelineEventTimeCommitter.commit([
            target(id: "ok", oldStart: date(9), oldEnd: date(10), newStart: date(10), newEnd: date(11)),
            target(id: "fail", oldStart: date(11), oldEnd: date(12), newStart: date(12), newEnd: date(13)),
            target(id: "same", oldStart: date(14), oldEnd: date(15), newStart: date(14), newEnd: date(15))
        ], calendar: calendar)

        #expect(calendar.updatedEvents.map(\.eventId) == ["ok", "fail"])
        #expect(result.shouldFetchEvents)
        #expect(result.undoChanges.map(\.eventId) == ["ok"])
        #expect(result.optimisticUpdates.map(\.eventId) == ["ok"])
    }

    private func target(
        id: String,
        oldStart: Date,
        oldEnd: Date,
        newStart: Date,
        newEnd: Date
    ) -> TimelineEventTimeCommitter.Target {
        TimelineEventTimeCommitter.Target(
            eventId: id,
            oldStart: oldStart,
            oldEnd: oldEnd,
            newStart: newStart,
            newEnd: newEnd,
            description: "Move Focus"
        )
    }

    private func date(_ hour: Int) -> Date {
        let base = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 13))!
        return base.addingTimeInterval(TimeInterval(hour) * 3_600)
    }
}

private final class FakeTimeCommitCalendar: TimelineEventTimeCommitting {
    let failingEventIds: Set<String>
    private(set) var updatedEvents: [(eventId: String, newStart: Date, newEnd: Date)] = []

    init(failingEventIds: Set<String> = []) {
        self.failingEventIds = failingEventIds
    }

    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool {
        updatedEvents.append((eventId, newStart, newEnd))
        return !failingEventIds.contains(eventId)
    }
}
