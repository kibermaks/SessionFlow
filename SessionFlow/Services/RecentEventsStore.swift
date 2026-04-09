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
        let lastUsed: Date

        init(title: String, durationMinutes: Int, calendarName: String, calendarIdentifier: String?, eventId: String? = nil, lastUsed: Date = Date()) {
            self.id = UUID()
            self.title = title
            self.durationMinutes = durationMinutes
            self.calendarName = calendarName
            self.calendarIdentifier = calendarIdentifier
            self.eventId = eventId
            self.lastUsed = lastUsed
        }
    }

    @Published private(set) var templates: [EventTemplate] = []

    init() {
        load()
    }

    /// Records a created event. Updates existing template if title matches, otherwise adds new.
    func record(title: String, durationMinutes: Int, calendarName: String, calendarIdentifier: String?, eventId: String? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Remove existing entry with same title (case-insensitive)
        templates.removeAll { $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }

        let template = EventTemplate(
            title: trimmed,
            durationMinutes: durationMinutes,
            calendarName: calendarName,
            calendarIdentifier: calendarIdentifier,
            eventId: eventId
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
