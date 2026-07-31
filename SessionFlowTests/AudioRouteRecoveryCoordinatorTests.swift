import Foundation
import Testing
@testable import SessionFlow

struct AudioRouteRecoveryCoordinatorTests {
    @Test func repeatedSleepWakeBurstsCoalesceToOneRecovery() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        for _ in 0..<100 {
            coordinator.suspend(reason: .systemSleep)
            coordinator.suspend(reason: .screenSleep)
            coordinator.suspend(reason: .inactiveSession)
            coordinator.resume(reason: .systemSleep, delay: 2.0) { recoveryCount += 1 }
            coordinator.resume(reason: .screenSleep, delay: 2.0) { recoveryCount += 1 }
            coordinator.resume(reason: .inactiveSession, delay: 1.0) { recoveryCount += 1 }
        }

        scheduler.runAll()

        #expect(recoveryCount == 1)
    }

    @Test func aNewSleepCancelsPendingWakeRecovery() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        coordinator.suspend(reason: .systemSleep)
        coordinator.resume(reason: .systemSleep, delay: 2.0) { recoveryCount += 1 }
        coordinator.suspend(reason: .screenSleep)
        scheduler.runAll()

        #expect(recoveryCount == 0)
    }

    @Test func configurationChangesDuringSleepDoNotScheduleRecovery() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        coordinator.suspend(reason: .systemSleep)
        for _ in 0..<100 {
            coordinator.scheduleWhileActive(delay: 0.75) { recoveryCount += 1 }
        }
        scheduler.runAll()

        #expect(recoveryCount == 0)
        #expect(scheduler.scheduledCount == 0)
    }

    @Test func repeatedConfigurationChangesCoalesceToOneRecovery() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        for _ in 0..<100 {
            coordinator.scheduleWhileActive(delay: 0.75) { recoveryCount += 1 }
        }
        scheduler.runAll()

        #expect(recoveryCount == 1)
    }

    @Test func staleRecoveryCannotRunWhenSchedulerStillDeliversCancelledWork() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        coordinator.suspend(reason: .systemSleep)
        coordinator.resume(reason: .systemSleep, delay: 2.0) { recoveryCount += 1 }
        coordinator.suspend(reason: .screenSleep)
        coordinator.resume(reason: .screenSleep, delay: 1.0) { recoveryCount += 1 }
        scheduler.runAll(includingCancelled: true)

        #expect(recoveryCount == 1)
    }

    @Test func eachCompletedSleepWakeCycleRecoversOnce() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        for _ in 0..<100 {
            coordinator.suspend(reason: .systemSleep)
            coordinator.suspend(reason: .screenSleep)
            coordinator.suspend(reason: .inactiveSession)
            coordinator.resume(reason: .systemSleep, delay: 2.0) { recoveryCount += 1 }
            coordinator.resume(reason: .screenSleep, delay: 2.0) { recoveryCount += 1 }
            coordinator.resume(reason: .inactiveSession, delay: 1.0) { recoveryCount += 1 }
            scheduler.runAll()
        }

        #expect(recoveryCount == 100)
    }

    @Test func overlappingSuspensionsWaitForEveryMatchingResume() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        coordinator.suspend(reason: .systemSleep)
        coordinator.suspend(reason: .screenSleep)
        coordinator.resume(reason: .systemSleep, delay: 2.0) { recoveryCount += 1 }
        scheduler.runAll()

        #expect(recoveryCount == 0)
        #expect(scheduler.scheduledCount == 0)

        coordinator.resume(reason: .screenSleep, delay: 1.0) { recoveryCount += 1 }

        #expect(scheduler.scheduledDelays == [2.0])
        scheduler.runAll()

        #expect(recoveryCount == 1)
    }

    @Test func unmatchedAndDuplicateResumeNotificationsAreIgnored() {
        let scheduler = ManualRecoveryScheduler()
        let coordinator = AudioRouteRecoveryCoordinator(scheduler: scheduler.schedule)
        var recoveryCount = 0

        let unmatched = coordinator.resume(reason: .systemSleep, delay: 2.0) { recoveryCount += 1 }
        coordinator.suspend(reason: .screenSleep)
        coordinator.suspend(reason: .inactiveSession)
        let waiting = coordinator.resume(reason: .screenSleep, delay: 2.0) { recoveryCount += 1 }
        let scheduled = coordinator.resume(reason: .inactiveSession, delay: 2.0) { recoveryCount += 1 }
        let duplicate = coordinator.resume(reason: .inactiveSession, delay: 1.0) { recoveryCount += 1 }
        scheduler.runAll()

        #expect(unmatched == .ignored)
        #expect(waiting == .waiting)
        #expect(scheduled == .scheduled)
        #expect(duplicate == .ignored)
        #expect(recoveryCount == 1)
        #expect(scheduler.scheduledCount == 0)
    }
}

private final class ManualRecoveryScheduler {
    private struct Job {
        let id: Int
        let delay: TimeInterval
        let operation: () -> Void
    }

    private var jobs: [Job] = []
    private var cancelledIDs: Set<Int> = []
    private var nextID = 0

    var scheduledCount: Int { jobs.count }
    var scheduledDelays: [TimeInterval] { jobs.map(\.delay) }

    func schedule(delay: TimeInterval, operation: @escaping () -> Void) -> () -> Void {
        let id = nextID
        nextID += 1
        jobs.append(Job(id: id, delay: delay, operation: operation))
        return { [weak self] in self?.cancelledIDs.insert(id) }
    }

    func runAll(includingCancelled: Bool = false) {
        let scheduledJobs = jobs
        jobs.removeAll()
        for job in scheduledJobs where includingCancelled || !cancelledIDs.contains(job.id) {
            job.operation()
        }
        cancelledIDs.subtract(scheduledJobs.map(\.id))
    }
}
