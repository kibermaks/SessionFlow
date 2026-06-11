import Foundation

// MARK: - Feedback rating (stored as emoji hashtags in calendar event notes)

enum SessionRating: String, Codable, CaseIterable {
    case rocket = "rocket"          // Amazing session, nailed it
    case completed = "completed"    // Stayed focused the whole time
    case partial = "partial"        // Was there some of the time
    case skipped = "skipped"        // Was AFK / didn't do it

    /// Emoji hashtag written to calendar event notes (e.g. "#flow✅")
    var tag: String {
        switch self {
        case .rocket: return "#flow🚀"
        case .completed: return "#flow✅"
        case .partial: return "#flow🌗"
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
        case .skipped: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .rocket: return "Fire"
        case .completed: return "Done"
        case .partial: return "Partly"
        case .skipped: return "Skipped"
        }
    }

    var focusMultiplier: Double {
        switch self {
        case .rocket: return 1.0
        case .completed: return 0.8
        case .partial: return 0.5
        case .skipped: return 0.0
        }
    }

    /// Parse a rating from calendar event notes by looking for emoji hashtags
    static func fromNotes(_ notes: String?) -> SessionRating? {
        guard let notes = notes else { return nil }
        for rating in allCases {
            if notes.contains(rating.tag) { return rating }
        }
        return nil
    }

    /// Strips only feedback tags from notes, preserving session type tags
    static func stripFeedbackTags(_ notes: String?) -> String? {
        guard let notes = notes, !notes.isEmpty else { return nil }
        var result = notes
        for tag in allTags {
            result = result.replacingOccurrences(of: tag, with: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    /// Applies this rating tag to notes, removing any existing feedback tag first
    func applyTo(notes: String?) -> String {
        var result = notes ?? ""
        // Remove existing feedback tags
        for existingTag in Self.allTags {
            result = result.replacingOccurrences(of: existingTag, with: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // Append new tag
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

    var id: String {
        "\(eventId)-\(phase.rawValue)"
    }
}

// MARK: - Harsh Mode note storage

enum HarshModeSessionNotes {
    private static let goalsStart = "[SessionFlow Harsh Goals]"
    private static let goalsEnd = "[/SessionFlow Harsh Goals]"
    private static let reviewStart = "[SessionFlow Harsh Review]"
    private static let reviewEnd = "[/SessionFlow Harsh Review]"

    static func goalLines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line in
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    return String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return line
            }
            .filter { !$0.isEmpty }
    }

    static func goals(from notes: String?) -> [String] {
        blockLines(startMarker: goalsStart, endMarker: goalsEnd, in: notes)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return trimmed
            }
            .filter { !$0.isEmpty }
    }

    static func applyingGoals(_ goals: [String], to notes: String?) -> String {
        let cleanedGoals = goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let base = removingBlock(startMarker: goalsStart, endMarker: goalsEnd, from: notes)
        guard !cleanedGoals.isEmpty else { return base }
        return appendingBlock(
            to: base,
            startMarker: goalsStart,
            lines: cleanedGoals.map { "- \($0)" },
            endMarker: goalsEnd
        )
    }

    static func applyingReview(rating: SessionRating?, reflection: String, to notes: String?) -> String {
        let withoutOldReview = removingBlock(startMarker: reviewStart, endMarker: reviewEnd, from: notes)
        let withRating = rating?.applyTo(notes: withoutOldReview) ?? withoutOldReview
        let cleanedReflection = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if let rating {
            lines.append("Rating: \(rating.label)")
        }
        if !cleanedReflection.isEmpty {
            lines.append("Reflection:")
            lines.append(contentsOf: cleanedReflection.components(separatedBy: .newlines))
        }
        guard !lines.isEmpty else {
            return withRating
        }
        return appendingBlock(to: withRating, startMarker: reviewStart, lines: lines, endMarker: reviewEnd)
    }

    static func removingManagedBlocks(from notes: String?) -> String {
        let withoutGoals = removingBlock(startMarker: goalsStart, endMarker: goalsEnd, from: notes)
        return removingBlock(startMarker: reviewStart, endMarker: reviewEnd, from: withoutGoals)
    }

    private static func blockLines(startMarker: String, endMarker: String, in notes: String?) -> [String] {
        guard let notes, !notes.isEmpty else { return [] }
        var isInsideBlock = false
        var result: [String] = []

        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == startMarker {
                isInsideBlock = true
                continue
            }
            if trimmed == endMarker {
                break
            }
            if isInsideBlock {
                result.append(line)
            }
        }

        return result
    }

    private static func removingBlock(startMarker: String, endMarker: String, from notes: String?) -> String {
        guard let notes, !notes.isEmpty else { return "" }
        var isInsideBlock = false
        var result: [String] = []

        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == startMarker {
                isInsideBlock = true
                continue
            }
            if trimmed == endMarker {
                isInsideBlock = false
                continue
            }
            if !isInsideBlock {
                result.append(line)
            }
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func appendingBlock(to notes: String, startMarker: String, lines: [String], endMarker: String) -> String {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = ([startMarker] + lines + [endMarker]).joined(separator: "\n")
        if trimmedNotes.isEmpty {
            return block
        }
        return "\(trimmedNotes)\n\n\(block)"
    }
}
