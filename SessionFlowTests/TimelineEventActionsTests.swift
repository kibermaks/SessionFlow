import Foundation
import SwiftUI
import Testing
@testable import SessionFlow

struct TimelineEventActionsTests {
    @Test func copyTargetsSkipSelectedDayAndUseRelativeLabels() {
        let calendar = testCalendar()
        let today = calendar.date(from: DateComponents(year: 2026, month: 6, day: 13))!
        let selectedDate = calendar.date(byAdding: .day, value: 1, to: today)!

        let targets = TimelineEventActions.copyTargets(
            today: today,
            selectedDate: selectedDate,
            calendar: calendar
        )

        #expect(Array(targets.map(\.label).prefix(2)) == ["Today", "Mon, Jun 15"])
        #expect(!targets.contains { calendar.isDate($0.date, inSameDayAs: selectedDate) })
        #expect(targets.count == 6)
    }

    @Test func duplicateOutcomeUsesSameDaySuccessOrDuplicateFailure() {
        let selectedDate = Date(timeIntervalSince1970: 1_000)
        let start = Date(timeIntervalSince1970: 2_000)

        let success = TimelineEventActions.duplicateOutcome(
            title: "Focus",
            selectedDate: selectedDate,
            result: .init(success: true, newEventId: "copy-id", targetStartTime: start)
        )

        #expect(success == .success(TimelineEventActions.CopyToast(
            title: "Focus",
            targetLabel: "the same day",
            targetDate: selectedDate,
            targetStartTime: start,
            newEventId: "copy-id"
        )))

        #expect(TimelineEventActions.duplicateOutcome(
            title: "Focus",
            selectedDate: selectedDate,
            result: .init(success: false, newEventId: nil, targetStartTime: nil)
        ) == .failure("Failed to duplicate \"Focus\""))
    }

    @Test func copyOutcomeUsesTargetLabelAndCopyFailure() {
        let targetDate = Date(timeIntervalSince1970: 3_000)
        let start = Date(timeIntervalSince1970: 4_000)
        let target = TimelineEventActions.CopyTarget(label: "Tomorrow", date: targetDate)

        let success = TimelineEventActions.copyOutcome(
            title: "Review",
            target: target,
            result: .init(success: true, newEventId: "copy-id", targetStartTime: start)
        )

        #expect(success == .success(TimelineEventActions.CopyToast(
            title: "Review",
            targetLabel: "Tomorrow",
            targetDate: targetDate,
            targetStartTime: start,
            newEventId: "copy-id"
        )))

        #expect(TimelineEventActions.copyOutcome(
            title: "Review",
            target: target,
            result: .init(success: true, newEventId: nil, targetStartTime: start)
        ) == .failure("Failed to copy \"Review\""))
    }

    @Test func customCopyOutcomeFormatsTargetLabel() {
        let calendar = testCalendar()
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 9))!

        let outcome = TimelineEventActions.customCopyOutcome(
            title: "Planning",
            targetDate: targetDate,
            result: .init(success: true, newEventId: "new-id", targetStartTime: start)
        )

        #expect(outcome == .success(TimelineEventActions.CopyToast(
            title: "Planning",
            targetLabel: "Tue, Jun 16",
            targetDate: targetDate,
            targetStartTime: start,
            newEventId: "new-id"
        )))
    }

    @Test func deleteSnapshotCopiesUndoFieldsFromSlot() {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = start.addingTimeInterval(1_800)
        let url = URL(string: "https://example.com")!
        let slot = BusyTimeSlot(
            id: "event-id",
            title: "Focus",
            startTime: start,
            endTime: end,
            notes: "#work notes",
            url: url,
            calendarName: "Work",
            calendarColor: .blue,
            calendarIdentifier: "calendar-id"
        )

        #expect(TimelineEventActions.deleteSnapshot(for: slot) == EventDeleteSnapshot(
            eventId: "event-id",
            title: "Focus",
            notes: "#work notes",
            url: url,
            startDate: start,
            endDate: end,
            calendarIdentifier: "calendar-id",
            calendarName: "Work"
        ))
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
