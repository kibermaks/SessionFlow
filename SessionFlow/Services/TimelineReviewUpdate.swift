import Foundation

protocol TimelineReviewCalendarApplying: AnyObject {
    func setFeedbackTag(eventId: String, rating: SessionRating) -> Bool
    func clearFeedbackTag(eventId: String) -> Bool
    func setAlignmentTag(eventId: String, alignment: SessionAlignment) -> Bool
    func clearAlignmentTag(eventId: String) -> Bool
}

extension CalendarService: TimelineReviewCalendarApplying {}

enum TimelineReviewUpdate {
    struct FeedbackResult: Equatable {
        let undoChange: EventUndoManager.FeedbackChange
        let updatedNotes: String?
    }

    struct AlignmentResult: Equatable {
        let undoChange: EventUndoManager.AlignmentChange
        let updatedNotes: String?
    }

    static func setFeedback(
        eventId: String,
        currentNotes: String?,
        rating: SessionRating,
        toggleWhenAlreadySelected: Bool = false,
        calendar: TimelineReviewCalendarApplying
    ) -> FeedbackResult? {
        let oldRating = SessionRating.fromNotes(currentNotes)
        let newRating: SessionRating? = oldRating == rating && toggleWhenAlreadySelected ? nil : rating
        guard oldRating != newRating else { return nil }

        let success: Bool
        let updatedNotes: String?
        if let newRating {
            success = calendar.setFeedbackTag(eventId: eventId, rating: newRating)
            updatedNotes = newRating.applyTo(notes: currentNotes)
        } else {
            success = calendar.clearFeedbackTag(eventId: eventId)
            updatedNotes = normalizedNotes(SessionRating.stripFeedbackTags(currentNotes))
        }

        guard success else { return nil }
        return FeedbackResult(
            undoChange: EventUndoManager.FeedbackChange(
                eventId: eventId,
                oldRating: oldRating,
                newRating: newRating
            ),
            updatedNotes: updatedNotes
        )
    }

    static func clearFeedback(
        eventId: String,
        currentNotes: String?,
        calendar: TimelineReviewCalendarApplying
    ) -> FeedbackResult? {
        guard let oldRating = SessionRating.fromNotes(currentNotes) else { return nil }
        return setFeedback(
            eventId: eventId,
            currentNotes: currentNotes,
            rating: oldRating,
            toggleWhenAlreadySelected: true,
            calendar: calendar
        )
    }

    static func setAlignment(
        eventId: String,
        currentNotes: String?,
        alignment: SessionAlignment,
        toggleWhenAlreadySelected: Bool = false,
        calendar: TimelineReviewCalendarApplying
    ) -> AlignmentResult? {
        let oldAlignment = SessionAlignment.fromNotes(currentNotes)
        let newAlignment: SessionAlignment? = oldAlignment == alignment && toggleWhenAlreadySelected ? nil : alignment
        guard oldAlignment != newAlignment else { return nil }

        let success: Bool
        let updatedNotes: String?
        if let newAlignment {
            success = calendar.setAlignmentTag(eventId: eventId, alignment: newAlignment)
            updatedNotes = newAlignment.applyTo(notes: currentNotes)
        } else {
            success = calendar.clearAlignmentTag(eventId: eventId)
            updatedNotes = normalizedNotes(SessionAlignment.stripAlignmentTags(currentNotes))
        }

        guard success else { return nil }
        return AlignmentResult(
            undoChange: EventUndoManager.AlignmentChange(
                eventId: eventId,
                oldAlignment: oldAlignment,
                newAlignment: newAlignment
            ),
            updatedNotes: updatedNotes
        )
    }

    static func clearAlignment(
        eventId: String,
        currentNotes: String?,
        calendar: TimelineReviewCalendarApplying
    ) -> AlignmentResult? {
        guard let oldAlignment = SessionAlignment.fromNotes(currentNotes) else { return nil }
        return setAlignment(
            eventId: eventId,
            currentNotes: currentNotes,
            alignment: oldAlignment,
            toggleWhenAlreadySelected: true,
            calendar: calendar
        )
    }

    static func shouldKeepPopoverOpen(afterNotes notes: String?) -> Bool {
        SessionRating.fromNotes(notes) == nil || SessionAlignment.fromNotes(notes) == nil
    }

    private static func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        return notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
    }
}
