import Foundation

enum TimelineInlineEditField: Hashable {
    case title
    case notes
    case url
}

struct TimelineInlineEditCommit: Equatable {
    enum Change: Equatable {
        case title(old: String, new: String)
        case notes(old: String?, new: String?)
        case url(old: URL?, new: URL?)
    }

    let change: Change
    let description: String
}

struct TimelineInlineEditor: Equatable {
    struct TextEdit: Equatable {
        var isEditing = false
        var draft = ""
        var original = ""
    }

    var title = TextEdit()
    var notes = TextEdit()
    var url = TextEdit()
    var isCanceling = false
    var autoFocusField: TimelineInlineEditField?

    mutating func begin(_ field: TimelineInlineEditField, original: String) {
        var state = editState(for: field)
        state.isEditing = true
        state.draft = original
        state.original = original
        setEditState(state, for: field)
    }

    mutating func cancel(_ field: TimelineInlineEditField) {
        isCanceling = true
        reset(field)
    }

    mutating func clearCancelGuard() {
        isCanceling = false
    }

    mutating func reset(_ field: TimelineInlineEditField) {
        setEditState(TextEdit(), for: field)
    }

    mutating func resetAll() {
        title = TextEdit()
        notes = TextEdit()
        url = TextEdit()
        isCanceling = false
        autoFocusField = nil
    }

    func commitPlan(
        for field: TimelineInlineEditField,
        existingNotes: String?,
        isFlowFlexible: Bool
    ) -> TimelineInlineEditCommit? {
        switch field {
        case .title:
            return titleCommitPlan()
        case .notes:
            return notesCommitPlan(existingNotes: existingNotes, isFlowFlexible: isFlowFlexible)
        case .url:
            return urlCommitPlan()
        }
    }

    func dirtyCommitPlans(existingNotes: String?, isFlowFlexible: Bool) -> [TimelineInlineEditCommit] {
        TimelineInlineEditField.commitOrder.compactMap { field in
            guard editState(for: field).isEditing else { return nil }
            return commitPlan(for: field, existingNotes: existingNotes, isFlowFlexible: isFlowFlexible)
        }
    }

    func isEditing(_ field: TimelineInlineEditField) -> Bool {
        editState(for: field).isEditing
    }

    private func titleCommitPlan() -> TimelineInlineEditCommit? {
        guard title.isEditing else { return nil }
        guard !title.draft.isEmpty else { return nil }
        guard title.draft != title.original else { return nil }

        return TimelineInlineEditCommit(
            change: .title(old: title.original, new: title.draft),
            description: "Rename Event"
        )
    }

    private func notesCommitPlan(existingNotes: String?, isFlowFlexible: Bool) -> TimelineInlineEditCommit? {
        guard notes.isEditing else { return nil }
        guard let update = TimelineEventContent.notesUpdate(
            editedText: notes.draft,
            originalText: notes.original,
            existingNotes: existingNotes,
            isFlowFlexible: isFlowFlexible
        ) else {
            return nil
        }

        return TimelineInlineEditCommit(
            change: .notes(old: update.oldNotesForUndo, new: update.notesToSave),
            description: "Edit Notes"
        )
    }

    private func urlCommitPlan() -> TimelineInlineEditCommit? {
        guard url.isEditing else { return nil }
        guard let update = TimelineEventContent.urlUpdate(editedText: url.draft, originalText: url.original) else {
            return nil
        }

        return TimelineInlineEditCommit(
            change: .url(old: update.oldURLForUndo, new: update.urlToSave),
            description: "Edit URL"
        )
    }

    private func editState(for field: TimelineInlineEditField) -> TextEdit {
        switch field {
        case .title:
            return title
        case .notes:
            return notes
        case .url:
            return url
        }
    }

    private mutating func setEditState(_ state: TextEdit, for field: TimelineInlineEditField) {
        switch field {
        case .title:
            title = state
        case .notes:
            notes = state
        case .url:
            url = state
        }
    }
}

private extension TimelineInlineEditField {
    static let commitOrder: [TimelineInlineEditField] = [.title, .notes, .url]
}
