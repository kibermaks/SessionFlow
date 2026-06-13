import Foundation
import Testing
import MCP
@testable import SessionFlow

/// In-memory `CalendarWriting` so tests never touch the real EventKit store. Records calls so
/// tests can assert that the agent layer drove the calendar correctly.
final class FakeCalendarStore: CalendarWriting, @unchecked Sendable {
    var scheduleEndHour: Int = 24

    var busySlots: [BusyTimeSlot] = []
    var existingCounts: (work: Int, side: Int, deep: Int, titles: Set<String>) = (0, 0, 0, [])
    var planningExists = false
    var deleteResult: (deleted: Int, failed: Int) = (3, 0)

    private(set) var fetchedDates: [Date] = []
    private(set) var createdSessions: [ScheduledSession] = []
    private(set) var movedEvents: [(id: String, start: Date, end: Date)] = []
    private(set) var deleteCalls: [(future: Bool, date: Date)] = []

    func fetchEvents(for date: Date) async { fetchedDates.append(date) }
    func busySlotsForFetchedDate(_ date: Date) -> [BusyTimeSlot] { busySlots }
    func hasPlanningSession(for date: Date, planningEventName: String) -> Bool { planningExists }

    func countExistingSessions(
        for date: Date,
        workCalendar: CalendarDescriptor,
        sideCalendar: CalendarDescriptor,
        deepConfig: DeepSessionConfig?
    ) -> (work: Int, side: Int, deep: Int, titles: Set<String>) {
        existingCounts
    }

    func createSessions(_ sessions: [ScheduledSession]) -> (success: Int, failed: Int, eventIds: [String]) {
        createdSessions.append(contentsOf: sessions)
        return (sessions.count, 0, sessions.map { _ in UUID().uuidString })
    }

    func updateEventTime(eventId: String, newStart: Date, newEnd: Date) -> Bool {
        movedEvents.append((eventId, newStart, newEnd))
        return true
    }

    func deleteSessionEvents(
        for date: Date,
        sessionNames: [String]?,
        fromCalendars calendarsToDelete: [CalendarDescriptor],
        requireSessionTag: Bool
    ) -> (deleted: Int, failed: Int) {
        deleteCalls.append((false, date))
        return deleteResult
    }

    func deleteFutureSessionEvents(
        for date: Date,
        after cutoffTime: Date,
        sessionNames: [String]?,
        fromCalendars calendarsToDelete: [CalendarDescriptor],
        requireSessionTag: Bool
    ) -> (deleted: Int, failed: Int) {
        deleteCalls.append((true, date))
        return deleteResult
    }
}

/// Gives state-mutating tool tests an isolated defaults adapter so they cannot pollute or restore
/// over the user's real SessionFlow settings.
final class DefaultsSandbox {
    private let suiteName: String
    private let defaults: UserDefaults
    private var restored = false

    init() {
        suiteName = "SessionFlowTests.Defaults.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults suite.")
        }
        self.defaults = defaults
        defaults.removePersistentDomain(forName: suiteName)
        SessionFlowDefaults.useOverrideStore(defaults)
    }

    func restore() {
        guard !restored else { return }
        restored = true
        SessionFlowDefaults.useOverrideStore(nil)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
@Suite(.serialized)
final class MCPFeatureTests {
    let sandbox = DefaultsSandbox()
    deinit { sandbox.restore() }
}

enum MCPTestError: Error { case toolError(String) }

/// Spins up the real `MCPServerController` (server + loopback listener) on an ephemeral port and
/// connects a real MCP `Client` over HTTP with bearer auth. Exercises the full production path.
@MainActor
struct MCPTestServer {
    let controller: MCPServerController
    let client: Client
    let engine: SchedulingEngine
    let calendar: FakeCalendarStore
    let token: String

    static func start(
        token: String = "test-token",
        configure: (SchedulingEngine, FakeCalendarStore) -> Void = { _, _ in }
    ) async throws -> MCPTestServer {
        let engine = SchedulingEngine()
        let calendar = FakeCalendarStore()
        configure(engine, calendar)

        let controller = MCPServerController()
        controller.configure(engine: engine, calendar: calendar)
        await controller.start(port: 0, token: token)

        let url = URL(string: "http://127.0.0.1:\(controller.activePort)/mcp")!
        let transport = HTTPClientTransport(
            endpoint: url,
            streaming: false,
            requestModifier: { request in
                var request = request
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            }
        )
        let client = Client(name: "SessionFlowTests", version: "1.0")
        _ = try await client.connect(transport: transport)

        return MCPTestServer(controller: controller, client: client, engine: engine, calendar: calendar, token: token)
    }

    func stop() async {
        await client.disconnect()
        await controller.stop()
    }

    /// Calls a tool and returns its text content, throwing if the tool reported an error.
    func callText(_ name: String, _ arguments: [String: Value] = [:]) async throws -> String {
        let (content, isError) = try await client.callTool(name: name, arguments: arguments)
        let text = content.compactMap { item -> String? in
            if case let .text(text, _, _) = item { return text }
            return nil
        }.joined()
        if isError == true { throw MCPTestError.toolError(text) }
        return text
    }

    /// Calls a tool and parses its JSON object result.
    func callJSON(_ name: String, _ arguments: [String: Value] = [:]) async throws -> [String: Any] {
        let text = try await callText(name, arguments)
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }
}
