import Foundation
import Testing
@testable import SessionFlow

struct TimelineEventContentTests {
    @Test func blockDisplayNotesRemoveSessionFlowMetadataAndManagedSections() {
        let notes = HarshModeSessionNotes.applyingGoals(
            ["Ship paid work"],
            to: "#side Client #workout #planned #flowflexible \(SessionRating.completed.tag) \(SessionAlignment.support.tag)"
        )

        #expect(TimelineEventContent.blockDisplayNotes(from: notes) == "Client #workout #planned")
    }

    @Test func detailEditableNotesPreserveOwnershipTagsButHideSystemMetadata() {
        let notes = "#work Client #workout #flowfixed \(SessionRating.completed.tag) \(SessionAlignment.direct.tag)"

        #expect(TimelineEventContent.detailEditableNotes(from: notes) == "#work Client #workout")
    }

    @Test func notesUpdatePreservesReviewTagsWhenSavingEditedNotes() {
        let update = TimelineEventContent.notesUpdate(
            editedText: "#work Edited notes",
            originalText: "#work Original notes",
            existingNotes: "#work Original notes \(SessionRating.completed.tag) \(SessionAlignment.strategic.tag)",
            isFlowFlexible: true
        )

        #expect(update == TimelineEventContent.NotesUpdate(
            notesToSave: "#work Edited notes \(SessionRating.completed.tag) \(SessionAlignment.strategic.tag)",
            oldNotesForUndo: "#work Original notes"
        ))
    }

    @Test func notesUpdateAddsFlexibleTagWhenEditedNotesNoLongerContainOwnershipTag() {
        let update = TimelineEventContent.notesUpdate(
            editedText: "Edited external notes",
            originalText: "#work Original notes",
            existingNotes: "#work Original notes \(SessionRating.completed.tag)",
            isFlowFlexible: true
        )

        #expect(update?.notesToSave == "Edited external notes \(SessionRating.completed.tag) #flowflexible")
    }

    @Test func notesUpdatePreservesFixedTagForFixedSessionFlowOwnedNotes() {
        let update = TimelineEventContent.notesUpdate(
            editedText: "#work Edited notes",
            originalText: "#work Original notes",
            existingNotes: "#work Original notes \(SessionRating.partial.tag)",
            isFlowFlexible: false
        )

        #expect(update == TimelineEventContent.NotesUpdate(
            notesToSave: "#work Edited notes \(SessionRating.partial.tag) #flowfixed",
            oldNotesForUndo: "#work Original notes #flowfixed"
        ))
    }

    @Test func notesUpdateReturnsNilWhenEditableTextDidNotChange() {
        #expect(TimelineEventContent.notesUpdate(
            editedText: "Same notes",
            originalText: "Same notes",
            existingNotes: "Same notes \(SessionRating.completed.tag)",
            isFlowFlexible: true
        ) == nil)
    }

    @Test func urlUpdateNormalizesMissingSchemeAndEncodesSpaces() {
        let update = TimelineEventContent.urlUpdate(
            editedText: "example.com/path with spaces",
            originalText: ""
        )

        #expect(update?.urlToSave?.absoluteString == "https://example.com/path%20with%20spaces")
        #expect(update?.oldURLForUndo == nil)
    }

    @Test func urlUpdateReturnsNilWhenNormalizedComparisonTextDidNotChange() {
        #expect(TimelineEventContent.urlUpdate(
            editedText: "https://example.com",
            originalText: "https://example.com"
        ) == nil)
    }

    @Test func urlUpdateClearsExistingURL() {
        let update = TimelineEventContent.urlUpdate(
            editedText: "",
            originalText: "https://example.com"
        )

        #expect(update?.urlToSave == nil)
        #expect(update?.oldURLForUndo?.absoluteString == "https://example.com")
    }

    @Test func feedbackAndAlignmentVisibilityPolicyIsCentralized() {
        let now = Date(timeIntervalSince1970: 1_800)
        let past = Date(timeIntervalSince1970: 1_200)
        let future = Date(timeIntervalSince1970: 2_400)

        #expect(TimelineEventContent.showsFeedbackBadge(
            eventEnd: past,
            now: now,
            awarenessEnabled: true,
            productivityEnabled: true
        ))
        #expect(!TimelineEventContent.showsFeedbackBadge(
            eventEnd: future,
            now: now,
            awarenessEnabled: true,
            productivityEnabled: true
        ))
        #expect(!TimelineEventContent.showsFeedbackBadge(
            eventEnd: past,
            now: now,
            awarenessEnabled: false,
            productivityEnabled: true
        ))

        #expect(!TimelineEventContent.shouldShowAlignmentPicker(for: "External appointment"))
        #expect(TimelineEventContent.shouldShowAlignmentPicker(for: "#work SessionFlow event"))
        #expect(TimelineEventContent.shouldShowAlignmentPicker(for: "External appointment \(SessionAlignment.direct.tag)"))
    }

    @Test func goalReminderTextMatchesReminderStyle() {
        let goals = ["Ship paid work", "Write recap", "Triage backlog"]

        #expect(TimelineEventContent.goalReminderText(goals, style: .compact) == "Ship paid work")
        #expect(TimelineEventContent.goalReminderText(goals, style: .prominent) == "Ship paid work / Write recap")
    }
}
