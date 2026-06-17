import Foundation

enum TimelineEventContent {
    struct NotesUpdate: Equatable {
        let notesToSave: String?
        let oldNotesForUndo: String?
    }

    struct URLUpdate: Equatable {
        let urlToSave: URL?
        let oldURLForUndo: URL?
    }

    static func blockDisplayNotes(from notes: String?) -> String? {
        detailEditableNotes(from: SessionAwarenessService.strippedNotes(notes))
    }

    static func detailEditableNotes(from notes: String?) -> String? {
        FlowFlexibilityNotes.strippingTags(
            from: HarshModeSessionNotes.removingManagedBlocks(
                from: SessionAlignment.stripAlignmentTags(SessionRating.stripFeedbackTags(notes))
            )
        )
    }

    static func notesUpdate(
        editedText: String,
        originalText: String,
        existingNotes: String?,
        isFlowFlexible: Bool
    ) -> NotesUpdate? {
        let normalizedNew = editedText.isEmpty ? nil : editedText
        let normalizedOriginal = originalText.isEmpty ? nil : originalText

        guard normalizedNew != normalizedOriginal else { return nil }

        let finalNotes = (normalizedNew ?? "") + reviewTagSuffix(from: existingNotes)
        let trimmedNotes: String? = finalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : finalNotes
        let notesWithFlexibility = FlowFlexibilityNotes.applyingFlexible(isFlowFlexible, to: trimmedNotes)
        let notesToSave = applyingExistingGoals(from: existingNotes, to: notesWithFlexibility)
        let oldNotesWithFlexibility = FlowFlexibilityNotes.applyingFlexible(isFlowFlexible, to: normalizedOriginal)
        let oldNotesForUndo = applyingExistingGoals(from: existingNotes, to: oldNotesWithFlexibility)

        return NotesUpdate(notesToSave: notesToSave, oldNotesForUndo: oldNotesForUndo)
    }

    static func goalsUpdate(
        editedText: String,
        originalText: String,
        existingNotes: String?,
        isFlowFlexible: Bool
    ) -> NotesUpdate? {
        let newGoals = HarshModeSessionNotes.goalLines(from: editedText)
        let originalGoals = HarshModeSessionNotes.goalLines(from: originalText)

        guard newGoals != originalGoals else { return nil }

        let notesWithoutGoals = HarshModeSessionNotes.applyingGoals([], to: existingNotes)
        let notesWithFlexibility = FlowFlexibilityNotes.applyingFlexible(isFlowFlexible, to: notesWithoutGoals)
        let notesToSave = HarshModeSessionNotes.applyingGoals(newGoals, to: notesWithFlexibility)
        let oldNotesForUndo = existingNotes

        return NotesUpdate(notesToSave: notesToSave, oldNotesForUndo: oldNotesForUndo)
    }

    static func urlUpdate(editedText: String, originalText: String) -> URLUpdate? {
        let originalURLString = originalText.isEmpty ? nil : originalText
        let newURLString = editedText.isEmpty ? nil : editedText.trimmingCharacters(in: .whitespaces)

        guard newURLString != originalURLString else { return nil }

        return URLUpdate(
            urlToSave: normalizedURL(from: editedText),
            oldURLForUndo: originalURLString.flatMap { URL(string: $0) }
        )
    }

    static func showsFeedbackBadge(
        eventEnd: Date,
        now: Date = Date(),
        awarenessEnabled: Bool,
        productivityEnabled: Bool
    ) -> Bool {
        eventEnd < now && awarenessEnabled && productivityEnabled
    }

    static func shouldShowAlignmentPicker(for notes: String?) -> Bool {
        FlowFlexibilityNotes.countsTowardAlignmentScore(
            notes,
            alignment: SessionAlignment.fromNotes(notes)
        )
    }

    static func goalReminderText(_ goals: [String], style: HarshModeReminderStyle) -> String {
        switch style {
        case .compact:
            return goals.first ?? ""
        case .prominent:
            return goals.prefix(2).joined(separator: " / ")
        }
    }

    private static func applyingExistingGoals(from sourceNotes: String?, to notes: String?) -> String? {
        let goals = HarshModeSessionNotes.goals(from: sourceNotes)
        guard !goals.isEmpty else { return notes }
        return HarshModeSessionNotes.applyingGoals(goals, to: notes)
    }

    private static func reviewTagSuffix(from notes: String?) -> String {
        var tags: [String] = []
        if let rating = SessionRating.fromNotes(notes) {
            tags.append(rating.tag)
        }
        if let alignment = SessionAlignment.fromNotes(notes) {
            tags.append(alignment.tag)
        }
        return tags.isEmpty ? "" : " " + tags.joined(separator: " ")
    }

    private static func normalizedURL(from rawText: String) -> URL? {
        guard !rawText.isEmpty else { return nil }

        var urlString = rawText.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        if let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: encoded)
        }
        return URL(string: urlString)
    }
}
