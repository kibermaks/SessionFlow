import Foundation
import SwiftUI

/// Persists recently created event templates for quick re-creation on the timeline.
class RecentEventsStore: ObservableObject {
    private static let defaultsKey = "SessionFlow.RecentEventTemplates"
    private static let maxEntries = 20

    struct EventTemplate: Codable, Identifiable, Equatable {
        let id: UUID
        let title: String
        let durationMinutes: Int  // fallback if original event is gone
        let calendarName: String
        let calendarIdentifier: String?
        let eventId: String?  // reference to the original calendar event
        let isFlexible: Bool
        let lastUsed: Date

        init(title: String, durationMinutes: Int, calendarName: String, calendarIdentifier: String?, eventId: String? = nil, isFlexible: Bool = false, lastUsed: Date = Date()) {
            self.id = UUID()
            self.title = title
            self.durationMinutes = durationMinutes
            self.calendarName = calendarName
            self.calendarIdentifier = calendarIdentifier
            self.eventId = eventId
            self.isFlexible = isFlexible
            self.lastUsed = lastUsed
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, durationMinutes, calendarName, calendarIdentifier, eventId, isFlexible, lastUsed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
            calendarName = try container.decode(String.self, forKey: .calendarName)
            calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier)
            eventId = try container.decodeIfPresent(String.self, forKey: .eventId)
            isFlexible = try container.decodeIfPresent(Bool.self, forKey: .isFlexible) ?? false
            lastUsed = try container.decode(Date.self, forKey: .lastUsed)
        }
    }

    @Published private(set) var templates: [EventTemplate] = []

    init() {
        load()
    }

    /// Records a created event. Updates existing template if title matches, otherwise adds new.
    func record(title: String, durationMinutes: Int, calendarName: String, calendarIdentifier: String?, eventId: String? = nil, isFlexible: Bool = false) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Remove existing entry with same title (case-insensitive)
        templates.removeAll { $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }

        let template = EventTemplate(
            title: trimmed,
            durationMinutes: durationMinutes,
            calendarName: calendarName,
            calendarIdentifier: calendarIdentifier,
            eventId: eventId,
            isFlexible: isFlexible
        )
        templates.insert(template, at: 0)

        // Trim to max
        if templates.count > Self.maxEntries {
            templates = Array(templates.prefix(Self.maxEntries))
        }
        save()
    }

    /// Returns templates matching a query, sorted by relevance (prefix match first, then contains).
    func search(_ query: String) -> [EventTemplate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return templates }

        let lowered = q.lowercased()

        // Partition: prefix matches first, then substring matches
        var prefixMatches: [EventTemplate] = []
        var containsMatches: [EventTemplate] = []

        for t in templates {
            let titleLower = t.title.lowercased()
            if titleLower.hasPrefix(lowered) {
                prefixMatches.append(t)
            } else if titleLower.contains(lowered) {
                containsMatches.append(t)
            }
        }

        // Also do fuzzy: match if all query chars appear in order
        var fuzzyMatches: [EventTemplate] = []
        let queryChars = Array(lowered)
        for t in templates {
            if prefixMatches.contains(where: { $0.id == t.id }) || containsMatches.contains(where: { $0.id == t.id }) {
                continue
            }
            let titleLower = t.title.lowercased()
            var qi = 0
            for ch in titleLower {
                if qi < queryChars.count && ch == queryChars[qi] {
                    qi += 1
                }
            }
            if qi == queryChars.count {
                fuzzyMatches.append(t)
            }
        }

        return prefixMatches + containsMatches + fuzzyMatches
    }

    /// Returns the live duration for a template by looking up its original event.
    /// Falls back to the stored durationMinutes if the event no longer exists.
    func resolveDuration(for template: EventTemplate, using calendarService: CalendarService) -> Int {
        if let eventId = template.eventId,
           let liveDuration = calendarService.eventDurationMinutes(identifier: eventId) {
            return liveDuration
        }
        return template.durationMinutes
    }

    func resolveFlexible(for template: EventTemplate, using calendarService: CalendarService) -> Bool {
        if let eventId = template.eventId,
           let liveFlexible = calendarService.eventIsFlexible(identifier: eventId) {
            return liveFlexible
        }
        return template.isFlexible
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([EventTemplate].self, from: data) else {
            return
        }
        templates = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
