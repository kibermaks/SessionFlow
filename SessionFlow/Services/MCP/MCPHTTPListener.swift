import Foundation
import Network
import MCP

/// A loopback HTTP listener (Network.framework) that adapts raw sockets to MCP HTTP requests.
/// The supplied request handler owns JSON-RPC routing and validation; this type only parses HTTP
/// into `HTTPRequest`, invokes the handler, and writes the resulting `HTTPResponse` back. One
/// request per connection (`Connection: close`).
actor MCPHTTPListener {
    private static let maxRequestBytes = 2_000_000

    private let requestedPort: UInt16
    private let requestHandler: (HTTPRequest) async -> HTTPResponse

    private let queue = DispatchQueue(label: "com.kibermaks.SessionFlow.mcp.listener")
    private var listener: NWListener?
    private(set) var boundPort: UInt16 = 0
    private var readyContinuation: CheckedContinuation<Void, any Swift.Error>?

    init(port: UInt16, requestHandler: @escaping (HTTPRequest) async -> HTTPResponse) {
        self.requestedPort = port
        self.requestHandler = requestHandler
    }

    func start() async throws {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if requestedPort != 0, let port = NWEndpoint.Port(rawValue: requestedPort) {
            params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        }

        let listener = try NWListener(using: params)
        self.listener = listener

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Swift.Error>) in
            self.readyContinuation = cont
            listener.stateUpdateHandler = { [weak self] state in
                Task { await self?.onState(state) }
            }
            listener.newConnectionHandler = { [weak self] conn in
                Task { await self?.serve(conn) }
            }
            listener.start(queue: self.queue)
        }
    }

    func stop() {
        readyContinuation?.resume(throwing: CancellationError())
        readyContinuation = nil
        listener?.cancel()
        listener = nil
        boundPort = 0
    }

    private func onState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port?.rawValue { boundPort = port }
            readyContinuation?.resume()
            readyContinuation = nil
        case .failed(let error):
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
        case .cancelled:
            readyContinuation?.resume(throwing: CancellationError())
            readyContinuation = nil
        default:
            break
        }
    }

    // MARK: - Connection handling

    private func serve(_ conn: NWConnection) async {
        conn.start(queue: queue)

        var buffer = Data()
        var headerRange: Range<Data.Index>?
        while headerRange == nil {
            guard let chunk = await receiveChunk(conn) else { conn.cancel(); return }
            buffer.append(chunk)
            headerRange = buffer.range(of: Data("\r\n\r\n".utf8))
            if buffer.count > Self.maxRequestBytes {
                write(conn, .error(statusCode: 413, .invalidRequest("Request too large")))
                return
            }
        }

        guard let range = headerRange else { conn.cancel(); return }
        let headerText = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
        let (method, path, headers) = Self.parseHead(headerText)

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength <= Self.maxRequestBytes else {
            write(conn, .error(statusCode: 413, .invalidRequest("Request body too large")))
            return
        }
        var body = Data(buffer[range.upperBound...])
        guard body.count <= Self.maxRequestBytes else {
            write(conn, .error(statusCode: 413, .invalidRequest("Request body too large")))
            return
        }
        while body.count < contentLength {
            guard let chunk = await receiveChunk(conn) else { break }
            body.append(chunk)
            if body.count > Self.maxRequestBytes {
                write(conn, .error(statusCode: 413, .invalidRequest("Request body too large")))
                return
            }
        }

        let request = HTTPRequest(
            method: method,
            headers: headers,
            body: body.isEmpty ? nil : body,
            path: path
        )
        let response = await requestHandler(request)
        write(conn, response)
    }

    private func receiveChunk(_ conn: NWConnection) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete || error != nil {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    private func write(_ conn: NWConnection, _ response: HTTPResponse) {
        var headers = response.headers
        let body: Data
        if case .stream = response {
            // This listener does not serve SSE; the stateless transport never returns .stream.
            body = Data()
        } else {
            body = response.bodyData ?? Data()
        }
        if !body.isEmpty, headers["Content-Type"] == nil {
            headers["Content-Type"] = "application/json"
        }
        headers["Content-Length"] = String(body.count)
        headers["Connection"] = "close"

        var head = "HTTP/1.1 \(response.statusCode) \(Self.reasonPhrase(response.statusCode))\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - Parsing helpers

    private static func parseHead(_ text: String) -> (method: String, path: String, headers: [String: String]) {
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        if !lines.isEmpty { lines.removeFirst() }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        let method = parts.count > 0 ? parts[0] : ""
        let path = parts.count > 1 ? parts[1] : ""
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return (method, path, headers)
    }

    private static func reasonPhrase(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 421: return "Misdirected Request"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}

/// Requires a fixed shared-secret bearer token on every request. Sits in the validation
/// pipeline after origin validation so unauthenticated callers are rejected with 401.
struct SharedSecretBearerValidator: HTTPRequestValidator {
    let token: String

    func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
        guard request.header("Authorization") == "Bearer \(token)" else {
            return .error(statusCode: 401, .invalidRequest("Missing or invalid bearer token"))
        }
        return nil
    }
}
