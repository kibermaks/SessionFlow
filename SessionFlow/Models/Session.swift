import SwiftUI
import EventKit

// MARK: - Session Type
enum SessionType: String, Codable, CaseIterable, Identifiable {
    case work = "Work"
    case side = "Side"
    case planning = "Planning"
    case deep = "Deep"
    case bigRest = "Long Rest"

    var id: String { rawValue }

    var defaultDuration: Int {
        switch self {
        case .work: return 40
        case .side: return 30
        case .planning: return 15
        case .deep: return 15
        case .bigRest: return 60
        }
    }

    var color: Color {
        switch self {
        case .work: return Color(hex: "8B5CF6")      // Purple
        case .side: return Color(hex: "3B82F6")       // Blue
        case .planning: return Color(hex: "EF4444")   // Red
        case .deep: return Color(hex: "10B981")      // Emerald Green
        case .bigRest: return Color(hex: "F59E0B")  // Amber
        }
    }

    var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .side: return "star.fill"
        case .planning: return "calendar.badge.clock"
        case .deep: return "bolt.circle.fill"
        case .bigRest: return "pause.circle.fill"
        }
    }
}

// MARK: - Scheduled Session
struct ScheduledSession: Identifiable, Equatable {
    let id: UUID
    let type: SessionType
    var title: String
    var startTime: Date
    var endTime: Date
    let calendarName: String
    let calendarIdentifier: String?
    let notes: String?
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var durationMinutes: Int {
        Int(duration / 60)
    }
    
    init(
        id: UUID = UUID(),
        type: SessionType,
        title: String,
        startTime: Date,
        endTime: Date,
        calendarName: String,
        calendarIdentifier: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.calendarName = calendarName
        self.calendarIdentifier = calendarIdentifier
        self.notes = notes
    }
    
    /// Returns the hashtag string (without #) for this session type
    func hashtag() -> String {
        switch type {
        case .work: return "work"
        case .side: return "side"
        case .deep: return "deep"
        case .planning: return "plan"
        case .bigRest: return "break"
        }
    }
}

// MARK: - Busy Time Slot (from existing calendar events)
struct BusyTimeSlot: Identifiable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let notes: String?
    let url: URL?
    let calendarName: String
    let calendarColor: Color
    let calendarIdentifier: String?

    init(from event: EKEvent) {
        self.id = event.eventIdentifier ?? UUID().uuidString
        self.title = event.title ?? "Busy"
        self.startTime = event.startDate
        self.endTime = event.endDate
        self.notes = event.notes
        self.url = event.url
        self.calendarName = event.calendar?.title ?? "Unknown"
        self.calendarIdentifier = event.calendar?.calendarIdentifier
        if let cgColor = event.calendar?.cgColor {
            self.calendarColor = Color(cgColor: cgColor)
        } else {
            self.calendarColor = .gray
        }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        startTime: Date,
        endTime: Date,
        notes: String? = nil,
        url: URL? = nil,
        calendarName: String,
        calendarColor: Color = .gray,
        calendarIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
        self.url = url
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.calendarIdentifier = calendarIdentifier
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
