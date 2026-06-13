import Foundation

struct TimelineGroupDrag {
    typealias TimeRange = (start: Date, end: Date)

    private(set) var originalTimes: [String: TimeRange] = [:]
    private(set) var previewTimes: [String: TimeRange] = [:]

    var isActive: Bool {
        !originalTimes.isEmpty
    }

    func contains(_ slotId: String) -> Bool {
        originalTimes[slotId] != nil
    }

    func preview(for slotId: String) -> TimeRange? {
        previewTimes[slotId]
    }

    mutating func begin(selectedIds: Set<String>, slots: [BusyTimeSlot]) {
        let slotsById = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, $0) })
        originalTimes = Dictionary(uniqueKeysWithValues: selectedIds.compactMap { id in
            guard let slot = slotsById[id] else { return nil }
            return (id, (start: slot.startTime, end: slot.endTime))
        })
        previewTimes = originalTimes
    }

    @discardableResult
    mutating func updateTranslation(from originalStart: Date, to newStart: Date) -> [String: TimeRange] {
        let translation = newStart.timeIntervalSince(originalStart)
        previewTimes = originalTimes.mapValues { original in
            (
                start: original.start.addingTimeInterval(translation),
                end: original.end.addingTimeInterval(translation)
            )
        }
        return previewTimes
    }

    mutating func reset() {
        originalTimes.removeAll()
        previewTimes.removeAll()
    }
}
