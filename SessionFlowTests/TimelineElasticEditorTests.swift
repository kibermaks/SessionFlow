import Foundation
import SwiftUI
import Testing
@testable import SessionFlow

struct TimelineElasticEditorTests {
    @Test func beginInitializesSessionStateAndGapMap() {
        var editor = TimelineElasticEditor()
        let slots = [
            slot(id: "a", title: "A", start: date(9), end: date(10)),
            slot(id: "b", title: "B", start: date(11), end: date(12))
        ]

        editor.begin(with: slots, mode: .pushDown)

        #expect(editor.isEditing)
        #expect(editor.stagedSlots.map(\.id) == ["a", "b"])
        #expect(editor.displacementMode == .pushDown)
        #expect(editor.emptySpaceAfterBySlotId["a"] == 3_600)
        #expect(!editor.canUndo)
        #expect(!editor.canRedo)
    }

    @Test func timeChangesCompareOriginalAndStagedSlotsInOriginalOrder() {
        var editor = TimelineElasticEditor()
        let slots = [
            slot(id: "a", title: "Alpha", start: date(9), end: date(10)),
            slot(id: "b", title: "Beta", start: date(10), end: date(11))
        ]
        editor.begin(with: slots, mode: .bubble)
        editor.stagedSlots = [
            slot(id: "b", title: "Beta", start: date(12), end: date(13)),
            slot(id: "a", title: "Alpha", start: date(11), end: date(12))
        ]

        let changes = editor.timeChanges()

        #expect(changes.map(\.eventId) == ["a", "b"])
        #expect(changes.map(\.description) == ["Elastic move Alpha", "Elastic move Beta"])
        #expect(editor.changeCount == 2)
    }

    @Test func undoRedoRestoreSlotsAndGapMaps() {
        var editor = TimelineElasticEditor()
        let original = [
            slot(id: "a", title: "A", start: date(9), end: date(10)),
            slot(id: "b", title: "B", start: date(10), end: date(11))
        ]
        let moved = [
            slot(id: "a", title: "A", start: date(12), end: date(13)),
            slot(id: "b", title: "B", start: date(13), end: date(14))
        ]

        editor.begin(with: original, mode: .bubble)
        editor.emptySpaceAfterBySlotId = ["a": 60]
        editor.recordUndoSnapshot(original)
        editor.stagedSlots = moved
        editor.emptySpaceAfterBySlotId = ["a": 120]

        let didUndo = editor.undo()
        #expect(didUndo)
        #expect(editor.stagedSlots.map(\.startTime) == original.map(\.startTime))
        #expect(editor.emptySpaceAfterBySlotId["a"] == 60)
        #expect(editor.canRedo)

        let didRedo = editor.redo()
        #expect(didRedo)
        #expect(editor.stagedSlots.map(\.startTime) == moved.map(\.startTime))
        #expect(editor.emptySpaceAfterBySlotId["a"] == 120)
        #expect(editor.canUndo)
    }

    @Test func preDragSnapshotCanBeRestoredAndCleared() {
        var editor = TimelineElasticEditor()
        let original = [slot(id: "a", title: "A", start: date(9), end: date(10))]
        let moved = [slot(id: "a", title: "A", start: date(10), end: date(11))]

        editor.begin(with: original, mode: .bubble)
        editor.capturePreDragSnapshot()
        editor.stagedSlots = moved

        let restored = editor.restorePreDragSnapshot()
        #expect(restored?.map(\.startTime) == Optional(original.map(\.startTime)))
        #expect(editor.stagedSlots.map(\.startTime) == original.map(\.startTime))

        editor.clearPreDragSnapshot()
        let restoredAfterClear = editor.restorePreDragSnapshot()
        #expect(restoredAfterClear == nil)
    }

    @Test func resetClearsAllSessionState() {
        var editor = TimelineElasticEditor()
        let slots = [slot(id: "a", title: "A", start: date(9), end: date(10))]

        editor.begin(with: slots, mode: .pushDown)
        editor.capturePreDragSnapshot()
        editor.recordUndoSnapshot(slots)
        editor.reset()

        #expect(!editor.isEditing)
        #expect(editor.stagedSlots.isEmpty)
        #expect(editor.preDragSlots == nil)
        #expect(!editor.canUndo)
        #expect(!editor.canRedo)
        #expect(editor.emptySpaceAfterBySlotId.isEmpty)
    }

    @Test func undoStackKeepsMostRecentFiftySnapshots() {
        var editor = TimelineElasticEditor()
        let base = [slot(id: "base", title: "Base", start: date(8), end: date(9))]

        editor.begin(with: base, mode: .bubble)
        for index in 0..<55 {
            editor.recordUndoSnapshot([
                slot(id: "\(index)", title: "\(index)", start: date(8 + index), end: date(9 + index))
            ])
        }

        #expect(editor.undoStack.count == 50)
        #expect(editor.undoStack.first?.slots.first?.id == "5")
        #expect(editor.undoStack.last?.slots.first?.id == "54")
    }

    private func slot(id: String, title: String, start: Date, end: Date) -> BusyTimeSlot {
        BusyTimeSlot(
            id: id,
            title: title,
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
