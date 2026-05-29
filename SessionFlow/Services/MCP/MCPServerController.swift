import Foundation
import SwiftUI
import MCP

/// Owns the embedded MCP localhost listener and exposes start/stop plus observable status for the
/// settings UI. Off until `start()` is called.
@MainActor
final class MCPServerController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var activePort: UInt16 = 0
    @Published private(set) var token: String = ""

    private var engine: SchedulingEngine?
    private var calendar: (any CalendarWriting)?

    private var listener: MCPHTTPListener?
    private var handler: MCPToolHandler?

    init() {}

    /// Wires the live services the tools operate on. Call once before `start()`.
    func configure(engine: SchedulingEngine, calendar: any CalendarWriting) {
        self.engine = engine
        self.calendar = calendar
    }

    func start(port: UInt16, token: String) async {
        guard !isRunning, let engine, let calendar else { return }
        self.token = token

        let coordinator = ScheduleCoordinator(engine: engine, calendar: calendar)
        let handler = MCPToolHandler(engine: engine, calendar: calendar, coordinator: coordinator)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let listener = MCPHTTPListener(port: port) { request in
            await Self.handleRequest(request, handler: handler, token: token, version: version)
        }
        do {
            try await listener.start()
            self.listener = listener
            self.handler = handler
            self.activePort = await listener.boundPort
            self.isRunning = true
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
            self.isRunning = false
            await listener.stop()
        }
    }

    func stop() async {
        await listener?.stop()
        listener = nil
        handler = nil
        isRunning = false
        activePort = 0
    }

    /// Creates a short-lived SDK server per HTTP request. The Swift MCP SDK's `Server` stores
    /// initialization state globally, while Claude Code health checks and reconnects by sending
    /// fresh `initialize` requests. Per-request servers keep the HTTP endpoint stateless and allow
    /// repeated clients without leaking one client's lifecycle into the next.
    nonisolated private static func handleRequest(
        _ request: HTTPRequest,
        handler: MCPToolHandler,
        token: String,
        version: String
    ) async -> HTTPResponse {
        let pipeline = StandardValidationPipeline(validators: [
            OriginValidator.localhost(),
            SharedSecretBearerValidator(token: token),
            AcceptHeaderValidator(mode: .jsonOnly),
            ContentTypeValidator(),
            ProtocolVersionValidator(),
        ])
        let transport = StatelessHTTPServerTransport(validationPipeline: pipeline)
        let server = Server(
            name: "SessionFlow",
            version: version,
            instructions: "SessionFlow schedules focus sessions around the calendar. Call the 'learn' tool first to read the full guide of concepts and tools.",
            capabilities: .init(
                resources: .init(subscribe: false, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        await registerHandlers(on: server, handler: handler)

        do {
            try await server.start(transport: transport)
            let response = await transport.handleRequest(request)
            await server.stop()
            await transport.disconnect()
            return response
        } catch {
            await server.stop()
            await transport.disconnect()
            return .error(statusCode: 500, .internalError(error.localizedDescription))
        }
    }

    nonisolated private static func registerHandlers(on server: Server, handler: MCPToolHandler) async {
        await server.withMethodHandler(ListTools.self) { _ in
            let tools = await handler.toolDefinitions()
            return .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            let result = await handler.call(name: params.name, arguments: params.arguments)
            return .init(content: [.text(text: result.text, annotations: nil, _meta: nil)], isError: result.isError)
        }
        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: [
                Resource(
                    name: MCPGuide.resourceName,
                    uri: MCPGuide.resourceURI,
                    description: "How to use SessionFlow's tools and concepts.",
                    mimeType: MCPGuide.mimeType
                ),
            ])
        }
        await server.withMethodHandler(ReadResource.self) { params in
            guard params.uri == MCPGuide.resourceURI else {
                throw MCPError.invalidParams("Unknown resource: \(params.uri)")
            }
            return .init(contents: [
                .text(MCPGuide.markdown(), uri: MCPGuide.resourceURI, mimeType: MCPGuide.mimeType),
            ])
        }
    }
}

/// Persisted MCP server settings (enabled flag, port, bearer token) backed by UserDefaults.
enum MCPSettings {
    static let enabledKey = "SessionFlow.MCPEnabled"
    static let portKey = "SessionFlow.MCPPort"
    static let tokenKey = "SessionFlow.MCPToken"
    static let defaultPort: UInt16 = 8787

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var port: UInt16 {
        get {
            let value = UserDefaults.standard.integer(forKey: portKey)
            return value > 0 && value <= 65535 ? UInt16(value) : defaultPort
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: portKey) }
    }

    static var token: String {
        if let existing = UserDefaults.standard.string(forKey: tokenKey), !existing.isEmpty {
            return existing
        }
        return regenerateToken()
    }

    @discardableResult
    static func regenerateToken() -> String {
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(token, forKey: tokenKey)
        return token
    }
}
