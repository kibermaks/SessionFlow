import Testing
import Foundation
import AppKit
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

@MainActor
struct WindowIdentityTests {
    @Test func acceptsOnlyTheRealMainContentWindowShape() {
        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = "SessionFlow"
        mainWindow.contentView = NSView()

        let auxiliaryWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 2560, height: 30),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        auxiliaryWindow.title = ""
        auxiliaryWindow.contentView = NSView()

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Settings"
        settingsWindow.contentView = NSView()

        #expect(SessionFlowWindowIdentity.isMainWindow(mainWindow))
        #expect(!SessionFlowWindowIdentity.isMainWindow(auxiliaryWindow))
        #expect(!SessionFlowWindowIdentity.isMainWindow(settingsWindow))
    }
}
