import Foundation

enum SessionFlowEventSemantics {
    enum OwnershipTag: String, CaseIterable, Hashable {
        case work = "#work"
        case side = "#side"
        case deep = "#deep"
        case planning = "#plan"
        case bigRest = "#break"

        var sessionType: SessionType {
            switch self {
            case .work: return .work
            case .side: return .side
            case .deep: return .deep
            case .planning: return .planning
            case .bigRest: return .bigRest
            }
        }
    }

    static let recognizedOwnershipTags = OwnershipTag.allCases.map(\.rawValue)

    static func ownershipTag(for sessionType: SessionType) -> OwnershipTag {
        switch sessionType {
        case .work: return .work
        case .side: return .side
        case .deep: return .deep
        case .planning: return .planning
        case .bigRest: return .bigRest
        }
    }

    static func ownershipTags(in notes: String?) -> [OwnershipTag] {
        guard let notes, !notes.isEmpty else { return [] }

        var tags: [OwnershipTag] = []
        var seen = Set<OwnershipTag>()
        for parsed in parsedHashtags(in: notes) {
            guard let tag = OwnershipTag(rawValue: parsed.normalized), !seen.contains(tag) else {
                continue
            }
            tags.append(tag)
            seen.insert(tag)
        }
        return tags
    }

    static func sessionType(fromNotes notes: String?) -> SessionType? {
        let tags = Set(ownershipTags(in: notes))
        return OwnershipTag.allCases.first { tags.contains($0) }?.sessionType
    }

    static func isSessionFlowOwned(_ notes: String?) -> Bool {
        !ownershipTags(in: notes).isEmpty
    }

    static func strippingOwnershipTags(from notes: String?) -> String? {
        guard let notes, !notes.isEmpty else { return nil }

        let ranges = parsedHashtags(in: notes)
            .filter { OwnershipTag(rawValue: $0.normalized) != nil }
            .map(\.range)

        guard !ranges.isEmpty else { return normalizedStrippedNotes(notes) }

        var result = notes
        for range in ranges.reversed() {
            result.removeSubrange(range)
        }
        return normalizedStrippedNotes(result)
    }

    private static func parsedHashtags(in notes: String) -> [(normalized: String, range: Range<String.Index>)] {
        var results: [(normalized: String, range: Range<String.Index>)] = []
        var index = notes.startIndex

        while index < notes.endIndex {
            guard notes[index] == "#", isHashtagStart(at: index, in: notes) else {
                index = notes.index(after: index)
                continue
            }

            let tagStart = index
            var tagEnd = notes.index(after: index)
            while tagEnd < notes.endIndex, isHashtagContinuation(notes[tagEnd]) {
                tagEnd = notes.index(after: tagEnd)
            }

            if tagEnd > notes.index(after: tagStart) {
                results.append((String(notes[tagStart..<tagEnd]).lowercased(), tagStart..<tagEnd))
            }
            index = tagEnd
        }

        return results
    }

    private static func isHashtagStart(at index: String.Index, in notes: String) -> Bool {
        guard index > notes.startIndex else { return true }
        return !isHashtagContinuation(notes[notes.index(before: index)])
    }

    private static func isHashtagContinuation(_ character: Character) -> Bool {
        if character == "_" || character == "-" { return true }
        return character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func normalizedStrippedNotes(_ notes: String) -> String? {
        let lines = notes
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }

        let normalized = lines
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized.isEmpty ? nil : normalized
    }
}
