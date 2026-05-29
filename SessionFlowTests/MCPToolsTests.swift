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
}
