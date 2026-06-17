import Foundation
import SwiftUI
import Testing
@testable import SessionFlow

struct TimelineGroupDragTests {
    @Test func beginCapturesSelectedSlotTimesAndIgnoresMissingIds() {
        var groupDrag = TimelineGroupDrag()
        let slots = [
            slot(id: "a", start: date(9), end: date(10)),
            slot(id: "b", start: date(11), end: date(12))
        ]

        groupDrag.begin(selectedIds: ["a", "missing"], slots: slots)

        #expect(groupDrag.isActive)
        #expect(groupDrag.contains("a"))
        #expect(!groupDrag.contains("b"))
        #expect(groupDrag.originalTimes["a"]?.start == date(9))
        #expect(groupDrag.preview(for: "a")?.end == date(10))
    }

    @Test func updateTranslationMovesEveryCapturedSlotByAnchorDelta() {
        var groupDrag = TimelineGroupDrag()
        let slots = [
            slot(id: "a", start: date(9), end: date(10)),
            slot(id: "b", start: date(11), end: date(12))
        ]

        groupDrag.begin(selectedIds: ["a", "b"], slots: slots)
        let previews = groupDrag.updateTranslation(from: date(9), to: date(10))

        #expect(previews["a"]?.start == date(10))
        #expect(previews["a"]?.end == date(11))
        #expect(previews["b"]?.start == date(12))
        #expect(previews["b"]?.end == date(13))
        #expect(groupDrag.preview(for: "b")?.start == date(12))
    }

    @Test func resetClearsOriginalAndPreviewTimes() {
        var groupDrag = TimelineGroupDrag()
        groupDrag.begin(selectedIds: ["a"], slots: [slot(id: "a", start: date(9), end: date(10))])

        groupDrag.reset()

        #expect(!groupDrag.isActive)
        #expect(groupDrag.originalTimes.isEmpty)
        #expect(groupDrag.previewTimes.isEmpty)
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

    private func date(_ hour: Int) -> Date {
        let base = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 13))!
        return base.addingTimeInterval(TimeInterval(hour) * 3_600)
    }
}
