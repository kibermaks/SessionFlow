import Testing
import Foundation
@testable import SessionFlow

extension MCPFeatureTests {
    private func makeCoordinator(_ configure: (SchedulingEngine) -> Void = { _ in })
        -> (ScheduleCoordinator, SchedulingEngine, FakeCalendarStore) {
        let engine = SchedulingEngine()
        configure(engine)
        let calendar = FakeCalendarStore()
        return (ScheduleCoordinator(engine: engine, calendar: calendar), engine, calendar)
    }

    @Test func regeneratePreviewProducesSessionsAndFetches() async {
        let (coordinator, engine, calendar) = makeCoordinator { engine in
            engine.workSessions = 3
            engine.sideSessions = 0
            engine.schedulePlanning = false
            engine.scheduleEndHour = 28
        }
        let date = Calendar.current.startOfDay(for: Date())
        let sessions = await coordinator.regeneratePreview(date: date, startTime: nil)
        #expect(!sessions.isEmpty)
        #expect(engine.projectedSessions.count == sessions.count)
        #expect(calendar.scheduleEndHour == 28)
        #expect(calendar.fetchedDates.contains { Calendar.current.isDate($0, inSameDayAs: date) })
    }

    @Test func commitCreatesSessionsAndClearsPreview() async {
        let (coordinator, engine, calendar) = makeCoordinator { engine in
            engine.workSessions = 2
            engine.sideSessions = 0
            engine.schedulePlanning = false
        }
        let date = Calendar.current.startOfDay(for: Date())
        _ = await coordinator.regeneratePreview(date: date, startTime: nil)
        engine.sessionsFrozen = true
        let result = await coordinator.commit(date: date)
        #expect(result.success > 0)
        #expect(!calendar.createdSessions.isEmpty)
        #expect(engine.projectedSessions.isEmpty)
        #expect(engine.sessionsFrozen == false)
    }

    @Test func deleteFutureUsesFutureDeletion() async {
        let (coordinator, _, calendar) = makeCoordinator()
        calendar.deleteResult = (4, 0)
        let result = await coordinator.deleteSessions(date: Date(), scope: .future)
        #expect(result.deleted == 4)
        #expect(calendar.deleteCalls.count == 1)
        #expect(calendar.deleteCalls.first?.future == true)
    }

    @Test func deleteAllUsesWholeDayDeletion() async {
        let (coordinator, _, calendar) = makeCoordinator()
        _ = await coordinator.deleteSessions(date: Date(), scope: .all)
        #expect(calendar.deleteCalls.first?.future == false)
    }

    @Test func defaultStartTimeUsesConfiguredHourForFutureDates() {
        let (coordinator, engine, _) = makeCoordinator { engine in engine.defaultStartHour = 8 }
        let future = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let start = coordinator.defaultStartTime(for: future)
        #expect(Calendar.current.component(.hour, from: start) == engine.defaultStartHour)
    }
}
