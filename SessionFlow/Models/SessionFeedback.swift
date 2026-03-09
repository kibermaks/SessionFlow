import Foundation

// MARK: - Feedback rating

enum SessionRating: String, Codable, CaseIterable {
    case completed = "completed"    // Stayed focused the whole time
    case partial = "partial"        // Was there some of the time
    case skipped = "skipped"        // Was AFK / didn't do it

    var icon: String {
        switch self {
        case .completed: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .skipped: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .completed: return "Done"
        case .partial: return "Partly"
        case .skipped: return "Skipped"
        }
    }

    var badgeCharacter: String {
        switch self {
        case .completed: return "✓"
        case .partial: return "◐"
        case .skipped: return "✗"
        }
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

// MARK: - Persisted feedback entry

struct SessionFeedbackEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let eventId: String
    let date: Date
    let sessionTitle: String
    let sessionType: String     // SessionType.rawValue
    let totalMinutes: Int
    let rating: SessionRating

    init(from feedback: SessionFeedback, rating: SessionRating) {
        self.id = UUID()
        self.eventId = feedback.eventId
        self.date = feedback.startTime
        self.sessionTitle = feedback.sessionTitle
        self.sessionType = feedback.sessionType?.rawValue ?? ""
        self.totalMinutes = Int(feedback.totalDuration / 60)
        self.rating = rating
    }

    init(eventId: String, date: Date, sessionTitle: String, sessionType: String, totalMinutes: Int, rating: SessionRating) {
        self.id = UUID()
        self.eventId = eventId
        self.date = date
        self.sessionTitle = sessionTitle
        self.sessionType = sessionType
        self.totalMinutes = totalMinutes
        self.rating = rating
    }
}

// MARK: - Feedback storage

class SessionFeedbackStore {
    static let shared = SessionFeedbackStore()
    private static let storageKey = "SessionFlow.SessionFeedbackLog"

    private init() {}

    func loadEntries() -> [SessionFeedbackEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([SessionFeedbackEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func saveEntry(_ entry: SessionFeedbackEntry) {
        var entries = loadEntries()
        // Replace if already exists for this event
        entries.removeAll { $0.eventId == entry.eventId }
        entries.append(entry)
        save(entries)
    }

    func updateRating(eventId: String, rating: SessionRating) {
        var entries = loadEntries()
        if let index = entries.firstIndex(where: { $0.eventId == eventId }) {
            let old = entries[index]
            entries[index] = SessionFeedbackEntry(
                eventId: old.eventId,
                date: old.date,
                sessionTitle: old.sessionTitle,
                sessionType: old.sessionType,
                totalMinutes: old.totalMinutes,
                rating: rating
            )
            save(entries)
        }
    }

    func entry(forEventId eventId: String) -> SessionFeedbackEntry? {
        loadEntries().first { $0.eventId == eventId }
    }

    func clearOldEntries(keepingDate: Date) {
        let calendar = Calendar.current
        let entries = loadEntries().filter { calendar.isDate($0.date, inSameDayAs: keepingDate) }
        save(entries)
    }

    private func save(_ entries: [SessionFeedbackEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
