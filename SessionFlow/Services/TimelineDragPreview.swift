import CoreGraphics
import Foundation

enum TimelineDragMode: Equatable {
    case none
    case move
    case resizeTop
    case resizeBottom
}

struct TimelineDragPreview {
    struct TimeRange: Equatable {
        let start: Date
        let end: Date
    }

    static let minimumDuration: TimeInterval = 5 * 60

    static func mode(
        startY: CGFloat,
        blockHeight: CGFloat,
        edgeZone: CGFloat,
        canResize: Bool
    ) -> TimelineDragMode {
        guard canResize else { return .move }

        if startY < edgeZone {
            return .resizeTop
        }
        if startY > blockHeight - edgeZone {
            return .resizeBottom
        }
        return .move
    }

    static func timeRange(
        mode: TimelineDragMode,
        originalStart: Date,
        originalEnd: Date,
        translationY: CGFloat,
        yPosition: (Date) -> CGFloat,
        dateFromYOffset: (CGFloat) -> Date,
        snap: (Date) -> Date,
        clampStart: (Date) -> Date,
        preservesRawTime: Bool
    ) -> TimeRange? {
        switch mode {
        case .move:
            let duration = originalEnd.timeIntervalSince(originalStart)
            let originalY = yPosition(originalStart)
            let rawDate = dateFromYOffset(originalY + translationY)
            let snapped = preservesRawTime ? rawDate : snap(rawDate)
            let newStart = clampStart(snapped)
            return TimeRange(start: newStart, end: newStart.addingTimeInterval(duration))

        case .resizeTop:
            let originalY = yPosition(originalStart)
            let rawDate = dateFromYOffset(originalY + translationY)
            let snapped = preservesRawTime ? rawDate : snap(rawDate)
            let newStart = clampStart(snapped)
            let maxStart = originalEnd.addingTimeInterval(-minimumDuration)
            return TimeRange(start: min(newStart, maxStart), end: originalEnd)

        case .resizeBottom:
            let originalY = yPosition(originalEnd)
            let rawDate = dateFromYOffset(originalY + translationY)
            let newEnd = preservesRawTime ? rawDate : snap(rawDate)
            let minEnd = originalStart.addingTimeInterval(minimumDuration)
            return TimeRange(start: originalStart, end: max(newEnd, minEnd))

        case .none:
            return nil
        }
    }
}
