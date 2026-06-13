import Foundation

struct TimelineElasticEditor {
    struct Snapshot {
        let slots: [BusyTimeSlot]
        let emptySpaceAfterBySlotId: [String: TimeInterval]
    }

    private(set) var originalSlots: [BusyTimeSlot]?
    var stagedSlots: [BusyTimeSlot] = []
    private(set) var preDragSlots: [BusyTimeSlot]?
    private(set) var undoStack: [Snapshot] = []
    private(set) var redoStack: [Snapshot] = []
    var displacementMode: ElasticDisplacementMode = .bubble
    var emptySpaceAfterBySlotId: [String: TimeInterval] = [:]

    var isEditing: Bool {
        originalSlots != nil
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var changeCount: Int {
        timeChanges().count
    }

    mutating func begin(with slots: [BusyTimeSlot], mode: ElasticDisplacementMode) {
        originalSlots = slots
        stagedSlots = slots
        preDragSlots = nil
        emptySpaceAfterBySlotId = TimelineEditPlanner.calculateEmptySpaceAfterBySlotId(for: slots)
        undoStack.removeAll()
        redoStack.removeAll()
        displacementMode = mode
    }

    mutating func reset() {
        originalSlots = nil
        stagedSlots = []
        preDragSlots = nil
        emptySpaceAfterBySlotId = [:]
        undoStack.removeAll()
        redoStack.removeAll()
    }

    mutating func replaceOriginalSlots(_ slots: [BusyTimeSlot]) {
        originalSlots = slots
    }

    mutating func capturePreDragSnapshot() {
        preDragSlots = stagedSlots
    }

    mutating func clearPreDragSnapshot() {
        preDragSlots = nil
    }

    var dragBaseSlots: [BusyTimeSlot] {
        preDragSlots ?? stagedSlots
    }

    mutating func restorePreDragSnapshot() -> [BusyTimeSlot]? {
        guard let preDragSlots else { return nil }
        stagedSlots = preDragSlots
        return preDragSlots
    }

    mutating func recordUndoSnapshot(_ slots: [BusyTimeSlot]) {
        undoStack.append(Snapshot(
            slots: slots,
            emptySpaceAfterBySlotId: emptySpaceAfterBySlotId
        ))
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(Snapshot(
            slots: stagedSlots,
            emptySpaceAfterBySlotId: emptySpaceAfterBySlotId
        ))
        stagedSlots = previous.slots
        emptySpaceAfterBySlotId = previous.emptySpaceAfterBySlotId
        return true
    }

    mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(Snapshot(
            slots: stagedSlots,
            emptySpaceAfterBySlotId: emptySpaceAfterBySlotId
        ))
        stagedSlots = next.slots
        emptySpaceAfterBySlotId = next.emptySpaceAfterBySlotId
        return true
    }

    func adjustedGapMap(
        forDraggedUpdates draggedUpdates: [String: (start: Date, end: Date)],
        in baseSlots: [BusyTimeSlot]
    ) -> [String: TimeInterval] {
        TimelineEditPlanner.adjustedGapMap(
            existingGapMap: emptySpaceAfterBySlotId,
            draggedUpdates: draggedUpdates,
            in: baseSlots
        )
    }

    func displacedSlots(
        baseSlots: [BusyTimeSlot],
        draggedUpdates: [String: (start: Date, end: Date)],
        commitDraggedSlots: Bool,
        gapAfterBySlotId: [String: TimeInterval],
        floor: Date
    ) -> [BusyTimeSlot] {
        TimelineEditPlanner.displaceBusySlots(
            baseSlots: baseSlots,
            draggedUpdates: draggedUpdates,
            commitDraggedSlots: commitDraggedSlots,
            existingGapMap: gapAfterBySlotId,
            mode: displacementMode,
            floor: floor
        )
    }

    func timeChanges() -> [EventUndoManager.EventTimeChange] {
        guard let originalSlots else { return [] }
        let originalsById = Dictionary(uniqueKeysWithValues: originalSlots.map { ($0.id, $0) })

        return stagedSlots
            .compactMap { staged -> EventUndoManager.EventTimeChange? in
                guard let old = originalsById[staged.id],
                      old.startTime != staged.startTime || old.endTime != staged.endTime else {
                    return nil
                }
                return EventUndoManager.EventTimeChange(
                    eventId: staged.id,
                    oldStartTime: old.startTime,
                    oldEndTime: old.endTime,
                    newStartTime: staged.startTime,
                    newEndTime: staged.endTime,
                    description: "Elastic move \(staged.title)"
                )
            }
            .sorted { $0.oldStartTime < $1.oldStartTime }
    }
}
