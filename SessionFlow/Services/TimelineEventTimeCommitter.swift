import Foundation

protocol TimelineEventTimeCommitting: AnyObject {
    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool
}

extension CalendarService: TimelineEventTimeCommitting {}

enum TimelineEventTimeCommitter {
    struct Target: Equatable {
        let eventId: String
        let oldStart: Date
        let oldEnd: Date
        let newStart: Date
        let newEnd: Date
        let description: String

        var hasChanges: Bool {
            oldStart != newStart || oldEnd != newEnd
        }
    }

    struct EventTimeUpdate: Equatable {
        let eventId: String
        let newStart: Date
        let newEnd: Date
    }

    struct Result: Equatable {
        var undoChanges: [EventUndoManager.EventTimeChange] = []
        var optimisticUpdates: [EventTimeUpdate] = []
        var shouldFetchEvents = false
    }

    static func commit(
        _ targets: [Target],
        calendar: TimelineEventTimeCommitting
    ) -> Result {
        var result = Result()

        for target in targets where target.hasChanges {
            result.shouldFetchEvents = true

            guard calendar.updateEventTime(
                eventId: target.eventId,
                newStart: target.newStart,
                newEnd: target.newEnd
            ) else {
                continue
            }

            result.undoChanges.append(EventUndoManager.EventTimeChange(
                eventId: target.eventId,
                oldStartTime: target.oldStart,
                oldEndTime: target.oldEnd,
                newStartTime: target.newStart,
                newEndTime: target.newEnd,
                description: target.description
            ))
            result.optimisticUpdates.append(EventTimeUpdate(
                eventId: target.eventId,
                newStart: target.newStart,
                newEnd: target.newEnd
            ))
        }

        return result
    }
}
