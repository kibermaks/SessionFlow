import Foundation
import Testing
@testable import SessionFlow

@MainActor
struct SessionAwarenessServiceTests {
    @Test func accelerandoPlaybackRateStartsAtCurrentProgress() {
        let rate = SessionAudioService.playbackRate(
            progress: 0.5,
            accelerando: .init(enabled: true, maxMultiplier: 2.0)
        )

        #expect(abs(rate - 1.5) < 0.001)
    }

    @Test func fixedPlaybackRateUsesMultiplierWhenAccelerandoIsOff() {
        let rate = SessionAudioService.playbackRate(
            progress: 0.8,
            accelerando: .init(enabled: false, maxMultiplier: 1.7)
        )

        #expect(abs(rate - 1.7) < 0.001)
    }

    @Test func commitModeStartPausesLifecycleEvenWhenGoalsAreOptional() {
        var config = SessionAwarenessConfig()
        config.harshModeEnabled = true
        config.harshModeRequireStartGoals = false

        #expect(SessionAwarenessService.shouldPauseHarshStartLifecycle(
            config: config,
            sessionType: .work,
            isBusySlot: false,
            startAccepted: false,
            startBypassed: false
        ))
    }

    @Test func commitModeStartDoesNotPauseAfterStartIsAccepted() {
        var config = SessionAwarenessConfig()
        config.harshModeEnabled = true
        config.harshModeRequireStartGoals = false

        #expect(!SessionAwarenessService.shouldPauseHarshStartLifecycle(
            config: config,
            sessionType: .work,
            isBusySlot: false,
            startAccepted: true,
            startBypassed: false
        ))
    }

    @Test func commitModeStartPromptIgnoresExistingGoalsUntilStartIsSubmitted() {
        var config = SessionAwarenessConfig()
        config.harshModeEnabled = true
        config.harshModeRequireStartGoals = false
        let notesWithGoals = HarshModeSessionNotes.applyingGoals(["Already planned"], to: "#work")

        let startAccepted = SessionAwarenessService.hasSubmittedHarshStart(startSubmissionRecorded: false)

        #expect(SessionAwarenessService.shouldPauseHarshStartLifecycle(
            config: config,
            sessionType: .work,
            isBusySlot: false,
            startAccepted: startAccepted,
            startBypassed: false
        ))
        #expect(SessionAwarenessService.hasCompletedHarshStartForEndGate(
            notes: notesWithGoals,
            startSubmissionRecorded: false
        ))
    }

    @Test func commitModeStartPromptIdentityChangesWhenSessionStartMoves() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40 * 60)
        let movedStart = start.addingTimeInterval(2 * 60 * 60)
        let movedEnd = movedStart.addingTimeInterval(40 * 60)

        let originalID = HarshModePrompt.id(eventId: "event", phase: .start, startTime: start, endTime: end)
        let movedID = HarshModePrompt.id(eventId: "event", phase: .start, startTime: movedStart, endTime: movedEnd)

        #expect(originalID != movedID)
    }

    @Test func commitModeStartPromptIdentityIgnoresEndOnlyResize() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40 * 60)
        let resizedEnd = start.addingTimeInterval(90 * 60)

        let originalID = HarshModePrompt.id(eventId: "event", phase: .start, startTime: start, endTime: end)
        let resizedID = HarshModePrompt.id(eventId: "event", phase: .start, startTime: start, endTime: resizedEnd)

        #expect(originalID == resizedID)
    }

    @Test func commitModeStartPromptExpiresAtSessionEnd() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40 * 60)
        let startPrompt = HarshModePrompt(
            phase: .start,
            eventId: "event",
            sessionTitle: "Work",
            sessionType: .work,
            startTime: start,
            endTime: end,
            notes: "#work",
            nextTaskTitle: nil,
            nextTaskStartTime: nil
        )
        let endPrompt = HarshModePrompt(
            phase: .end,
            eventId: "event",
            sessionTitle: "Work",
            sessionType: .work,
            startTime: start,
            endTime: end,
            notes: "#work",
            nextTaskTitle: nil,
            nextTaskStartTime: nil
        )

        #expect(!SessionAwarenessService.shouldDismissHarshStartPromptAtEnd(
            prompt: startPrompt,
            now: end.addingTimeInterval(-1)
        ))
        #expect(SessionAwarenessService.shouldDismissHarshStartPromptAtEnd(
            prompt: startPrompt,
            now: end
        ))
        #expect(!SessionAwarenessService.shouldDismissHarshStartPromptAtEnd(
            prompt: endPrompt,
            now: end.addingTimeInterval(1)
        ))
    }

    @Test func commitModeEndPromptIdentityTracksFullInterval() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40 * 60)
        let resizedEnd = start.addingTimeInterval(90 * 60)

        let originalID = HarshModePrompt.id(eventId: "event", phase: .end, startTime: start, endTime: end)
        let resizedID = HarshModePrompt.id(eventId: "event", phase: .end, startTime: start, endTime: resizedEnd)

        #expect(originalID != resizedID)
    }

    @Test func commitModeStartAcceptsEmptyGoalsWhenGoalsAreOptional() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let service = SessionAwarenessService()
        service.config.harshModeRequireStartGoals = false
        service.config.harshModeMinimumGoals = 3
        service.debugPresentHarshModeStartPrompt()

        #expect(service.submitHarshGoals(title: "Focus block", goals: []))
    }

    @Test func commitModeStartRejectsEmptyGoalsWhenGoalsAreRequired() {
        let sandbox = DefaultsSandbox()
        defer { sandbox.restore() }

        let service = SessionAwarenessService()
        service.config.harshModeRequireStartGoals = true
        service.config.harshModeMinimumGoals = 1
        service.debugPresentHarshModeStartPrompt()

        #expect(!service.submitHarshGoals(title: "Focus block", goals: []))
    }

    @Test func commitModeEndPromptPlaysEndSoundWhenSessionWasAudible() {
        #expect(SessionAwarenessService.shouldPlayHarshEndPromptSound(
            isEnabled: true,
            wasSessionMuted: false,
            endSound: .init(sound: "Gong", volume: 0.6)
        ))
    }

    @Test func commitModeEndPromptDoesNotPlayEndSoundWhenMutedDisabledOrOff() {
        #expect(!SessionAwarenessService.shouldPlayHarshEndPromptSound(
            isEnabled: true,
            wasSessionMuted: true,
            endSound: .init(sound: "Gong", volume: 0.6)
        ))
        #expect(!SessionAwarenessService.shouldPlayHarshEndPromptSound(
            isEnabled: false,
            wasSessionMuted: false,
            endSound: .init(sound: "Gong", volume: 0.6)
        ))
        #expect(!SessionAwarenessService.shouldPlayHarshEndPromptSound(
            isEnabled: true,
            wasSessionMuted: false,
            endSound: .off
        ))
    }
}
