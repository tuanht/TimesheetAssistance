import Foundation
import TimesheetCore

/// A tool failure reported by the server (`isError: true` or a JSON-RPC error). Fetchers map it.
struct MCPToolError: Error, Equatable {
    let message: String
}

/// The server dropped our `Mcp-Session-Id` (HTTP 404). Never leaves `MCPClient`.
private struct SessionExpired: Error {}

/// Calls allow-listed read tools on one MCP server over Streamable HTTP.
public actor MCPClient {
    static let protocolVersion = "2025-06-18"

    private let server: MCPServer
    private let credentials: any CredentialProvider
    private let session: URLSession
    private let timeout: TimeInterval = 30
    private var nextID = 1
    private var sessionID: String?
    private var initialization: Task<Void, Error>?

    public init(server: MCPServer, credentials: any CredentialProvider, session: URLSession? = nil) {
        self.server = server
        self.credentials = credentials
        self.session = session ?? URLSession(
            configuration: .ephemeral, delegate: RedirectRefuser.shared, delegateQueue: nil)
    }

    /// Returns the tool result's `structuredContent` if present, else the first text content parsed as JSON, else `.string(text)`.
    public func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        guard server.allowedTools.contains(name) else { throw ContextError.toolNotAllowed(name) }
        let params = JSONValue.object(["name": .string(name), "arguments": .object(arguments)])
        do {
            return try await initializedCall(params)
        } catch is SessionExpired {
            // The spec requires a fresh session after a 404; retry once.
            resetSession()
            do {
                return try await initializedCall(params)
            } catch is SessionExpired {
                resetSession()
                throw ContextError.unexpectedReply(server.service)
            }
        } catch ContextError.signInAgain(let service) {
            // A new token must not reuse the old session.
            resetSession()
            throw ContextError.signInAgain(service)
        }
    }

    private func initializedCall(_ params: JSONValue) async throws -> JSONValue {
        try await ensureInitialized()
        return try toolValue(try await request("tools/call", params: params))
    }

    private func resetSession() {
        initialization = nil
        sessionID = nil
    }

    // MARK: - Handshake

    private func ensureInitialized() async throws {
        if let initialization { return try await initialization.value }
        let task = Task { try await handshake() }
        initialization = task
        do {
            try await task.value
        } catch {
            initialization = nil
            throw error
        }
    }

    private func handshake() async throws {
        // `initialize` never carries a session ID; the reply sets the new one.
        sessionID = nil
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        _ = try await request("initialize", params: .object([
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("TimesheetAssistant"), "version": .string(version)]),
        ]))
        // Servers answer 202 with an empty body.
        _ = try await send(.object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]))
    }

    // MARK: - JSON-RPC

    private func request(_ method: String, params: JSONValue) async throws -> JSONValue {
        let id = nextID
        nextID += 1
        let data = try await send(.object([
            "jsonrpc": .string("2.0"), "id": .number(Double(id)), "method": .string(method), "params": params,
        ]))
        let message = try reply(matching: id, in: data)
        if let error = message["error"] {
            if case .string(let text)? = error["message"] { throw MCPToolError(message: text) }
            throw MCPToolError(message: "")
        }
        guard let result = message["result"] else { throw ContextError.unexpectedReply(server.service) }
        return result
    }

    private func toolValue(_ result: JSONValue) throws -> JSONValue {
        let text = firstText(of: result)
        if result["isError"] == .bool(true) { throw MCPToolError(message: text ?? "") }
        if let structured = result["structuredContent"], structured != .null { return structured }
        guard let text else { throw ContextError.unexpectedReply(server.service) }
        return (try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) ?? .string(text)
    }

    private func firstText(of result: JSONValue) -> String? {
        guard case .array(let items)? = result["content"] else { return nil }
        for item in items where item["type"] == .string("text") {
            if case .string(let text)? = item["text"] { return text }
        }
        return nil
    }

    /// The reply with `id`, from a plain JSON body or from the `data:` lines of an SSE stream.
    private func reply(matching id: Int, in data: Data) throws -> JSONValue {
        let body = String(decoding: data, as: UTF8.self)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloads = trimmed.hasPrefix("{") ? [trimmed] : Self.sseDataPayloads(body)
        for payload in payloads {
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) else { continue }
            if message["id"] == .number(Double(id)) { return message }
        }
        throw ContextError.unexpectedReply(server.service)
    }

    /// One string per SSE event: its `data:` lines joined with newlines.
    static func sseDataPayloads(_ body: String) -> [String] {
        var payloads: [String] = []
        var lines: [String] = []
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                if !lines.isEmpty { payloads.append(lines.joined(separator: "\n")) }
                lines = []
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst("data:".count)
                if value.hasPrefix(" ") { value = value.dropFirst() }
                lines.append(String(value))
            }
        }
        if !lines.isEmpty { payloads.append(lines.joined(separator: "\n")) }
        return payloads
    }

    // MARK: - HTTP

    private func send(_ body: JSONValue) async throws -> Data {
        var request = URLRequest(url: server.url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Atlassian answers 406 without text/event-stream.
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
            request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }
        if request.url?.host == server.url.host {
            let credential = try await credentials.credential()
            request.setValue(credential.authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw ContextError.unreachable(server.service)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ContextError.unexpectedReply(server.service) }
        try check(http, data: data)
        if sessionID == nil, let id = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = id }
        return data
    }

    private func check(_ http: HTTPURLResponse, data: Data) throws {
        let service = server.service
        switch http.statusCode {
        case 200..<300:
            return
        case 300..<400:
            // Redirects are refused, so the server is effectively unreachable.
            throw ContextError.unreachable(service)
        case 404 where sessionID != nil:
            throw SessionExpired()
        case 401:
            throw ContextError.signInAgain(service)
        case 400 where http.value(forHTTPHeaderField: "WWW-Authenticate")?.contains("invalid_token") == true:
            // GitHub's reply to a malformed token.
            throw ContextError.signInAgain(service)
        case 403:
            let text = String(decoding: data, as: UTF8.self).lowercased()
            let needsApproval = ["approv", "organization", "admin"].contains { text.contains($0) }
            throw needsApproval ? ContextError.notApproved(service) : ContextError.signInAgain(service)
        default:
            throw ContextError.unexpectedReply(service)
        }
    }
}
