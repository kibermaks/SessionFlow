import Foundation
import Testing
@testable import SessionFlow

struct TimelineInlineEditorTests {
    @Test func beginCancelAndResetEditState() {
        var editor = TimelineInlineEditor()

        editor.begin(.notes, original: "Original notes")
        #expect(editor.notes == TimelineInlineEditor.TextEdit(
            isEditing: true,
            draft: "Original notes",
            original: "Original notes"
        ))

        editor.cancel(.notes)
        #expect(editor.isCanceling)
        #expect(!editor.notes.isEditing)
        #expect(editor.notes.draft.isEmpty)

        editor.clearCancelGuard()
        #expect(!editor.isCanceling)

        editor.begin(.title, original: "Title")
        editor.begin(.url, original: "https://example.com")
        editor.autoFocusField = .url
        editor.resetAll()

        #expect(editor == TimelineInlineEditor())
    }

    @Test func titleCommitPlanRejectsEmptyAndUnchangedTitles() {
        var editor = TimelineInlineEditor()
        editor.begin(.title, original: "Original")

        editor.title.draft = ""
        #expect(editor.commitPlan(for: .title, existingNotes: nil, isFlowFlexible: true) == nil)

        editor.title.draft = "Original"
        #expect(editor.commitPlan(for: .title, existingNotes: nil, isFlowFlexible: true) == nil)
    }

    @Test func titleCommitPlanDescribesRename() {
        var editor = TimelineInlineEditor()
        editor.begin(.title, original: "Original")
        editor.title.draft = "Renamed"

        #expect(editor.commitPlan(for: .title, existingNotes: nil, isFlowFlexible: true) == TimelineInlineEditCommit(
            change: .title(old: "Original", new: "Renamed"),
            description: "Rename Event"
        ))
    }

    @Test func notesCommitPlanUsesTimelineContentPolicy() {
        var editor = TimelineInlineEditor()
        editor.begin(.notes, original: "#work Original")
        editor.notes.draft = "#work Edited"

        let plan = editor.commitPlan(
            for: .notes,
            existingNotes: "#work Original \(SessionRating.completed.tag) \(SessionAlignment.direct.tag)",
            isFlowFlexible: false
        )

        #expect(plan == TimelineInlineEditCommit(
            change: .notes(
                old: "#work Original #flowfixed",
                new: "#work Edited \(SessionRating.completed.tag) \(SessionAlignment.direct.tag) #flowfixed"
            ),
            description: "Edit Notes"
        ))
    }

    @Test func urlCommitPlanUsesTimelineContentPolicy() {
        var editor = TimelineInlineEditor()
        editor.begin(.url, original: "")
        editor.url.draft = "example.com/path with spaces"

        let plan = editor.commitPlan(for: .url, existingNotes: nil, isFlowFlexible: true)

        #expect(plan == TimelineInlineEditCommit(
            change: .url(old: nil, new: URL(string: "https://example.com/path%20with%20spaces")),
            description: "Edit URL"
        ))
    }

    @Test func dirtyCommitPlansOnlyIncludesEditingChangedFieldsInStableOrder() {
        var editor = TimelineInlineEditor()
        editor.begin(.url, original: "")
        editor.url.draft = "example.com"
        editor.begin(.title, original: "Original")
        editor.title.draft = "Renamed"
        editor.begin(.notes, original: "Same")
        editor.notes.draft = "Same"

        let plans = editor.dirtyCommitPlans(existingNotes: "Same \(SessionRating.completed.tag)", isFlowFlexible: true)

        #expect(plans == [
            TimelineInlineEditCommit(change: .title(old: "Original", new: "Renamed"), description: "Rename Event"),
            TimelineInlineEditCommit(change: .url(old: nil, new: URL(string: "https://example.com")), description: "Edit URL")
        ])
    }
}
