import Testing
import Foundation
@testable import SessionFlow

/// Exercises the loopback HTTP listener + SDK validation pipeline over real sockets: bearer auth,
/// DNS-rebinding origin checks, and method handling.
extension MCPFeatureTests {
    private static let initializeBody = Data("""
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}
    """.utf8)

    private func post(port: UInt16, headers: [String: String], body: Data = initializeBody, method: String = "POST") async -> Int {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = method
        if method == "POST" { request.httpBody = body }
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return -1 }
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }

    private func rawStatus(port: UInt16, request: String) -> Int {
        var input: InputStream?
        var output: OutputStream?
        Stream.getStreamsToHost(withName: "127.0.0.1", port: Int(port), inputStream: &input, outputStream: &output)
        guard let input, let output else { return -1 }
        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        let data = Data(request.utf8)
        let written = data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return output.write(base, maxLength: data.count)
        }
        guard written == data.count else { return -1 }

        var buffer = [UInt8](repeating: 0, count: 256)
        let count = input.read(&buffer, maxLength: buffer.count)
        guard count > 0,
              let head = String(bytes: buffer.prefix(count), encoding: .utf8) else { return -1 }
        let parts = head.split(separator: " ", maxSplits: 2)
        return parts.count > 1 ? Int(parts[1]) ?? -1 : -1
    }

    @Test func missingTokenIsUnauthorized() async throws {
        let server = try await MCPTestServer.start()
        let status = await post(port: server.controller.activePort, headers: [
            "Accept": "application/json", "Content-Type": "application/json",
        ])
        #expect(status == 401)
        await server.stop()
    }

    @Test func wrongTokenIsUnauthorized() async throws {
        let server = try await MCPTestServer.start(token: "right-token")
        let status = await post(port: server.controller.activePort, headers: [
            "Accept": "application/json", "Content-Type": "application/json",
            "Authorization": "Bearer wrong-token",
        ])
        #expect(status == 401)
        await server.stop()
    }

    @Test func nonLoopbackOriginIsForbidden() async throws {
        let server = try await MCPTestServer.start(token: "tok")
        let status = await post(port: server.controller.activePort, headers: [
            "Accept": "application/json", "Content-Type": "application/json",
            "Authorization": "Bearer tok",
            "Origin": "http://evil.example.com",
        ])
        #expect(status == 403)
        await server.stop()
    }

    @Test func getMethodNotAllowed() async throws {
        let server = try await MCPTestServer.start(token: "tok")
        let status = await post(
            port: server.controller.activePort,
            headers: ["Authorization": "Bearer tok"],
            method: "GET"
        )
        #expect(status == 405)
        await server.stop()
    }

    @Test func validTokenIsAccepted() async throws {
        let server = try await MCPTestServer.start(token: "tok")
        let status = await post(port: server.controller.activePort, headers: [
            "Accept": "application/json", "Content-Type": "application/json",
            "Authorization": "Bearer tok",
        ])
        #expect(status == 200)
        await server.stop()
    }

    @Test func repeatedInitializeRequestsAreAccepted() async throws {
        let server = try await MCPTestServer.start(token: "tok")
        let headers = [
            "Accept": "application/json", "Content-Type": "application/json",
            "Authorization": "Bearer tok",
        ]
        let first = await post(port: server.controller.activePort, headers: headers)
        let second = await post(port: server.controller.activePort, headers: headers)
        #expect(first == 200)
        #expect(second == 200)
        await server.stop()
    }

    @Test func oversizedRequestIsRejected() async throws {
        let server = try await MCPTestServer.start(token: "tok")
        let status = rawStatus(
            port: server.controller.activePort,
            request: """
            POST /mcp HTTP/1.1\r
            Host: 127.0.0.1\r
            Accept: application/json\r
            Content-Type: application/json\r
            Authorization: Bearer tok\r
            Content-Length: 2000001\r
            Connection: close\r
            \r

            """
        )
        #expect(status == 413)
        await server.stop()
    }
}
