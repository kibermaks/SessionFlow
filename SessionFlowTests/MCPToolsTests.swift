import Testing
import Foundation
import MCP
@testable import SessionFlow

private func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

extension MCPFeatureTests {
    @Test func listsEveryTool() async throws {
        let server = try await MCPTestServer.start()
        let (tools, _) = try await server.client.listTools()
        let names = Set(tools.map(\.name))
        let expected: Set<String> = [
            "learn", "get_config", "get_state", "list_presets", "get_day",
            "set_tasks", "set_config", "apply_preset", "save_preset",
            "regenerate_schedule", "commit_schedule", "move_session", "resize_session",
            "delete_sessions", "set_freeze",
        ]
        #expect(expected.isSubset(of: names))
        await server.stop()
    }

    @Test func learnReturnsGuide() async throws {
        let server = try await MCPTestServer.start()
        let text = try await server.callText("learn")
        #expect(text.contains("SessionFlow Agent Guide"))
        #expect(text.contains("set_tasks"))
        await server.stop()
    }

    @Test func getConfigReflectsEngine() async throws {
        let server = try await MCPTestServer.start { engine, _ in engine.workSessions = 4 }
        let json = try await server.callJSON("get_config")
        let sessions = json["sessions"] as? [String: Any]
        #expect(sessions?["work"] as? Int == 4)
        await server.stop()
    }

    @Test func setConfigUpdatesEngine() async throws {
        let server = try await MCPTestServer.start()
        _ = try await server.callText("set_config", [
            "workSessions": .int(7),
            "workSessionDuration": .int(25),
            "pattern": .string("All Work First"),
        ])
        #expect(server.engine.workSessions == 7)
        #expect(server.engine.workSessionDuration == 25)
        #expect(server.engine.pattern == .allWorkFirst)
        await server.stop()
    }

    @Test func setConfigClampsHourRangesAndSyncsCalendarWindow() async throws {
        let server = try await MCPTestServer.start()
        _ = try await server.callText("set_config", [
            "dayStartHour": .int(-2),
            "dayEndHour": .int(99),
            "scheduleEndHour": .int(99),
            "defaultStartHour": .int(99),
        ])
        #expect(server.engine.dayStartHour == 0)
        #expect(server.engine.dayEndHour == 24)
        #expect(server.engine.scheduleEndHour == 30)
        #expect(server.engine.defaultStartHour == 23)
        #expect(server.calendar.scheduleEndHour == 30)
        await server.stop()
    }

    @Test func defaultsSandboxDoesNotTouchStandardDefaults() {
        let key = "SessionFlowTests.StandardDefaultsSentinel.\(UUID().uuidString)"

        SessionFlowDefaults.store.set("sandbox", forKey: key)

        #expect(SessionFlowDefaults.store.string(forKey: key) == "sandbox")
        #expect(UserDefaults.standard.string(forKey: key) == nil)
    }

    @Test func setConfigRejectsInvalidPattern() async throws {
        let server = try await MCPTestServer.start()
        await #expect(throws: MCPTestError.self) {
            _ = try await server.callText("set_config", ["pattern": .string("Nonsense")])
        }
        await server.stop()
    }

    @Test func setTasksUpdatesEngine() async throws {
        let server = try await MCPTestServer.start()
        _ = try await server.callText("set_tasks", [
            "work": .array([.string("Email"), .string("Review PRs")]),
            "useWork": .bool(true),
        ])
        #expect(server.engine.workTasks == "Email\nReview PRs")
        #expect(server.engine.useWorkTasks == true)
        await server.stop()
    }

    @Test func regenerateBuildsPreview() async throws {
        let server = try await MCPTestServer.start { engine, _ in
            engine.workSessions = 3
            engine.sideSessions = 0
            engine.schedulePlanning = false
        }
        let json = try await server.callJSON("regenerate_schedule", ["startHour": .int(9)])
        let projected = json["projectedSessions"] as? [[String: Any]] ?? []
        #expect(!projected.isEmpty)
        #expect(!server.engine.projectedSessions.isEmpty)
        await server.stop()
    }

    @Test func commitWritesToCalendar() async throws {
        let server = try await MCPTestServer.start { engine, _ in
            engine.workSessions = 2
            engine.sideSessions = 0
            engine.schedulePlanning = false
        }
        _ = try await server.callText("regenerate_schedule", ["startHour": .int(9)])
        let json = try await server.callJSON("commit_schedule")
        #expect((json["success"] as? Int ?? 0) > 0)
        #expect(!server.calendar.createdSessions.isEmpty)
        #expect(server.engine.projectedSessions.isEmpty)
        await server.stop()
    }

    @Test func deleteSessionsCallsCalendar() async throws {
        let server = try await MCPTestServer.start()
        server.calendar.deleteResult = (5, 0)
        let json = try await server.callJSON("delete_sessions", ["scope": .string("future")])
        #expect(json["deleted"] as? Int == 5)
        #expect(server.calendar.deleteCalls.contains { $0.future })
        await server.stop()
    }

    @Test func setFreezeTogglesEngine() async throws {
        let server = try await MCPTestServer.start()
        _ = try await server.callText("set_freeze", ["frozen": .bool(true)])
        #expect(server.engine.sessionsFrozen == true)
        await server.stop()
    }

    @Test func movePreviewSession() async throws {
        let server = try await MCPTestServer.start { engine, _ in
            engine.workSessions = 2
            engine.sideSessions = 0
            engine.schedulePlanning = false
        }
        _ = try await server.callText("regenerate_schedule", ["startHour": .int(9)])
        let sessionId = try #require(server.engine.projectedSessions.first?.id.uuidString)
        let newStart = Date().addingTimeInterval(3600)
        let newEnd = newStart.addingTimeInterval(1800)
        _ = try await server.callText("move_session", [
            "sessionId": .string(sessionId),
            "newStart": .string(iso(newStart)),
            "newEnd": .string(iso(newEnd)),
        ])
        let moved = try #require(server.engine.projectedSessions.first { $0.id.uuidString == sessionId })
        #expect(abs(moved.startTime.timeIntervalSince(newStart)) < 1)
        await server.stop()
    }

    @Test func moveCommittedEvent() async throws {
        let server = try await MCPTestServer.start()
        let newStart = Date().addingTimeInterval(3600)
        let newEnd = newStart.addingTimeInterval(1800)
        _ = try await server.callText("resize_session", [
            "eventId": .string("event-123"),
            "newStart": .string(iso(newStart)),
            "newEnd": .string(iso(newEnd)),
        ])
        #expect(server.calendar.movedEvents.contains { $0.id == "event-123" })
        await server.stop()
    }

    @Test func savePresetThenApply() async throws {
        let server = try await MCPTestServer.start { engine, _ in engine.workSessions = 6 }
        let saved = try await server.callJSON("save_preset", ["name": .string("Agent Preset")])
        let presetId = try #require(saved["presetId"] as? String)
        #expect(server.engine.currentPresetId?.uuidString == presetId)

        let listed = try await server.callJSON("list_presets")
        let presets = listed["presets"] as? [[String: Any]] ?? []
        #expect(presets.contains { $0["name"] as? String == "Agent Preset" })

        let applied = try await server.callJSON("apply_preset", ["name": .string("Agent Preset")])
        #expect(applied["appliedPreset"] as? String == "Agent Preset")
        await server.stop()
    }

    @Test func presetDecoderAcceptsOlderPresetWithoutNewerFields() throws {
        let json = """
        [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Old Preset",
            "icon": "calendar",
            "workSessionCount": 4,
            "sideSessionCount": 2,
            "workSessionName": "Work",
            "sideSessionName": "Side",
            "workSessionDuration": 45,
            "sideSessionDuration": 30,
            "planningDuration": 10,
            "restDuration": 15,
            "schedulePlanning": true,
            "pattern": "Alternating",
            "workSessionsPerCycle": 2
        }]
        """.data(using: .utf8)!

        let presets = try JSONDecoder().decode([Preset].self, from: json)

        #expect(presets.count == 1)
        #expect(presets[0].name == "Old Preset")
        #expect(presets[0].sideRestDuration == Preset.calculateSideRest(from: 15))
        #expect(presets[0].deepSessionConfig == .default)
        #expect(presets[0].calendarMapping == .default)
    }

    @Test func presetStorageMigratesLegacyTaskSchedulerPresetsKey() {
        let legacy = Preset(name: "Legacy Preset", workSessionCount: 3)
        let data = try! JSONEncoder().encode([legacy])
        SessionFlowDefaults.store.set(data, forKey: "TaskScheduler.Presets")
        SessionFlowDefaults.store.removeObject(forKey: "SessionFlow.Presets")

        let presets = PresetStorage.shared.loadPresets()

        #expect(presets.map(\.name) == ["Legacy Preset"])
        #expect(SessionFlowDefaults.store.data(forKey: "SessionFlow.Presets") != nil)
        #expect(SessionFlowDefaults.store.data(forKey: "TaskScheduler.Presets") == nil)
    }

    @Test func presetStorageRecoversSavedStateWhenPresetKeyMissingAfterSetup() {
        let state = Preset(
            name: "Current State",
            icon: "gear",
            workSessionCount: 7,
            calendarMapping: CalendarMapping(workCalendarName: "Focused", sideCalendarName: "Admin")
        )
        let data = try! JSONEncoder().encode(state)
        SessionFlowDefaults.store.set(true, forKey: "SessionFlow.HasCompletedSetup")
        SessionFlowDefaults.store.set(data, forKey: "SessionFlow.SavedState")
        SessionFlowDefaults.store.removeObject(forKey: "SessionFlow.Presets")

        let presets = PresetStorage.shared.loadPresets()

        #expect(presets.count == 1)
        #expect(presets[0].name == "Recovered Current Settings")
        #expect(presets[0].workSessionCount == 7)
        #expect(presets[0].calendarMapping.workCalendarName == "Focused")
    }

    @Test func presetStorageRecoversSavedStateWhenOnlyLegacySetupFlagIsSet() {
        let state = Preset(
            name: "Current State",
            icon: "gear",
            workSessionCount: 8,
            calendarMapping: CalendarMapping(workCalendarName: "Legacy Work", sideCalendarName: "Legacy Side")
        )
        let data = try! JSONEncoder().encode(state)
        SessionFlowDefaults.store.set(false, forKey: "SessionFlow.HasCompletedSetup")
        SessionFlowDefaults.store.set(true, forKey: "hasCompletedSetup")
        SessionFlowDefaults.store.set(data, forKey: "SessionFlow.SavedState")
        SessionFlowDefaults.store.removeObject(forKey: "SessionFlow.Presets")

        let presets = PresetStorage.shared.loadPresets()

        #expect(presets.count == 1)
        #expect(presets[0].name == "Recovered Current Settings")
        #expect(presets[0].workSessionCount == 8)
        #expect(presets[0].calendarMapping.sideCalendarName == "Legacy Side")
    }

    @Test func presetStoragePreservesIntentionallyEmptyPresetListAfterSetup() {
        let state = Preset(name: "Current State", workSessionCount: 9)
        let data = try! JSONEncoder().encode(state)
        SessionFlowDefaults.store.set(true, forKey: "SessionFlow.HasCompletedSetup")
        SessionFlowDefaults.store.set(data, forKey: "SessionFlow.SavedState")
        PresetStorage.shared.savePresets([])

        let presets = PresetStorage.shared.loadPresets()

        #expect(presets.isEmpty)
        #expect(SessionFlowDefaults.store.data(forKey: "SessionFlow.Presets") != nil)
    }

    @Test func presetStorageMarksBothSetupCompletionFlagsTogether() {
        PresetStorage.shared.markSetupCompleted()

        #expect(PresetStorage.shared.hasCompletedSetup)
        #expect(SessionFlowDefaults.store.bool(forKey: "SessionFlow.HasCompletedSetup"))
        #expect(SessionFlowDefaults.store.bool(forKey: "hasCompletedSetup"))

        PresetStorage.shared.markSetupIncomplete()

        #expect(!PresetStorage.shared.hasCompletedSetup)
        #expect(!SessionFlowDefaults.store.bool(forKey: "SessionFlow.HasCompletedSetup"))
        #expect(!SessionFlowDefaults.store.bool(forKey: "hasCompletedSetup"))
    }

    @Test func recentSchedulersSkipConfigurationsThatMatchNamedPresets() {
        let named = Preset(name: "Named", workSessionCount: 4, sideSessionCount: 2)
        let sameConfiguration = named.withIdentity(name: "Recent Candidate", icon: "clock")
        PresetStorage.shared.savePresets([named])

        PresetStorage.shared.recordRecentScheduler(sameConfiguration, excludingNamedPresets: [named])

        #expect(PresetStorage.shared.loadRecentSchedulers(excludingNamedPresets: [named]).isEmpty)
    }

    @Test func recentSchedulersDedupeAndKeepFiveMostRecent() {
        let named = Preset(name: "Named", workSessionCount: 1, sideSessionCount: 1)
        PresetStorage.shared.savePresets([named])

        for count in 2...7 {
            PresetStorage.shared.recordRecentScheduler(
                Preset(name: "Candidate \(count)", workSessionCount: count, sideSessionCount: 1),
                excludingNamedPresets: [named]
            )
        }
        PresetStorage.shared.recordRecentScheduler(
            Preset(name: "Duplicate", workSessionCount: 5, sideSessionCount: 1),
            excludingNamedPresets: [named]
        )

        let recent = PresetStorage.shared.loadRecentSchedulers(excludingNamedPresets: [named])

        #expect(recent.map(\.workSessionCount) == [5, 7, 6, 4, 3])
        #expect(recent.count == 5)
    }

    @Test func getDayReturnsAvailability() async throws {
        let server = try await MCPTestServer.start()
        let json = try await server.callJSON("get_day", ["date": .string("2026-05-28")])
        #expect(json["availability"] != nil)
        #expect(json["existingSessionCounts"] != nil)
        #expect(json["events"] != nil)
        await server.stop()
    }

    @Test func unknownToolReportsError() async throws {
        let server = try await MCPTestServer.start()
        await #expect(throws: MCPTestError.self) {
            _ = try await server.callText("does_not_exist")
        }
        await server.stop()
    }

    @Test func harshModeNotesUseReadableSections() {
        let withGoals = HarshModeSessionNotes.applyingGoals(
            ["Ship fresh mode", "Write next step"],
            to: "#work"
        )

        #expect(withGoals == "#work\n\n#flowgoal:\nShip fresh mode\nWrite next step")
        #expect(!withGoals.contains("[SessionFlow Harsh Goals]"))
        #expect(HarshModeSessionNotes.goals(from: withGoals) == ["Ship fresh mode", "Write next step"])

        let withReview = HarshModeSessionNotes.applyingReview(
            rating: .completed,
            reflection: "Stayed focused",
            to: withGoals
        )

        #expect(withReview.contains("#work \(SessionRating.completed.tag)"))
        #expect(withReview.contains("#flowreview:\nStayed focused"))
        #expect(!withReview.contains("[SessionFlow Harsh Review]"))
        #expect(!withReview.contains("Session Flow Review:"))
        #expect(!withReview.contains("Rating:"))
        #expect(HarshModeSessionNotes.goals(from: withReview) == ["Ship fresh mode", "Write next step"])
    }

    @Test func harshModeReviewSectionRequiresReflection() {
        let notes = HarshModeSessionNotes.applyingGoals(["Ship fresh mode"], to: "#work")
        let rated = HarshModeSessionNotes.applyingReview(
            rating: .completed,
            reflection: " \n ",
            to: notes
        )

        #expect(rated.contains(SessionRating.completed.tag))
        #expect(!rated.contains("#flowreview:"))
        #expect(HarshModeSessionNotes.goals(from: rated) == ["Ship fresh mode"])
    }

    @Test func harshModeGoalsStripSessionFlowMetadataTags() {
        let notes = """
        #side

        #flowgoal:
        Rospower #flow✅ #flowalign2
        #flow✅
        #flowalign2
        """

        #expect(HarshModeSessionNotes.goals(from: notes) == ["Rospower"])
        #expect(HarshModeSessionNotes.goalLines(from: "- Rospower #flow✅ #flowalign2") == ["Rospower"])
    }

    @Test func sessionAlignmentTagsRoundTripAndStrip() {
        let aligned = SessionAlignment.direct.applyTo(notes: "Client delivery #flowalign1")

        #expect(SessionAlignment.fromNotes(aligned) == .direct)
        #expect(aligned.contains(SessionAlignment.direct.tag))
        #expect(!aligned.contains(SessionAlignment.maintenance.tag))
        #expect(SessionAlignment.stripAlignmentTags(aligned) == "Client delivery")
        #expect(SessionAwarenessService.strippedNotes("#work \(aligned)") == "Client delivery")
    }

    @Test func strippedDisplayNotesPreserveLongerUserHashtags() {
        let notes = "#work Cardio #workout roadmap #planned #flow✅ #flowalign1"

        #expect(SessionAwarenessService.strippedNotes(notes) == "Cardio #workout roadmap #planned")
        #expect(HarshModeSessionNotes.goalLines(from: "- Cardio #workout #flowalign10 #flowalign1") == ["Cardio #workout #flowalign10"])
    }

    @Test func procrastinatedFocusRatingRoundTripsAndScoresZeroFocus() {
        let notes = SessionRating.procrastinated.applyTo(notes: "#work Review inbox")

        #expect(SessionRating.fromNotes(notes) == .procrastinated)
        #expect(notes.contains(SessionRating.procrastinated.tag))
        #expect(SessionRating.stripFeedbackTags(notes) == "#work Review inbox")
        #expect(SessionRating.procrastinated.focusMultiplier == 0)
        #expect(FocusWeights().multiplier(for: .procrastinated) == 0)
    }

    @Test func externalCalendarEventsDoNotRequireAlignment() {
        let fixedExternalNotes = "Pickup kid"
        let sessionFlowNotes = "#work Client delivery"

        #expect(FlowFlexibilityNotes.alignmentIsOptional(fixedExternalNotes))
        #expect(!FlowFlexibilityNotes.countsTowardAlignmentScore(fixedExternalNotes, alignment: nil))
        #expect(FlowFlexibilityNotes.countsTowardAlignmentScore(fixedExternalNotes, alignment: .direct))

        #expect(!FlowFlexibilityNotes.alignmentIsOptional(sessionFlowNotes))
        #expect(FlowFlexibilityNotes.countsTowardAlignmentScore(sessionFlowNotes, alignment: nil))
    }

    @Test func flowFixedTagOverridesSessionFlowFlexibility() {
        let fixedWorkNotes = "#work Client delivery #flowfixed"

        #expect(FlowFlexibilityNotes.hasExplicitFixedTag(fixedWorkNotes))
        #expect(!FlowFlexibilityNotes.isFlexible(fixedWorkNotes))
        #expect(FlowFlexibilityNotes.isSessionFlowOwned(fixedWorkNotes))
        #expect(FlowFlexibilityNotes.strippingTags(from: fixedWorkNotes) == "#work Client delivery")
        #expect(FlowFlexibilityNotes.applyingFlexible(false, to: "#work Client delivery") == "#work Client delivery #flowfixed")
        #expect(FlowFlexibilityNotes.applyingFlexible(true, to: fixedWorkNotes) == "#work Client delivery")
    }

    @Test func flowFlexibleAliasesMarkExternalEventsFlexible() {
        #expect(FlowFlexibilityNotes.isFlexible("Doctor #flowflexible"))
        #expect(FlowFlexibilityNotes.isFlexible("Doctor #flow-flexible"))
        #expect(!FlowFlexibilityNotes.isFlexible("#work #flowflexible #flowfixed"))
        #expect(FlowFlexibilityNotes.applyingFlexible(true, to: "Doctor") == "Doctor #flowflexible")
        #expect(FlowFlexibilityNotes.strippingTags(from: "Doctor #flow-flexible #flowfixed") == "Doctor")
    }

    @Test func harshModeReviewPreservesAlignmentTag() {
        let alignedGoals = HarshModeSessionNotes.applyingGoals(
            ["Ship paid work"],
            to: SessionAlignment.direct.applyTo(notes: "#work")
        )
        let reviewed = HarshModeSessionNotes.applyingReview(
            rating: .completed,
            reflection: "Stayed on target",
            to: alignedGoals
        )

        #expect(reviewed.contains(SessionAlignment.direct.tag))
        #expect(reviewed.contains(SessionRating.completed.tag))
        #expect(SessionAlignment.fromNotes(reviewed) == .direct)
        #expect(HarshModeSessionNotes.goals(from: reviewed) == ["Ship paid work"])
    }

    @Test func harshModeReviewWritesAlignmentTag() {
        let goals = HarshModeSessionNotes.applyingGoals(
            ["Ship paid work"],
            to: SessionAlignment.maintenance.applyTo(notes: "#work")
        )
        let reviewed = HarshModeSessionNotes.applyingReview(
            rating: .completed,
            alignment: .direct,
            reflection: "Stayed on target",
            to: goals
        )

        #expect(reviewed.contains(SessionRating.completed.tag))
        #expect(reviewed.contains(SessionAlignment.direct.tag))
        #expect(!reviewed.contains(SessionAlignment.maintenance.tag))
        #expect(SessionAlignment.fromNotes(reviewed) == .direct)
        #expect(HarshModeSessionNotes.goals(from: reviewed) == ["Ship paid work"])
    }

    @Test func harshModeGoalsCanBeEditedAfterReview() {
        let notes = HarshModeSessionNotes.applyingGoals(["Original goal"], to: "#work")
        let reviewed = HarshModeSessionNotes.applyingReview(
            rating: .completed,
            reflection: "Shipped a different thing",
            to: notes
        )

        let edited = HarshModeSessionNotes.applyingGoals(["Corrected goal"], to: reviewed)

        #expect(HarshModeSessionNotes.goals(from: edited) == ["Corrected goal"])
        #expect(edited.contains("#flowreview:\nShipped a different thing"))
        #expect(edited.contains(SessionRating.completed.tag))
    }

    @Test func harshModeNotesReadAndRemoveLegacyBlocks() {
        let legacy = """
        #work

        [SessionFlow Harsh Goals]
        - Ship old format
        [/SessionFlow Harsh Goals]

        [SessionFlow Harsh Review]
        Rating: Done
        Reflection:
        Old review
        [/SessionFlow Harsh Review]
        """

        #expect(HarshModeSessionNotes.goals(from: legacy) == ["Ship old format"])
        #expect(HarshModeSessionNotes.removingManagedBlocks(from: legacy) == "#work")

        let updatedGoals = HarshModeSessionNotes.applyingGoals(["Ship new format"], to: legacy)
        #expect(updatedGoals.contains("#flowgoal:\nShip new format"))
        #expect(!updatedGoals.contains("[SessionFlow Harsh Goals]"))

        let updatedReview = HarshModeSessionNotes.applyingReview(
            rating: nil,
            reflection: "New review",
            to: legacy
        )
        #expect(updatedReview.contains("#flowreview:\nNew review"))
        #expect(!updatedReview.contains("[SessionFlow Harsh Review]"))
    }

    @Test func harshModeNotesMigrateReadableSectionHeaders() {
        let readable = """
        #work

        Session Flow Goals:
        Ship temporary format

        Session Flow Review:
        Temporary review
        """

        #expect(HarshModeSessionNotes.goals(from: readable) == ["Ship temporary format"])
        #expect(HarshModeSessionNotes.removingManagedBlocks(from: readable) == "#work")

        let updatedGoals = HarshModeSessionNotes.applyingGoals(["Ship hashtag format"], to: readable)
        #expect(updatedGoals.contains("#flowgoal:\nShip hashtag format"))
        #expect(!updatedGoals.contains("Session Flow Goals:"))

        let updatedReview = HarshModeSessionNotes.applyingReview(
            rating: nil,
            reflection: "Hashtag review",
            to: readable
        )
        #expect(updatedReview.contains("#flowreview:\nHashtag review"))
        #expect(!updatedReview.contains("Session Flow Review:"))
    }

    @Test func harshModeStartDelayMovesExistingEventByDelayOnly() {
        #expect(SessionAwarenessService.harshDelayMinuteOptions == [1, 2, 3, 4, 5, 10, 15, 20])

        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40 * 60)
        let now = start.addingTimeInterval(20 * 60)
        let nextTaskStart = end.addingTimeInterval(3 * 60)
        let fittingOptions = SessionAwarenessService.harshDelayMinuteOptions.filter { minutes in
            SessionAwarenessService.harshDelayTiming(
                phase: .start,
                startTime: start,
                endTime: end,
                now: now,
                minutes: minutes,
                nextTaskStart: nextTaskStart
            ) != nil
        }

        let oneMinute = SessionAwarenessService.harshDelayTiming(
            phase: .start,
            startTime: start,
            endTime: end,
            now: now,
            minutes: 1,
            nextTaskStart: nextTaskStart
        )

        #expect(oneMinute?.start == start.addingTimeInterval(60))
        #expect(oneMinute?.end == end.addingTimeInterval(60))
        #expect(oneMinute?.snoozeUntil == now.addingTimeInterval(60))
        #expect(fittingOptions == [1, 2, 3])

        let fiveMinutes = SessionAwarenessService.harshDelayTiming(
            phase: .start,
            startTime: start,
            endTime: end,
            now: now,
            minutes: 5,
            nextTaskStart: nextTaskStart
        )

        #expect(fiveMinutes == nil)
    }

    @Test func harshModeEndDelayExtendsFromNowAndStopsAtNextTask() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end = start.addingTimeInterval(40 * 60)
        let now = end.addingTimeInterval(10)
        let nextTaskStart = end.addingTimeInterval(3 * 60)

        let twoMinutes = SessionAwarenessService.harshDelayTiming(
            phase: .end,
            startTime: start,
            endTime: end,
            now: now,
            minutes: 2,
            nextTaskStart: nextTaskStart
        )

        #expect(twoMinutes?.start == start)
        #expect(twoMinutes?.end == now.addingTimeInterval(2 * 60))
        #expect(twoMinutes?.snoozeUntil == now.addingTimeInterval(2 * 60))

        let fiveMinutes = SessionAwarenessService.harshDelayTiming(
            phase: .end,
            startTime: start,
            endTime: end,
            now: now,
            minutes: 5,
            nextTaskStart: nextTaskStart
        )

        #expect(fiveMinutes == nil)
    }
}
