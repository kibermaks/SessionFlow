import Foundation

enum TimelineBusySlotLayout {
    struct PositionedSlot: Identifiable {
        let slot: BusyTimeSlot
        let column: Int
        var totalColumns: Int

        var id: String { slot.id }
    }

    private struct ActiveSlot {
        let slot: BusyTimeSlot
        let column: Int
    }

    static func positionedSlots(for slots: [BusyTimeSlot]) -> [PositionedSlot] {
        let sortedSlots = slots.sorted { $0.startTime < $1.startTime }
        var positionedSlots: [PositionedSlot] = []
        var activeSlots: [ActiveSlot] = []
        var currentClusterIndices: [Int] = []
        var currentClusterMaxColumns = 0

        func finalizeCluster() {
            guard !currentClusterIndices.isEmpty else { return }
            let totalColumns = max(currentClusterMaxColumns, 1)
            for index in currentClusterIndices {
                positionedSlots[index].totalColumns = totalColumns
            }
            currentClusterIndices.removeAll()
            currentClusterMaxColumns = 0
        }

        for slot in sortedSlots {
            activeSlots.removeAll { active in
                active.slot.endTime <= slot.startTime
            }

            if activeSlots.isEmpty {
                finalizeCluster()
            }

            let usedColumns = Set(activeSlots.map { $0.column })
            var column = 0
            while usedColumns.contains(column) {
                column += 1
            }

            let positionedIndex = positionedSlots.count
            positionedSlots.append(PositionedSlot(slot: slot, column: column, totalColumns: 1))
            activeSlots.append(ActiveSlot(slot: slot, column: column))
            currentClusterIndices.append(positionedIndex)
            currentClusterMaxColumns = max(currentClusterMaxColumns, column + 1)
        }

        finalizeCluster()
        return positionedSlots
    }
}
