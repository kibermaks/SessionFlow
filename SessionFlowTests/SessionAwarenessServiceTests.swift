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
