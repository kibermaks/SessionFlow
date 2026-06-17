import Foundation
import SwiftUI
import Testing
@testable import SessionFlow

struct TimelineBusySlotLayoutTests {
    @Test func nonOverlappingSlotsUseSingleColumn() {
        let result = TimelineBusySlotLayout.positionedSlots(for: [
            slot(id: "a", start: date(9), end: date(10)),
            slot(id: "b", start: date(10), end: date(11))
        ])

        #expect(result.map(\.id) == ["a", "b"])
        #expect(result.map(\.column) == [0, 0])
        #expect(result.map(\.totalColumns) == [1, 1])
    }

    @Test func overlappingSlotsShareClusterColumnCount() {
        let result = TimelineBusySlotLayout.positionedSlots(for: [
            slot(id: "a", start: date(9), end: date(11)),
            slot(id: "b", start: date(9, 30), end: date(10, 30)),
            slot(id: "c", start: date(10, 45), end: date(11, 30))
        ])

        #expect(result.map(\.id) == ["a", "b", "c"])
        #expect(result.map(\.column) == [0, 1, 1])
        #expect(result.map(\.totalColumns) == [2, 2, 2])
    }

    @Test func reusesReleasedColumnsInsideActiveCluster() {
        let result = TimelineBusySlotLayout.positionedSlots(for: [
            slot(id: "a", start: date(9), end: date(12)),
            slot(id: "b", start: date(9, 30), end: date(10)),
            slot(id: "c", start: date(10), end: date(10, 30))
        ])

        #expect(result.map(\.id) == ["a", "b", "c"])
        #expect(result.map(\.column) == [0, 1, 1])
        #expect(result.map(\.totalColumns) == [2, 2, 2])
    }

    @Test func separateClustersDoNotInheritColumnCount() {
        let result = TimelineBusySlotLayout.positionedSlots(for: [
            slot(id: "a", start: date(9), end: date(10)),
            slot(id: "b", start: date(9, 30), end: date(10, 30)),
            slot(id: "c", start: date(11), end: date(12)),
            slot(id: "d", start: date(12), end: date(13))
        ])

        #expect(result.map(\.id) == ["a", "b", "c", "d"])
        #expect(result.map(\.column) == [0, 1, 0, 0])
        #expect(result.map(\.totalColumns) == [2, 2, 1, 1])
    }

    @Test func sortsByStartTimeBeforeAssigningColumns() {
        let result = TimelineBusySlotLayout.positionedSlots(for: [
            slot(id: "late", start: date(11), end: date(12)),
            slot(id: "early", start: date(9), end: date(10))
        ])

        #expect(result.map(\.id) == ["early", "late"])
        #expect(result.map(\.column) == [0, 0])
        #expect(result.map(\.totalColumns) == [1, 1])
    }

    private func slot(id: String, start: Date, end: Date) -> BusyTimeSlot {
        BusyTimeSlot(
            id: id,
            title: id,
            startTime: start,
            endTime: end,
            calendarName: "Work",
            calendarColor: .blue
        )
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        let base = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 13))!
        return base.addingTimeInterval(TimeInterval(hour * 60 + minute) * 60)
    }
}
