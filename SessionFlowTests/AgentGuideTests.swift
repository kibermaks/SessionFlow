import Testing
import Foundation
@testable import SessionFlow

extension MCPFeatureTests {
    @Test func guideLoadsFromBundle() {
        let markdown = MCPGuide.markdown()
        #expect(markdown.contains("SessionFlow Agent Guide"))
        #expect(markdown.count > 500)
    }

    /// Guards against drift: every registered tool must be documented in the guide.
    @Test func guideMentionsEveryTool() {
        let engine = SchedulingEngine()
        let calendar = FakeCalendarStore()
        let coordinator = ScheduleCoordinator(engine: engine, calendar: calendar)
        let handler = MCPToolHandler(engine: engine, calendar: calendar, coordinator: coordinator)

        let markdown = MCPGuide.markdown()
        for tool in handler.toolDefinitions() {
            #expect(markdown.contains(tool.name), "Guide is missing tool: \(tool.name)")
        }
    }
}
