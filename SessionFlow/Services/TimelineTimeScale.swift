import CoreGraphics
import Foundation

struct TimelineTimeScale {
    let selectedDate: Date
    let hourHeight: CGFloat
    let hideNightHours: Bool
    let dayStartHour: Int
    let dayEndHour: Int
    let scheduleEndHour: Int
    var calendar: Calendar = .current

    var effectiveEndHour: Int {
        if hideNightHours {
            return max(dayEndHour, scheduleEndHour)
        }
        return max(24, scheduleEndHour)
    }

    var visibleHours: [Int] {
        if hideNightHours {
            return Array(dayStartHour..<effectiveEndHour)
        }
        return Array(0..<effectiveEndHour)
    }

    var contentHeight: CGFloat {
        CGFloat(visibleHours.count) * hourHeight + 40
    }

    func yPosition(for date: Date) -> CGFloat {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let secondsSinceStart = date.timeIntervalSince(dayStart)
        let hours = secondsSinceStart / 3_600
        let offset = hideNightHours ? CGFloat(dayStartHour) : 0
        return (CGFloat(hours) - offset) * hourHeight
    }

    func date(fromYOffset yPosition: CGFloat) -> Date {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let offset = hideNightHours ? CGFloat(dayStartHour) : 0
        let hours = yPosition / hourHeight + offset
        return dayStart.addingTimeInterval(Double(hours) * 3_600)
    }

    func snapToInterval(_ date: Date) -> Date {
        TimeSnapping.snapToNearest(date, intervalMinutes: 5)
    }

    func height(from start: Date, to end: Date) -> CGFloat {
        CGFloat(end.timeIntervalSince(start) / 3_600) * hourHeight
    }

    func formattedHour(
        _ hour: Int,
        uses12HourClock: Bool,
        formatter: DateFormatter = TimelineTimeScale.shortTimeFormatter()
    ) -> String {
        let normalizedHour = ((hour % 24) + 24) % 24

        if uses12HourClock {
            let displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12
            let period = normalizedHour < 12 ? "AM" : "PM"
            return "\(displayHour) \(period)"
        }

        var components = DateComponents()
        components.hour = normalizedHour

        if hour >= 24,
           let date = calendar.date(from: components),
           let nextDay = calendar.date(byAdding: .day, value: 1, to: date) {
            return formatter.string(from: nextDay)
        }

        guard let date = calendar.date(from: components) else {
            return "\(hour):00"
        }
        return formatter.string(from: date)
    }

    func timeRangeString(
        start: Date,
        end: Date,
        formatter: DateFormatter = TimelineTimeScale.shortTimeFormatter()
    ) -> String {
        "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    func startAndDurationString(
        start: Date,
        end: Date,
        formatter: DateFormatter = TimelineTimeScale.shortTimeFormatter()
    ) -> String {
        let durationMinutes = Int(end.timeIntervalSince(start) / 60)
        return "\(formatter.string(from: start)) - \(formatter.string(from: end)) • \(durationMinutes) min"
    }

    func effectiveNowTime(
        currentTime: Date,
        overrideEnabled: Bool,
        overrideHour: Int,
        overrideMinute: Int
    ) -> Date {
        guard overrideEnabled else { return currentTime }
        let dayStart = calendar.startOfDay(for: selectedDate)
        return calendar.date(byAdding: .hour, value: overrideHour, to: dayStart)
            .flatMap { calendar.date(byAdding: .minute, value: overrideMinute, to: $0) } ?? currentTime
    }

    func shouldShowCurrentTimeIndicator(
        currentDate: Date,
        overrideEnabled: Bool
    ) -> Bool {
        if overrideEnabled { return true }
        if calendar.isDateInToday(selectedDate) { return true }
        guard effectiveEndHour > 24,
              let yesterday = calendar.date(byAdding: .day, value: -1, to: currentDate),
              calendar.isDate(selectedDate, inSameDayAs: yesterday) else {
            return false
        }
        let dayStart = calendar.startOfDay(for: selectedDate)
        let hoursFromStart = currentDate.timeIntervalSince(dayStart) / 3_600
        return hoursFromStart < Double(effectiveEndHour)
    }

    static func shortTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}
