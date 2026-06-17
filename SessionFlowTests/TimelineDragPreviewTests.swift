import CoreGraphics
import Foundation
import Testing
@testable import SessionFlow

struct TimelineDragPreviewTests {
    @Test func modeDetectsResizeZonesAndMoveZone() {
        #expect(TimelineDragPreview.mode(startY: 2, blockHeight: 80, edgeZone: 8, canResize: true) == .resizeTop)
        #expect(TimelineDragPreview.mode(startY: 78, blockHeight: 80, edgeZone: 8, canResize: true) == .resizeBottom)
        #expect(TimelineDragPreview.mode(startY: 40, blockHeight: 80, edgeZone: 8, canResize: true) == .move)
    }

    @Test func modeUsesMoveWhenResizeIsDisabled() {
        #expect(TimelineDragPreview.mode(startY: 2, blockHeight: 80, edgeZone: 8, canResize: false) == .move)
        #expect(TimelineDragPreview.mode(startY: 78, blockHeight: 80, edgeZone: 8, canResize: false) == .move)
    }

    @Test func movePreservesDurationAndAppliesSnapAndClamp() {
        let range = TimelineDragPreview.timeRange(
            mode: .move,
            originalStart: date(9, 0),
            originalEnd: date(10, 0),
            translationY: 46,
            yPosition: yPosition,
            dateFromYOffset: dateFromYOffset,
            snap: snapToHour,
            clampStart: { max($0, date(9, 30)) },
            preservesRawTime: false
        )

        #expect(range?.start == date(10, 0))
        #expect(range?.end == date(11, 0))
    }

    @Test func rawMoveSkipsSnappingButStillClampsStart() {
        let range = TimelineDragPreview.timeRange(
            mode: .move,
            originalStart: date(9, 0),
            originalEnd: date(10, 0),
            translationY: 30,
            yPosition: yPosition,
            dateFromYOffset: dateFromYOffset,
            snap: snapToHour,
            clampStart: { max($0, date(10, 0)) },
            preservesRawTime: true
        )

        #expect(range?.start == date(10, 0))
        #expect(range?.end == date(11, 0))
    }

    @Test func resizeTopAppliesMinimumDuration() {
        let range = TimelineDragPreview.timeRange(
            mode: .resizeTop,
            originalStart: date(9, 0),
            originalEnd: date(10, 0),
            translationY: 90,
            yPosition: yPosition,
            dateFromYOffset: dateFromYOffset,
            snap: snapToHour,
            clampStart: { $0 },
            preservesRawTime: false
        )

        #expect(range?.start == date(9, 55))
        #expect(range?.end == date(10, 0))
    }

    @Test func resizeBottomAppliesMinimumDuration() {
        let range = TimelineDragPreview.timeRange(
            mode: .resizeBottom,
            originalStart: date(9, 0),
            originalEnd: date(10, 0),
            translationY: -90,
            yPosition: yPosition,
            dateFromYOffset: dateFromYOffset,
            snap: snapToHour,
            clampStart: { $0 },
            preservesRawTime: false
        )

        #expect(range?.start == date(9, 0))
        #expect(range?.end == date(9, 5))
    }

    @Test func noneProducesNoPreview() {
        let range = TimelineDragPreview.timeRange(
            mode: .none,
            originalStart: date(9, 0),
            originalEnd: date(10, 0),
            translationY: 90,
            yPosition: yPosition,
            dateFromYOffset: dateFromYOffset,
            snap: snapToHour,
            clampStart: { $0 },
            preservesRawTime: false
        )

        #expect(range == nil)
    }

    private func yPosition(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / 60)
    }

    private func dateFromYOffset(_ y: CGFloat) -> Date {
        dayStart.addingTimeInterval(TimeInterval(y) * 60)
    }

    private func snapToHour(_ date: Date) -> Date {
        let minutes = date.timeIntervalSince(dayStart) / 60
        let snapped = (minutes / 60).rounded() * 60
        return dayStart.addingTimeInterval(snapped * 60)
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        dayStart.addingTimeInterval(TimeInterval(hour * 60 + minute) * 60)
    }

    private var dayStart: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: 13))!
    }
}
