import Foundation
import Testing
@testable import SessionFlow

struct TimelineReviewUpdateTests {
    @Test func settingFeedbackWritesCalendarAndReturnsUndoAndOptimisticNotes() {
        let calendar = FakeReviewCalendar()
        let notes = "#work Deep work \(SessionRating.partial.tag) \(SessionAlignment.direct.tag)"

        let result = TimelineReviewUpdate.setFeedback(
            eventId: "event",
            currentNotes: notes,
            rating: .completed,
            calendar: calendar
        )

        #expect(calendar.feedbackUpdates.map(\.eventId) == ["event"])
        #expect(calendar.feedbackUpdates.map(\.rating) == [.completed])
        #expect(result == TimelineReviewUpdate.FeedbackResult(
            undoChange: EventUndoManager.FeedbackChange(
                eventId: "event",
                oldRating: .partial,
                newRating: .completed
            ),
            updatedNotes: "#work Deep work \(SessionAlignment.direct.tag) \(SessionRating.completed.tag)"
        ))
    }

    @Test func feedbackOnlyTogglesOffWhenRequested() {
        let selectedAgain = FakeReviewCalendar()
        let toggledOff = FakeReviewCalendar()
        let notes = "#work Deep work \(SessionRating.completed.tag)"

        let noChange = TimelineReviewUpdate.setFeedback(
            eventId: "event",
            currentNotes: notes,
            rating: .completed,
            calendar: selectedAgain
        )
        let removed = TimelineReviewUpdate.setFeedback(
            eventId: "event",
            currentNotes: notes,
            rating: .completed,
            toggleWhenAlreadySelected: true,
            calendar: toggledOff
        )

        #expect(noChange == nil)
        #expect(selectedAgain.feedbackUpdates.isEmpty)
        #expect(toggledOff.feedbackUpdates.map(\.eventId) == ["event"])
        #expect(toggledOff.feedbackUpdates.map(\.rating) == [nil])
        #expect(removed == TimelineReviewUpdate.FeedbackResult(
            undoChange: EventUndoManager.FeedbackChange(
                eventId: "event",
                oldRating: .completed,
                newRating: nil
            ),
            updatedNotes: "#work Deep work"
        ))
    }

    @Test func clearFeedbackNoOpsWhenNoFeedbackTagExists() {
        let calendar = FakeReviewCalendar()

        let result = TimelineReviewUpdate.clearFeedback(
            eventId: "event",
            currentNotes: "#work Deep work",
            calendar: calendar
        )

        #expect(result == nil)
        #expect(calendar.feedbackUpdates.isEmpty)
    }

    @Test func settingAlignmentWritesCalendarAndPreservesFeedbackTagInOptimisticNotes() {
        let calendar = FakeReviewCalendar()
        let notes = "#work Deep work \(SessionRating.completed.tag) \(SessionAlignment.support.tag)"

        let result = TimelineReviewUpdate.setAlignment(
            eventId: "event",
            currentNotes: notes,
            alignment: .direct,
            calendar: calendar
        )

        #expect(calendar.alignmentUpdates.map(\.eventId) == ["event"])
        #expect(calendar.alignmentUpdates.map(\.alignment) == [.direct])
        #expect(result == TimelineReviewUpdate.AlignmentResult(
            undoChange: EventUndoManager.AlignmentChange(
                eventId: "event",
                oldAlignment: .support,
                newAlignment: .direct
            ),
            updatedNotes: "#work Deep work \(SessionRating.completed.tag) \(SessionAlignment.direct.tag)"
        ))
    }

    @Test func failedCalendarWriteProducesNoUndoOrOptimisticNotes() {
        let calendar = FakeReviewCalendar(failingEventIds: ["event"])

        let result = TimelineReviewUpdate.setAlignment(
            eventId: "event",
            currentNotes: "#work Deep work \(SessionAlignment.support.tag)",
            alignment: .direct,
            calendar: calendar
        )

        #expect(calendar.alignmentUpdates.map(\.eventId) == ["event"])
        #expect(calendar.alignmentUpdates.map(\.alignment) == [.direct])
        #expect(result == nil)
    }

    @Test func popoverStaysOpenUntilBothReviewAxesArePresent() {
        #expect(TimelineReviewUpdate.shouldKeepPopoverOpen(afterNotes: "#work \(SessionRating.completed.tag)"))
        #expect(TimelineReviewUpdate.shouldKeepPopoverOpen(afterNotes: "#work \(SessionAlignment.direct.tag)"))
        #expect(!TimelineReviewUpdate.shouldKeepPopoverOpen(
            afterNotes: "#work \(SessionRating.completed.tag) \(SessionAlignment.direct.tag)"
        ))
    }
}

private final class FakeReviewCalendar: TimelineReviewCalendarApplying {
    let failingEventIds: Set<String>
    private(set) var feedbackUpdates: [(eventId: String, rating: SessionRating?)] = []
    private(set) var alignmentUpdates: [(eventId: String, alignment: SessionAlignment?)] = []

    init(failingEventIds: Set<String> = []) {
        self.failingEventIds = failingEventIds
    }

    func setFeedbackTag(eventId: String, rating: SessionRating) -> Bool {
        feedbackUpdates.append((eventId, rating))
        return !failingEventIds.contains(eventId)
    }

    func clearFeedbackTag(eventId: String) -> Bool {
        feedbackUpdates.append((eventId, nil))
        return !failingEventIds.contains(eventId)
    }

    func setAlignmentTag(eventId: String, alignment: SessionAlignment) -> Bool {
        alignmentUpdates.append((eventId, alignment))
        return !failingEventIds.contains(eventId)
    }

    func clearAlignmentTag(eventId: String) -> Bool {
        alignmentUpdates.append((eventId, nil))
        return !failingEventIds.contains(eventId)
    }
}
