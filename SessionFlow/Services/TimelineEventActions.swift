import Foundation

enum TimelineEventActions {
    static let contextMenuActionDelay: TimeInterval = 0.15
    static let elasticEditBlockedMessage = "Save or cancel elastic edits first"

    struct CopyTarget: Hashable {
        let label: String
        let date: Date
    }

    struct CalendarCopyResult: Equatable {
        let success: Bool
        let newEventId: String?
        let targetStartTime: Date?
    }

    struct CopyToast: Equatable {
        let title: String
        let targetLabel: String
        let targetDate: Date
        let targetStartTime: Date
        let newEventId: String
    }

    enum CopyOutcome: Equatable {
        case success(CopyToast)
        case failure(String)
    }

    static func copyTargets(
        today: Date = Date(),
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> [CopyTarget] {
        (0...6).compactMap { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            guard !calendar.isDate(date, inSameDayAs: selectedDate) else { return nil }

            return CopyTarget(
                label: menuLabel(forDayOffset: offset, date: date),
                date: date
            )
        }
    }

    static func customCopyLabel(for date: Date) -> String {
        formattedDayLabel(for: date)
    }

    static func duplicateOutcome(
        title: String,
        selectedDate: Date,
        result: CalendarCopyResult
    ) -> CopyOutcome {
        copyOutcome(
            title: title,
            targetLabel: "the same day",
            targetDate: selectedDate,
            failureVerb: "duplicate",
            result: result
        )
    }

    static func copyOutcome(
        title: String,
        target: CopyTarget,
        result: CalendarCopyResult
    ) -> CopyOutcome {
        copyOutcome(
            title: title,
            targetLabel: target.label,
            targetDate: target.date,
            failureVerb: "copy",
            result: result
        )
    }

    static func customCopyOutcome(
        title: String,
        targetDate: Date,
        result: CalendarCopyResult
    ) -> CopyOutcome {
        copyOutcome(
            title: title,
            targetLabel: customCopyLabel(for: targetDate),
            targetDate: targetDate,
            failureVerb: "copy",
            result: result
        )
    }

    static func deleteSnapshot(for slot: BusyTimeSlot) -> EventDeleteSnapshot {
        EventDeleteSnapshot(
            eventId: slot.id,
            title: slot.title,
            notes: slot.notes,
            url: slot.url,
            startDate: slot.startTime,
            endDate: slot.endTime,
            calendarIdentifier: slot.calendarIdentifier,
            calendarName: slot.calendarName
        )
    }

    static func calendarCopyResult(
        success: Bool,
        newEventId: String?,
        targetStartTime: Date?
    ) -> CalendarCopyResult {
        CalendarCopyResult(success: success, newEventId: newEventId, targetStartTime: targetStartTime)
    }

    private static func copyOutcome(
        title: String,
        targetLabel: String,
        targetDate: Date,
        failureVerb: String,
        result: CalendarCopyResult
    ) -> CopyOutcome {
        guard result.success,
              let newEventId = result.newEventId,
              let targetStartTime = result.targetStartTime else {
            return .failure("Failed to \(failureVerb) \"\(title)\"")
        }

        return .success(CopyToast(
            title: title,
            targetLabel: targetLabel,
            targetDate: targetDate,
            targetStartTime: targetStartTime,
            newEventId: newEventId
        ))
    }

    private static func menuLabel(forDayOffset offset: Int, date: Date) -> String {
        switch offset {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            return formattedDayLabel(for: date)
        }
    }

    private static func formattedDayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
