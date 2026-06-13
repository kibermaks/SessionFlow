import Foundation
import SwiftUI
import Testing
@testable import SessionFlow

struct TimelineEditPlannerTests {
    @Test func bubbleDisplacementCompressesGapConsumedByDraggedSlot() {
        let base = Calendar.current.startOfDay(for: Date())
        let nine = base.addingTimeInterval(9 * 3600)
        let tenFifteen = base.addingTimeInterval(10 * 3600 + 15 * 60)
        let slots = [
            slot(id: "dragged", start: nine, end: nine.addingTimeInterval(3600)),
            slot(id: "next", start: tenFifteen, end: tenFifteen.addingTimeInterval(1800)),
        ]
        let updates = [
            "dragged": (
                start: base.addingTimeInterval(10 * 3600),
                end: base.addingTimeInterval(11 * 3600)
            )
        ]

        let displaced = TimelineEditPlanner.displaceBusySlots(
            baseSlots: slots,
            draggedUpdates: updates,
            commitDraggedSlots: true,
            existingGapMap: TimelineEditPlanner.calculateEmptySpaceAfterBySlotId(for: slots),
            mode: .bubble,
            floor: base
        )

        #expect(displaced.first { $0.id == "dragged" }?.startTime == updates["dragged"]?.start)
        #expect(displaced.first { $0.id == "next" }?.startTime == base.addingTimeInterval(11 * 3600))
    }

    @Test func pushDownUsesPositiveDraggedTranslationForDownstreamCollision() {
        let base = Calendar.current.startOfDay(for: Date())
        let nine = base.addingTimeInterval(9 * 3600)
        let tenThirty = base.addingTimeInterval(10 * 3600 + 30 * 60)
        let slots = [
            slot(id: "dragged", start: nine, end: nine.addingTimeInterval(3600)),
            slot(id: "next", start: tenThirty, end: tenThirty.addingTimeInterval(1800)),
        ]
        let updates = [
            "dragged": (
                start: base.addingTimeInterval(10 * 3600),
                end: base.addingTimeInterval(11 * 3600)
            )
        ]

        let displaced = TimelineEditPlanner.displaceBusySlots(
            baseSlots: slots,
            draggedUpdates: updates,
            commitDraggedSlots: true,
            existingGapMap: TimelineEditPlanner.calculateEmptySpaceAfterBySlotId(for: slots),
            mode: .pushDown,
            floor: base
        )

        #expect(displaced.first { $0.id == "next" }?.startTime == base.addingTimeInterval(11 * 3600 + 30 * 60))
    }

    private func slot(id: String, start: Date, end: Date) -> BusyTimeSlot {
        BusyTimeSlot(
            id: id,
            title: id,
            startTime: start,
            endTime: end,
            notes: "#work",
            calendarName: "Work",
            calendarColor: .blue
        )
    }
}
