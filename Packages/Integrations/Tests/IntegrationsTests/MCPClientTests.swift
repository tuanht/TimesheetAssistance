import Foundation
import Testing
import TimesheetCore
@testable import Integrations

/// Intercepts requests for sessions built by `StubProtocol.session(_:)`, answering per JSON-RPC method.
/// State is static, so the suite using it is `.serialized`.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case response(status: Int, headers: [String: String] = [:], body: Data)
        case failure(URLError)
        /// Redirects to `location` with the given 3xx status.
        case redirect(status: Int, location: String)
    }

    /// Picks the reply from the request's JSON-RPC `method` and `id`.
    typealias Router = @Sendable (_ method: String, _ id: Int?) -> Reply

    private static let lock = NSLock()
    nonisolated(unsafe) private static var router: Router = { _, _ in .response(status: 200, body: Data()) }
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    static func session(_ router: @escaping Router) -> URLSession {
        lock.withLock {
            self.router = router
            captured = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    static var requests: [URLRequest] { lock.withLock { captured } }

    static func method(of request: URLRequest) -> String? {
        body(of: request)?["method"] as? String
    }

    static func body(of request: URLRequest) -> [String: Any]? {
        guard let data = request.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Self.readAll(stream)
        }
        let json = Self.body(of: request)
        let router = Self.lock.withLock {
            Self.captured.append(request)
            return Self.router
        }
        switch router(json?["method"] as? String ?? "", json?["id"] as? Int) {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .redirect(let status, let location):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Location": location])!
            var next = request
            next.url = URL(string: location)!
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private struct FixedCredential: CredentialProvider {
    let value: Credential
    func credential() async throws -> Credential { value }
}

@Suite(.serialized)
struct MCPClientTests {
    private static let token = "test-token-0123456789"
    private static let sessionID = "session-abc"

    // MARK: - Fixtures

    private static func sse(_ json: String) -> Data {
        Data("event: message\ndata: \(json)\n\n".utf8)
    }

    private static func initializeReply(id: Int?) -> StubProtocol.Reply {
        .response(
            status: 200,
            headers: ["Content-Type": "text/event-stream", "Mcp-Session-Id": sessionID],
            body: sse(#"{"jsonrpc":"2.0","id":\#(id ?? 0),"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"stub","version":"1"}}}"#))
    }

    private static let accepted = StubProtocol.Reply.response(status: 202, body: Data())

    /// A server that initializes normally and answers `tools/call` with `toolReply`.
    private static func server(
        _ toolReply: @escaping @Sendable (Int?) -> StubProtocol.Reply
    ) -> StubProtocol.Router {
        { method, id in
            switch method {
            case "initialize": initializeReply(id: id)
            case "notifications/initialized": accepted
            default: toolReply(id)
            }
        }
    }

    private static func toolResult(id: Int?, result: String, sse useSSE: Bool = true) -> StubProtocol.Reply {
        let json = #"{"jsonrpc":"2.0","id":\#(id ?? 0),"result":\#(result)}"#
        return useSSE
            ? .response(status: 200, headers: ["Content-Type": "text/event-stream"], body: sse(json))
            : .response(status: 200, headers: ["Content-Type": "application/json"], body: Data(json.utf8))
    }

    private static let prJSON = #"{"number":7,"title":"Add retry to sync","state":"closed","merged":true}"#

    private static func textContent(_ text: String) -> String {
        let escaped = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
        return #"{"content":[{"type":"text","text":\#(escaped)}]}"#
    }

    private static let prValue: JSONValue = .object([
        "number": .number(7), "title": .string("Add retry to sync"),
        "state": .string("closed"), "merged": .bool(true),
    ])

    private func client(
        _ router: @escaping StubProtocol.Router,
        server: MCPServer = .github,
        credential: Credential = .bearer(MCPClientTests.token)
    ) -> MCPClient {
        MCPClient(server: server, credentials: FixedCredential(value: credential),
                  session: StubProtocol.session(router))
    }

    private func readPR(_ sut: MCPClient) async throws -> JSONValue {
        try await sut.callTool("pull_request_read", arguments: [
            "method": .string("get"), "owner": .string("acme"), "repo": .string("web"), "pullNumber": .number(7),
        ])
    }

    private func status(_ code: Int, headers: [String: String] = [:], body: String = "") -> StubProtocol.Router {
        { _, _ in .response(status: code, headers: headers, body: Data(body.utf8)) }
    }

    // MARK: - Handshake

    @Test func initializesOnceThenCallsTool() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent(Self.prJSON)) })
        _ = try await readPR(sut)
        #expect(StubProtocol.requests.compactMap(StubProtocol.method) ==
                ["initialize", "notifications/initialized", "tools/call"])

        let initialize = try #require(StubProtocol.body(of: StubProtocol.requests[0]))
        let params = try #require(initialize["params"] as? [String: Any])
        #expect(params["protocolVersion"] as? String == "2025-06-18")
        let clientInfo = try #require(params["clientInfo"] as? [String: Any])
        #expect(clientInfo["name"] as? String == "TimesheetAssistant")
        #expect(clientInfo["version"] is String)

        let call = try #require(StubProtocol.body(of: StubProtocol.requests[2]))
        let callParams = try #require(call["params"] as? [String: Any])
        #expect(callParams["name"] as? String == "pull_request_read")
        let arguments = try #require(callParams["arguments"] as? [String: Any])
        #expect(arguments["pullNumber"] as? Int == 7)

        _ = try await readPR(sut)
        #expect(StubProtocol.requests.compactMap(StubProtocol.method) ==
                ["initialize", "notifications/initialized", "tools/call", "tools/call"])
    }

    @Test func echoesSessionId() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent(Self.prJSON)) })
        _ = try await readPR(sut)
        let requests = StubProtocol.requests
        #expect(requests[0].value(forHTTPHeaderField: "Mcp-Session-Id") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "Mcp-Session-Id") == Self.sessionID)
        #expect(requests[2].value(forHTTPHeaderField: "Mcp-Session-Id") == Self.sessionID)
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json, text/event-stream")
            #expect(request.httpMethod == "POST")
        }
    }

    @Test func sendsProtocolVersionAfterInitialize() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent(Self.prJSON)) })
        _ = try await readPR(sut)
        let requests = StubProtocol.requests
        #expect(requests[0].value(forHTTPHeaderField: "MCP-Protocol-Version") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-06-18")
        #expect(requests[2].value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-06-18")
    }

    @Test func sendsProtocolVersionWithoutSession() async throws {
        let sut = client { method, id in
            switch method {
            case "initialize":
                .response(
                    status: 200, headers: ["Content-Type": "application/json"],
                    body: Data(#"{"jsonrpc":"2.0","id":\#(id ?? 0),"result":{"protocolVersion":"2025-06-18","capabilities":{}}}"#.utf8))
            case "notifications/initialized": Self.accepted
            default: Self.toolResult(id: id, result: Self.textContent(Self.prJSON))
            }
        }
        _ = try await readPR(sut)
        let requests = StubProtocol.requests
        #expect(requests[0].value(forHTTPHeaderField: "MCP-Protocol-Version") == nil)
        #expect(requests[2].value(forHTTPHeaderField: "Mcp-Session-Id") == nil)
        #expect(requests[2].value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-06-18")
    }

    @Test func acceptsEmptyAcceptedNotification() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent(Self.prJSON)) })
        #expect(try await readPR(sut) == Self.prValue)
    }

    // MARK: - Reply parsing

    @Test func parsesJSONResponse() async throws {
        let sut = client(Self.server {
            Self.toolResult(id: $0, result: Self.textContent(Self.prJSON), sse: false)
        })
        #expect(try await readPR(sut) == Self.prValue)
    }

    @Test func parsesSSEResponse() async throws {
        let sut = client(Self.server { id in
            // A server notification first, then the reply with the matching id.
            let note = #"{"jsonrpc":"2.0","method":"notifications/message","params":{"level":"info"}}"#
            let other = #"{"jsonrpc":"2.0","id":999,"result":{"content":[]}}"#
            let reply = #"{"jsonrpc":"2.0","id":\#(id ?? 0),"result":\#(Self.textContent(Self.prJSON))}"#
            let body = "event: message\ndata: \(note)\n\n: keep-alive\n\nevent: message\ndata: \(other)\n\n"
                + "event: message\r\ndata: \(reply)\r\n\r\n"
            return .response(status: 200, headers: ["Content-Type": "text/event-stream"], body: Data(body.utf8))
        })
        #expect(try await readPR(sut) == Self.prValue)
    }

    @Test func prefersStructuredContent() async throws {
        let sut = client(Self.server {
            Self.toolResult(id: $0, result: #"{"content":[{"type":"text","text":"ignored"}],"structuredContent":{"ok":true}}"#)
        })
        #expect(try await readPR(sut) == .object(["ok": .bool(true)]))
    }

    @Test func parsesTextContentAsJSON() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent(Self.prJSON)) })
        #expect(try await readPR(sut) == Self.prValue)
    }

    @Test func plainTextContentIsReturnedAsString() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent("not json")) })
        #expect(try await readPR(sut) == .string("not json"))
    }

    @Test func toolErrorIsPassedUp() async throws {
        let message = "failed to get pull request: GET https://api.github.com/repos/acme/web/pulls/7: 404 Not Found []"
        let sut = client(Self.server {
            Self.toolResult(id: $0, result: #"{"content":[{"type":"text","text":"\#(message)"}],"isError":true}"#)
        })
        await #expect(throws: MCPToolError(message: message)) { try await readPR(sut) }
    }

    @Test func jsonRPCErrorIsPassedUp() async throws {
        let sut = client(Self.server { id in
            .response(status: 200, headers: ["Content-Type": "text/event-stream"],
                      body: Self.sse(#"{"jsonrpc":"2.0","id":\#(id ?? 0),"error":{"code":-32602,"message":"Tool x not found"}}"#))
        })
        await #expect(throws: MCPToolError(message: "Tool x not found")) { try await readPR(sut) }
    }

    @Test func undecodableReplyMapsToUnexpectedReply() async throws {
        let sut = client(Self.server { _ in .response(status: 200, body: Data("<html>".utf8)) })
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await readPR(sut) }
    }

    // MARK: - Allow-list

    @Test func refusesToolNotAllowed() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent("{}")) })
        await #expect(throws: ContextError.toolNotAllowed("create_pull_request")) {
            try await sut.callTool("create_pull_request", arguments: [:])
        }
        #expect(StubProtocol.requests.isEmpty)
    }

    // MARK: - Credentials

    @Test func bearerHeaderSent() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent("{}")) })
        _ = try await readPR(sut)
        #expect(StubProtocol.requests.count == 3)
        for request in StubProtocol.requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)")
        }
    }

    @Test func basicHeaderSent() async throws {
        let sut = client(Self.server { Self.toolResult(id: $0, result: Self.textContent("{}")) },
                         server: .atlassian,
                         credential: .basic(email: "dev@example.com", token: Self.token))
        _ = try await sut.callTool("atlassianUserInfo", arguments: [:])
        let expected = "Basic " + Data("dev@example.com:\(Self.token)".utf8).base64EncodedString()
        for request in StubProtocol.requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
            #expect(request.url?.host == "mcp.atlassian.com")
        }
    }

    // MARK: - Failures

    @Test(arguments: [301, 302, 307, 308])
    func redirectIsRefused(status: Int) async throws {
        let sut = client { _, _ in .redirect(status: status, location: "https://evil.example.com/mcp/") }
        await #expect(throws: ContextError.unreachable(.github)) { try await readPR(sut) }
        #expect(StubProtocol.requests.allSatisfy { $0.url?.host == "api.githubcopilot.com" })
    }

    @Test func unauthorizedMapsToSignInAgain() async throws {
        let sut = client(status(401, body: "unauthorized: token authentication failed"))
        await #expect(throws: ContextError.signInAgain(.github)) { try await readPR(sut) }
    }

    @Test func badRequestInvalidTokenMapsToSignInAgain() async throws {
        let sut = client(status(
            400, headers: ["WWW-Authenticate": #"Bearer error="invalid_token", resource_metadata="https://example.com""#],
            body: "bad request: Authorization header is badly formatted"))
        await #expect(throws: ContextError.signInAgain(.github)) { try await readPR(sut) }
    }

    @Test func badRequestWithoutInvalidTokenMapsToUnexpectedReply() async throws {
        let sut = client(status(400, body: "bad request"))
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await readPR(sut) }
    }

    @Test func forbiddenApprovalMapsToNotApproved() async throws {
        let sut = client(status(403, body: "The acme organization has enabled access restrictions. Ask an owner to approve this app."))
        await #expect(throws: ContextError.notApproved(.github)) { try await readPR(sut) }
    }

    @Test func otherForbiddenMapsToSignInAgain() async throws {
        let sut = client(status(403, body: "forbidden"))
        await #expect(throws: ContextError.signInAgain(.github)) { try await readPR(sut) }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost])
    func offlineMapsToUnreachable(code: URLError.Code) async throws {
        let sut = client { _, _ in .failure(URLError(code)) }
        await #expect(throws: ContextError.unreachable(.github)) { try await readPR(sut) }
    }

    @Test func failedInitializeIsRetriedOnNextCall() async throws {
        let sut = client(status(401))
        await #expect(throws: ContextError.signInAgain(.github)) { try await readPR(sut) }
        StubProtocol.replaceRouter(Self.server { Self.toolResult(id: $0, result: Self.textContent("{}")) })
        _ = try await readPR(sut)
        #expect(StubProtocol.requests.compactMap(StubProtocol.method) ==
                ["initialize", "initialize", "notifications/initialized", "tools/call"])
    }

    // MARK: - Session recovery

    /// Initialize replies hand out `session-1`, `session-2`, …; other methods use `rest`.
    private static func numberedSessions(
        _ rest: @escaping @Sendable (_ method: String, _ id: Int?, _ call: Int) -> StubProtocol.Reply
    ) -> StubProtocol.Router {
        let initializes = Counter(), calls = Counter()
        return { method, id in
            guard method == "initialize" else { return rest(method, id, calls.next(method)) }
            let n = initializes.next(method)
            return .response(
                status: 200,
                headers: ["Content-Type": "text/event-stream", "Mcp-Session-Id": "session-\(n)"],
                body: sse(#"{"jsonrpc":"2.0","id":\#(id ?? 0),"result":{"protocolVersion":"2025-06-18"}}"#))
        }
    }

    private func trace() -> [String] {
        StubProtocol.requests.map {
            "\(StubProtocol.method(of: $0) ?? "?") \($0.value(forHTTPHeaderField: "Mcp-Session-Id") ?? "-")"
        }
    }

    @Test func expiredSessionReinitializesAndRetries() async throws {
        let sut = client(Self.numberedSessions { method, id, call in
            if method == "notifications/initialized" { return Self.accepted }
            return call == 1 ? .response(status: 404, body: Data())
                : Self.toolResult(id: id, result: Self.textContent(Self.prJSON))
        })
        #expect(try await readPR(sut) == Self.prValue)
        #expect(trace() == [
            "initialize -", "notifications/initialized session-1", "tools/call session-1",
            "initialize -", "notifications/initialized session-2", "tools/call session-2",
        ])
    }

    @Test func repeatedExpiryMapsToUnexpectedReply() async throws {
        let sut = client(Self.numberedSessions { method, _, _ in
            method == "notifications/initialized" ? Self.accepted : .response(status: 404, body: Data())
        })
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await readPR(sut) }
        #expect(StubProtocol.requests.count == 6)
    }

    @Test func failedInitializedNotificationStartsFreshSession() async throws {
        let sut = client(Self.numberedSessions { method, id, call in
            if method == "notifications/initialized" {
                return call == 1 ? .response(status: 500, body: Data()) : Self.accepted
            }
            return Self.toolResult(id: id, result: Self.textContent("{}"))
        })
        await #expect(throws: ContextError.unexpectedReply(.github)) { try await readPR(sut) }
        _ = try await readPR(sut)
        #expect(trace() == [
            "initialize -", "notifications/initialized session-1",
            "initialize -", "notifications/initialized session-2", "tools/call session-2",
        ])
    }

    @Test func unauthorizedResetsSession() async throws {
        let sut = client(Self.numberedSessions { method, id, call in
            if method == "notifications/initialized" { return Self.accepted }
            return call == 2 ? .response(status: 401, body: Data())
                : Self.toolResult(id: id, result: Self.textContent("{}"))
        })
        _ = try await readPR(sut)
        await #expect(throws: ContextError.signInAgain(.github)) { try await readPR(sut) }
        _ = try await readPR(sut)
        #expect(trace() == [
            "initialize -", "notifications/initialized session-1", "tools/call session-1",
            "tools/call session-1",
            "initialize -", "notifications/initialized session-2", "tools/call session-2",
        ])
    }

    @Test func messageNeverContainsToken() async throws {
        let routers: [StubProtocol.Router] = [
            status(401, body: "unauthorized \(Self.token)"),
            status(400, headers: ["WWW-Authenticate": #"Bearer error="invalid_token""#], body: Self.token),
            status(403, body: "organization approval needed for \(Self.token)"),
            status(403, body: Self.token),
            status(500, body: Self.token),
            status(200, body: "garbage \(Self.token)"),
            { _, _ in .failure(URLError(.notConnectedToInternet)) },
            { _, _ in .redirect(status: 302, location: "https://evil.example.com/?t=\(Self.token)") },
        ]
        var seen = 0
        for router in routers {
            do {
                _ = try await readPR(client(router))
                Issue.record("expected an error")
            } catch let error as ContextError {
                seen += 1
                #expect(!error.userMessage.contains(Self.token))
            }
        }
        #expect(seen == routers.count)
    }
}

/// Counts calls per key, starting at 1.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func next(_ key: String) -> Int {
        lock.withLock {
            counts[key, default: 0] += 1
            return counts[key]!
        }
    }
}

extension StubProtocol {
    /// Swaps the router without resetting captured requests.
    static func replaceRouter(_ router: @escaping Router) {
        lock.withLock { self.router = router }
    }
}
