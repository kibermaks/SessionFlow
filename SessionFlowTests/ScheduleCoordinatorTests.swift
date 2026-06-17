import Testing
import Foundation
import SwiftUI
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

    @Test func daySnapshotConcentratesCalendarDayFacts() async {
        let (coordinator, engine, calendar) = makeCoordinator { engine in
            engine.workSessions = 1
            engine.sideSessions = 0
            engine.schedulePlanning = true
            engine.scheduleEndHour = 26
        }
        let date = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let busyStart = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: date)!
        calendar.busySlots = [
            BusyTimeSlot(
                id: "busy",
                title: "Busy",
                startTime: busyStart,
                endTime: busyStart.addingTimeInterval(1800),
                calendarName: "Work",
                calendarColor: .blue
            )
        ]
        calendar.planningExists = true
        calendar.existingCounts = (work: 1, side: 0, deep: 0, titles: ["Busy"])

        let snapshot = await coordinator.daySnapshot(date: date, startTime: start)

        #expect(snapshot.planningExists)
        #expect(snapshot.busySlots.map(\.id) == ["busy"])
        #expect(snapshot.existingSessions.work == 1)
        #expect(snapshot.existingSessions.titles == ["Busy"])
        #expect(snapshot.availability.availableMinutes > 0)
        #expect(calendar.scheduleEndHour == 26)
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
        #expect(engine.projectedSessionsDate == nil)
        #expect(engine.sessionsFrozen == false)
    }

    @Test func commitRejectsPreviewFromDifferentDate() async {
        let (coordinator, engine, calendar) = makeCoordinator { engine in
            engine.workSessions = 2
            engine.sideSessions = 0
            engine.schedulePlanning = false
        }
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let otherDate = cal.date(byAdding: .day, value: 1, to: date)!
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!

        _ = await coordinator.regeneratePreview(date: date, startTime: start)
        let previewCount = engine.projectedSessions.filter { $0.type != .bigRest }.count
        let result = await coordinator.commit(date: otherDate)

        #expect(result.success == 0)
        #expect(result.failed == previewCount)
        #expect(calendar.createdSessions.isEmpty)
        #expect(!engine.projectedSessions.isEmpty)
        #expect(engine.projectedSessionsDate.map { cal.isDate($0, inSameDayAs: date) } == true)
        #expect(engine.schedulingMessage == "Regenerate the schedule for this day before scheduling.")
    }

    @Test func projectSingleSessionUsesCentralOwnershipTags() {
        let (_, engine, _) = makeCoordinator()
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!

        for type in SessionType.allCases {
            let session = engine.projectSingleSession(type: type, startTime: start, baseDate: date, busySlots: [])
            #expect(session?.notes == SessionFlowEventSemantics.ownershipTag(for: type).rawValue)
        }
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
