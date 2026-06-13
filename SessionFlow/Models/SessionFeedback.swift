import Foundation

// MARK: - Feedback rating (stored as emoji hashtags in calendar event notes)

enum SessionRating: String, Codable, CaseIterable {
    case rocket = "rocket"          // Amazing session, nailed it
    case completed = "completed"    // Stayed focused the whole time
    case partial = "partial"        // Was there some of the time
    case procrastinated = "procrastinated" // Was present, but lost to distraction
    case skipped = "skipped"        // Was AFK / didn't do it

    /// Emoji hashtag written to calendar event notes (e.g. "#flow✅")
    var tag: String {
        switch self {
        case .rocket: return "#flow🚀"
        case .completed: return "#flow✅"
        case .partial: return "#flow🌗"
        case .procrastinated: return "#flow📱"
        case .skipped: return "#flow❌"
        }
    }

    /// All known feedback tags for stripping/parsing
    static var allTags: [String] {
        allCases.map(\.tag)
    }

    var icon: String {
        switch self {
        case .rocket: return "flame.fill"
        case .completed: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .procrastinated: return "iphone"
        case .skipped: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .rocket: return "Fire"
        case .completed: return "Done"
        case .partial: return "Partly"
        case .procrastinated: return "Procrastinated"
        case .skipped: return "Skipped"
        }
    }

    var shortLabel: String {
        switch self {
        case .rocket: return "Fire"
        case .completed: return "Done"
        case .partial: return "Partly"
        case .procrastinated: return "Procrast."
        case .skipped: return "Skipped"
        }
    }

    var focusMultiplier: Double {
        switch self {
        case .rocket: return 1.0
        case .completed: return 0.8
        case .partial: return 0.5
        case .procrastinated: return 0.0
        case .skipped: return 0.0
        }
    }

    /// Parse a rating from calendar event notes by looking for emoji hashtags
    static func fromNotes(_ notes: String?) -> SessionRating? {
        for rating in allCases {
            if SessionFlowEventSemantics.containsExactTag(rating.tag, in: notes, caseInsensitive: false) {
                return rating
            }
        }
        return nil
    }

    /// Strips only feedback tags from notes, preserving session type tags
    static func stripFeedbackTags(_ notes: String?) -> String? {
        SessionFlowEventSemantics.strippingExactTags(allTags, from: notes, caseInsensitive: false)
    }

    /// Applies this rating tag to notes, removing any existing feedback tag first
    func applyTo(notes: String?) -> String {
        var result = Self.stripFeedbackTags(notes) ?? ""
        // Append new tag
        result += (result.isEmpty ? "" : " ") + tag
        return result
    }
}

// MARK: - Goal alignment (stored as compact hashtags in calendar event notes)

enum SessionAlignment: String, Codable, CaseIterable {
    case offTrack = "offTrack"
    case maintenance = "maintenance"
    case support = "support"
    case strategic = "strategic"
    case direct = "direct"

    var tag: String {
        switch self {
        case .offTrack: return "#flowalign0"
        case .maintenance: return "#flowalign1"
        case .support: return "#flowalign2"
        case .strategic: return "#flowalign3"
        case .direct: return "#flowalign4"
        }
    }

    static var allTags: [String] {
        allCases.map(\.tag)
    }

    var icon: String {
        switch self {
        case .offTrack: return "xmark.octagon.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .support: return "arrow.triangle.branch"
        case .strategic: return "scope"
        case .direct: return "target"
        }
    }

    var label: String {
        switch self {
        case .offTrack: return "Off-track"
        case .maintenance: return "Maintenance"
        case .support: return "Support"
        case .strategic: return "Strategic"
        case .direct: return "Direct"
        }
    }

    var shortLabel: String {
        switch self {
        case .offTrack: return "Off"
        case .maintenance: return "Maint"
        case .support: return "Support"
        case .strategic: return "Strat"
        case .direct: return "Direct"
        }
    }

    var description: String {
        switch self {
        case .offTrack: return "Pulled away from your current goal."
        case .maintenance: return "Necessary upkeep, but weak goal movement."
        case .support: return "Indirect support, setup, tooling, or preparation."
        case .strategic: return "Important progress, not direct payoff yet."
        case .direct: return "Directly moved the current goal."
        }
    }

    var multiplier: Double {
        switch self {
        case .offTrack: return 0.0
        case .maintenance: return 0.25
        case .support: return 0.5
        case .strategic: return 0.75
        case .direct: return 1.0
        }
    }

    var percent: Int {
        Int(multiplier * 100)
    }

    static func fromNotes(_ notes: String?) -> SessionAlignment? {
        for alignment in allCases {
            if SessionFlowEventSemantics.containsExactTag(alignment.tag, in: notes) {
                return alignment
            }
        }
        return nil
    }

    static func stripAlignmentTags(_ notes: String?) -> String? {
        SessionFlowEventSemantics.strippingExactTags(allTags, from: notes)
    }

    func applyTo(notes: String?) -> String {
        var result = Self.stripAlignmentTags(notes) ?? ""
        result += (result.isEmpty ? "" : " ") + tag
        return result
    }
}

// MARK: - Pending feedback (in-memory, drives the panel prompt)

struct SessionFeedback: Identifiable {
    let id = UUID()
    let eventId: String         // BusyTimeSlot.id for lookup
    let sessionTitle: String
    let sessionType: SessionType?
    let startTime: Date
    let endTime: Date

    var totalDuration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Harsh Mode prompt state

enum HarshModePromptPhase: String, Equatable {
    case start
    case end
}

struct HarshModePrompt: Identifiable, Equatable {
    let phase: HarshModePromptPhase
    let eventId: String
    let sessionTitle: String
    let sessionType: SessionType?
    let startTime: Date
    let endTime: Date
    let notes: String?
    let nextTaskTitle: String?
    let nextTaskStartTime: Date?

    var id: String {
        "\(eventId)-\(phase.rawValue)"
    }
}

// MARK: - Harsh Mode note storage

enum HarshModeSessionNotes {
    private static let goalsHeader = "#flowgoal:"
    private static let reviewHeader = "#flowreview:"
    private static let legacyReadableGoalsHeader = "Session Flow Goals:"
    private static let legacyReadableReviewHeader = "Session Flow Review:"
    private static let legacyGoalsStart = "[SessionFlow Harsh Goals]"
    private static let legacyGoalsEnd = "[/SessionFlow Harsh Goals]"
    private static let legacyReviewStart = "[SessionFlow Harsh Review]"
    private static let legacyReviewEnd = "[/SessionFlow Harsh Review]"

    private static let goalsHeaders = [goalsHeader, legacyReadableGoalsHeader]
    private static let reviewHeaders = [reviewHeader, legacyReadableReviewHeader]
    private static let managedHeaders = goalsHeaders + reviewHeaders
    private static let legacyStartMarkers = [legacyGoalsStart, legacyReviewStart]

    static func goalLines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map(cleanedGoalLine)
            .filter { !$0.isEmpty }
    }

    static func goals(from notes: String?) -> [String] {
        sectionLines(
            headers: goalsHeaders,
            legacyStartMarker: legacyGoalsStart,
            legacyEndMarker: legacyGoalsEnd,
            in: notes
        )
            .map(cleanedGoalLine)
            .filter { !$0.isEmpty }
    }

    static func applyingGoals(_ goals: [String], to notes: String?) -> String {
        let cleanedGoals = goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let base = removingSection(
            headers: goalsHeaders,
            legacyStartMarker: legacyGoalsStart,
            legacyEndMarker: legacyGoalsEnd,
            from: notes
        )
        guard !cleanedGoals.isEmpty else { return base }
        return appendingSection(
            to: base,
            header: goalsHeader,
            lines: cleanedGoals
        )
    }

    static func applyingReview(rating: SessionRating?, reflection: String, to notes: String?) -> String {
        applyingReview(rating: rating, alignment: nil, reflection: reflection, to: notes)
    }

    static func applyingReview(rating: SessionRating?, alignment: SessionAlignment?, reflection: String, to notes: String?) -> String {
        let withoutOldReview = removingSection(
            headers: reviewHeaders,
            legacyStartMarker: legacyReviewStart,
            legacyEndMarker: legacyReviewEnd,
            from: notes
        )
        let withRating = applyingRating(rating, to: withoutOldReview)
        let withAlignment = applyingAlignment(alignment, to: withRating)
        let cleanedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedReflection.isEmpty else {
            return withAlignment
        }
        return appendingSection(
            to: withAlignment,
            header: reviewHeader,
            lines: cleanedReflection.components(separatedBy: .newlines)
        )
    }

    static func removingManagedBlocks(from notes: String?) -> String {
        let withoutGoals = removingSection(
            headers: goalsHeaders,
            legacyStartMarker: legacyGoalsStart,
            legacyEndMarker: legacyGoalsEnd,
            from: notes
        )
        return removingSection(
            headers: reviewHeaders,
            legacyStartMarker: legacyReviewStart,
            legacyEndMarker: legacyReviewEnd,
            from: withoutGoals
        )
    }

    private static func sectionLines(
        headers: [String],
        legacyStartMarker: String,
        legacyEndMarker: String,
        in notes: String?
    ) -> [String] {
        guard let notes, !notes.isEmpty else { return [] }
        let lines = notes.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == legacyStartMarker {
                var result: [String] = []
                index += 1
                while index < lines.count {
                    let legacyTrimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if legacyTrimmed == legacyEndMarker {
                        return result
                    }
                    result.append(lines[index])
                    index += 1
                }
                return result
            }
            if headers.contains(trimmed) {
                var result: [String] = []
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if isManagedHeaderStart(nextTrimmed) {
                        break
                    }
                    result.append(lines[index])
                    index += 1
                }
                return result
            }
            index += 1
        }

        return []
    }

    private static func cleanedGoalLine(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("- ") || result.hasPrefix("* ") {
            result = String(result.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        result = SessionFlowEventSemantics.strippingSessionFlowMetadata(from: result) ?? ""

        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removingSection(
        headers: [String],
        legacyStartMarker: String,
        legacyEndMarker: String,
        from notes: String?
    ) -> String {
        guard let notes, !notes.isEmpty else { return "" }
        let lines = notes.components(separatedBy: .newlines)
        var result: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == legacyStartMarker {
                index += 1
                while index < lines.count {
                    let legacyTrimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    index += 1
                    if legacyTrimmed == legacyEndMarker {
                        break
                    }
                }
                continue
            }
            if headers.contains(trimmed) {
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if isManagedHeaderStart(nextTrimmed) {
                        break
                    }
                    index += 1
                }
                continue
            }
            result.append(line)
            index += 1
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendingSection(to notes: String, header: String, lines: [String]) -> String {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let section = ([header] + lines).joined(separator: "\n")
        if trimmedNotes.isEmpty {
            return section
        }
        return "\(trimmedNotes)\n\n\(section)"
    }

    private static func isManagedHeaderStart(_ trimmedLine: String) -> Bool {
        managedHeaders.contains(trimmedLine) || legacyStartMarkers.contains(trimmedLine)
    }

    private static func applyingRating(_ rating: SessionRating?, to notes: String) -> String {
        guard let rating else { return notes }
        let cleanedNotes = removingFeedbackTags(from: notes)
        let parts = splittingBeforeFirstManagedSection(cleanedNotes)
        let ratedPrefix = rating.applyTo(notes: parts.prefix)
        guard !parts.suffix.isEmpty else { return ratedPrefix }
        if ratedPrefix.isEmpty {
            return "\(rating.tag)\n\n\(parts.suffix)"
        }
        return "\(ratedPrefix)\n\n\(parts.suffix)"
    }

    private static func applyingAlignment(_ alignment: SessionAlignment?, to notes: String) -> String {
        guard let alignment else { return notes }
        let cleanedNotes = removingAlignmentTags(from: notes)
        let parts = splittingBeforeFirstManagedSection(cleanedNotes)
        let alignedPrefix = alignment.applyTo(notes: parts.prefix)
        guard !parts.suffix.isEmpty else { return alignedPrefix }
        if alignedPrefix.isEmpty {
            return "\(alignment.tag)\n\n\(parts.suffix)"
        }
        return "\(alignedPrefix)\n\n\(parts.suffix)"
    }

    private static func removingFeedbackTags(from notes: String) -> String {
        SessionRating.stripFeedbackTags(notes) ?? ""
    }

    private static func removingAlignmentTags(from notes: String) -> String {
        SessionAlignment.stripAlignmentTags(notes) ?? ""
    }

    private static func splittingBeforeFirstManagedSection(_ notes: String) -> (prefix: String, suffix: String) {
        let lines = notes.components(separatedBy: .newlines)
        guard let firstManagedIndex = lines.firstIndex(where: { line in
            isManagedHeaderStart(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }) else {
            return (notes.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }

        let prefix = lines[..<firstManagedIndex]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = lines[firstManagedIndex...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (prefix, suffix)
    }
}
