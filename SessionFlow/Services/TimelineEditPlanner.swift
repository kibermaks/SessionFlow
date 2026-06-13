import Foundation

enum ElasticDisplacementMode: String, CaseIterable, Identifiable {
    case bubble = "Bubble"
    case pushDown = "Push down"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .bubble: return "Bubble"
        case .pushDown: return "Push"
        }
    }
}

struct TimelineEditPlanner {
    private struct ElasticObstacle {
        let start: Date
        let paddedEnd: Date
    }

    static func busySlot(_ slot: BusyTimeSlot, replacingStart start: Date, end: Date) -> BusyTimeSlot {
        BusyTimeSlot(
            id: slot.id,
            title: slot.title,
            startTime: start,
            endTime: end,
            notes: slot.notes,
            url: slot.url,
            calendarName: slot.calendarName,
            calendarColor: slot.calendarColor,
            calendarIdentifier: slot.calendarIdentifier
        )
    }

    static func applyingTimeUpdates(
        to slots: [BusyTimeSlot],
        updates: [String: (start: Date, end: Date)]
    ) -> [BusyTimeSlot] {
        slots.map { slot in
            guard let update = updates[slot.id] else { return slot }
            return busySlot(slot, replacingStart: update.start, end: update.end)
        }
    }

    static func calculateEmptySpaceAfterBySlotId(for slots: [BusyTimeSlot]) -> [String: TimeInterval] {
        let sortedSlots = slots.sorted {
            if $0.startTime == $1.startTime {
                return $0.endTime < $1.endTime
            }
            return $0.startTime < $1.startTime
        }
        guard sortedSlots.count > 1 else { return [:] }

        var gaps: [String: TimeInterval] = [:]
        for index in sortedSlots.indices.dropLast() {
            let current = sortedSlots[index]
            let next = sortedSlots[sortedSlots.index(after: index)]
            let gap = next.startTime.timeIntervalSince(current.endTime)
            if gap > 0 {
                gaps[current.id] = gap
            }
        }
        return gaps
    }

    static func adjustedGapMap(
        existingGapMap: [String: TimeInterval],
        draggedUpdates: [String: (start: Date, end: Date)],
        in baseSlots: [BusyTimeSlot]
    ) -> [String: TimeInterval] {
        guard !draggedUpdates.isEmpty else { return existingGapMap }

        var adjusted = existingGapMap
        let directlyMovedSlots = applyingTimeUpdates(to: baseSlots, updates: draggedUpdates)
        let directEmptySpaceAfterBySlotId = calculateEmptySpaceAfterBySlotId(for: directlyMovedSlots)

        for (id, preservedGap) in Array(adjusted) {
            let directGap = directEmptySpaceAfterBySlotId[id] ?? 0
            if directGap < preservedGap {
                adjusted[id] = max(0, directGap)
            }
        }

        return adjusted
    }

    static func displaceBusySlots(
        baseSlots: [BusyTimeSlot],
        draggedUpdates: [String: (start: Date, end: Date)],
        commitDraggedSlots: Bool,
        existingGapMap: [String: TimeInterval],
        mode: ElasticDisplacementMode,
        floor: Date
    ) -> [BusyTimeSlot] {
        let gapAfterBySlotId = adjustedGapMap(
            existingGapMap: existingGapMap,
            draggedUpdates: draggedUpdates,
            in: baseSlots
        )

        if mode == .pushDown,
           let pushed = pushDownBusySlots(
            baseSlots: baseSlots,
            draggedUpdates: draggedUpdates,
            commitDraggedSlots: commitDraggedSlots,
            gapAfterBySlotId: gapAfterBySlotId,
            floor: floor
           ) {
            return pushed
        }

        let draggedIds = Set(draggedUpdates.keys)
        var result = commitDraggedSlots
            ? applyingTimeUpdates(to: baseSlots, updates: draggedUpdates)
            : baseSlots

        var causedObstacles = draggedUpdates.map { entry in
            elasticObstacle(
                start: entry.value.start,
                end: entry.value.end,
                gapAfter: gapAfterBySlotId[entry.key] ?? 0
            )
        }
        var allObstacles = causedObstacles

        for slot in baseSlots where !draggedIds.contains(slot.id) {
            if !slot.isFlowFlexible || slot.startTime < floor {
                allObstacles.append(elasticObstacle(for: slot, gapAfterBySlotId: gapAfterBySlotId))
            }
        }

        let candidates = baseSlots
            .filter { !draggedIds.contains($0.id) && $0.isFlowFlexible && $0.startTime >= floor }
            .sorted { $0.startTime < $1.startTime }

        for slot in candidates {
            let duration = slot.endTime.timeIntervalSince(slot.startTime)
            let candidateGapAfter = gapAfterBySlotId[slot.id] ?? 0
            var candidateStart = max(slot.startTime, floor)
            var candidateEnd = slot.endTime
            var moved = false

            while true {
                let causedEnd = elasticBlockingEnd(
                    candidateStart: candidateStart,
                    candidateEnd: candidateEnd,
                    candidateGapAfter: candidateGapAfter,
                    obstacles: causedObstacles
                )

                if let causedEnd {
                    candidateStart = max(causedEnd, floor)
                    candidateEnd = candidateStart.addingTimeInterval(duration)
                    moved = true
                    continue
                }

                let obstacleEnd = elasticBlockingEnd(
                    candidateStart: candidateStart,
                    candidateEnd: candidateEnd,
                    candidateGapAfter: candidateGapAfter,
                    obstacles: allObstacles
                )

                if moved, let obstacleEnd {
                    candidateStart = max(obstacleEnd, floor)
                    candidateEnd = candidateStart.addingTimeInterval(duration)
                    continue
                }

                break
            }

            if moved {
                if let index = result.firstIndex(where: { $0.id == slot.id }) {
                    result[index] = busySlot(slot, replacingStart: candidateStart, end: candidateEnd)
                }
                let obstacle = elasticObstacle(
                    start: candidateStart,
                    end: candidateEnd,
                    gapAfter: candidateGapAfter
                )
                causedObstacles.append(obstacle)
                allObstacles.append(obstacle)
            } else {
                allObstacles.append(elasticObstacle(for: slot, gapAfterBySlotId: gapAfterBySlotId))
            }
        }

        return result
    }

    private static func elasticObstacle(start: Date, end: Date, gapAfter: TimeInterval) -> ElasticObstacle {
        ElasticObstacle(start: start, paddedEnd: end.addingTimeInterval(gapAfter))
    }

    private static func elasticObstacle(
        for slot: BusyTimeSlot,
        gapAfterBySlotId: [String: TimeInterval]
    ) -> ElasticObstacle {
        elasticObstacle(
            start: slot.startTime,
            end: slot.endTime,
            gapAfter: gapAfterBySlotId[slot.id] ?? 0
        )
    }

    private static func elasticBlockingEnd(
        candidateStart: Date,
        candidateEnd: Date,
        candidateGapAfter: TimeInterval,
        obstacles: [ElasticObstacle]
    ) -> Date? {
        let candidatePaddedEnd = candidateEnd.addingTimeInterval(candidateGapAfter)
        return obstacles
            .filter { candidateStart < $0.paddedEnd && candidatePaddedEnd > $0.start }
            .map(\.paddedEnd)
            .max()
    }

    private static func pushDownBusySlots(
        baseSlots: [BusyTimeSlot],
        draggedUpdates: [String: (start: Date, end: Date)],
        commitDraggedSlots: Bool,
        gapAfterBySlotId: [String: TimeInterval],
        floor: Date
    ) -> [BusyTimeSlot]? {
        let draggedIds = Set(draggedUpdates.keys)
        let originalsById = Dictionary(uniqueKeysWithValues: baseSlots.map { ($0.id, $0) })
        let positiveTranslation = draggedUpdates.compactMap { entry -> TimeInterval? in
            guard let original = originalsById[entry.key] else { return nil }
            return entry.value.start.timeIntervalSince(original.startTime)
        }
        .filter { $0 > 0 }
        .max()

        guard let translation = positiveTranslation else { return nil }

        let draggedObstacles = draggedUpdates.map { entry in
            elasticObstacle(
                start: entry.value.start,
                end: entry.value.end,
                gapAfter: gapAfterBySlotId[entry.key] ?? 0
            )
        }
        let pushAnchor = draggedUpdates.keys
            .compactMap { originalsById[$0]?.startTime }
            .min() ?? floor

        let hasDownstreamCollision = baseSlots
            .filter { !draggedIds.contains($0.id) && $0.endTime > floor }
            .contains { slot in
                let candidateGapAfter = gapAfterBySlotId[slot.id] ?? 0
                return elasticBlockingEnd(
                    candidateStart: slot.startTime,
                    candidateEnd: slot.endTime,
                    candidateGapAfter: candidateGapAfter,
                    obstacles: draggedObstacles
                ) != nil
            }

        guard hasDownstreamCollision else { return nil }

        var result = commitDraggedSlots
            ? applyingTimeUpdates(to: baseSlots, updates: draggedUpdates)
            : baseSlots

        var allObstacles = draggedObstacles

        for slot in baseSlots where !draggedIds.contains(slot.id) {
            let isPushCandidate = slot.isFlowFlexible && slot.startTime >= floor && slot.startTime >= pushAnchor
            if !isPushCandidate {
                allObstacles.append(elasticObstacle(for: slot, gapAfterBySlotId: gapAfterBySlotId))
            }
        }

        let candidates = baseSlots
            .filter { !draggedIds.contains($0.id) && $0.isFlowFlexible && $0.startTime >= floor && $0.startTime >= pushAnchor }
            .sorted { $0.startTime < $1.startTime }

        for slot in candidates {
            let duration = slot.endTime.timeIntervalSince(slot.startTime)
            let candidateGapAfter = gapAfterBySlotId[slot.id] ?? 0
            var candidateStart = max(slot.startTime.addingTimeInterval(translation), floor)
            var candidateEnd = candidateStart.addingTimeInterval(duration)

            while let blockerEnd = elasticBlockingEnd(
                candidateStart: candidateStart,
                candidateEnd: candidateEnd,
                candidateGapAfter: candidateGapAfter,
                obstacles: allObstacles
            ) {
                candidateStart = max(blockerEnd, floor)
                candidateEnd = candidateStart.addingTimeInterval(duration)
            }

            if let index = result.firstIndex(where: { $0.id == slot.id }) {
                result[index] = busySlot(slot, replacingStart: candidateStart, end: candidateEnd)
            }
            allObstacles.append(
                elasticObstacle(
                    start: candidateStart,
                    end: candidateEnd,
                    gapAfter: candidateGapAfter
                )
            )
        }

        return result
    }
}
