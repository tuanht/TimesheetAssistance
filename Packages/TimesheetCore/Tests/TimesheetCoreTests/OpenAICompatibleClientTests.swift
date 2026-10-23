import Foundation
import Testing
@testable import TimesheetCore

/// Intercepts requests for sessions built by `StubProtocol.session()`.
/// State is static, so the suite using it is `.serialized`.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    enum Reply {
        case response(status: Int, body: Data)
        case failure(URLError)
        /// Redirects to `location` with the given 3xx status.
        case redirect(status: Int, location: String)
        /// Never answers, so the caller can cancel.
        case hang
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [Reply] = [.response(status: 200, body: Data())]
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    static func session(replying reply: Reply) -> URLSession {
        session(replying: [reply])
    }

    /// Answers requests in order; the last reply repeats.
    static func session(replying replies: [Reply]) -> URLSession {
        precondition(!replies.isEmpty)
        lock.withLock {
            self.replies = replies
            captured = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    static var requests: [URLRequest] { lock.withLock { captured } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            request.httpBody = Self.readAll(stream)
        }
        let reply = Self.lock.withLock {
            Self.captured.append(request)
            return Self.replies.count > 1 ? Self.replies.removeFirst() : Self.replies[0]
        }
        switch reply {
        case .response(let status, let body):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
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
        case .hang:
            break
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

@Suite(.serialized)
struct OpenAICompatibleClientTests {
    private let config = EndpointConfig(
        baseURL: URL(string: "http://localhost:11434")!, model: "qwen3:8b", remoteConfirmed: false)

    private func chatBody(_ content: String) -> Data {
        let json: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func client(
        _ reply: StubProtocol.Reply, config: EndpointConfig? = nil, apiKey: String? = nil
    ) -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            config: config ?? self.config, apiKey: apiKey, session: StubProtocol.session(replying: reply))
    }

    @Test func sendsChatRequest() async throws {
        let sut = client(.response(status: 200, body: chatBody("hello")))
        let result = try await sut.complete(system: "sys", user: "usr")
        #expect(result == "hello")

        let request = try #require(StubProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path.hasSuffix("/v1/chat/completions") == true)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "qwen3:8b")
        #expect(json["stream"] as? Bool == false)
        #expect(json["temperature"] as? Double == 0.2)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "sys"], ["role": "user", "content": "usr"]])
    }

    @Test func baseURLWithV1NotDoubled() async throws {
        let v1 = EndpointConfig(
            baseURL: URL(string: "http://localhost:11434/v1")!, model: "m", remoteConfirmed: false)
        _ = try await client(.response(status: 200, body: chatBody("x")), config: v1)
            .complete(system: "s", user: "u")
        #expect(StubProtocol.requests.first?.url?.path == "/v1/chat/completions")
    }

    @Test func baseURLWithTrailingSlashNotDoubled() async throws {
        let slash = EndpointConfig(
            baseURL: URL(string: "http://localhost:11434/v1/")!, model: "m", remoteConfirmed: false)
        _ = try await client(.response(status: 200, body: chatBody("x")), config: slash)
            .complete(system: "s", user: "u")
        #expect(StubProtocol.requests.first?.url?.path == "/v1/chat/completions")
    }

    @Test func noAuthHeaderWithoutKey() async throws {
        _ = try await client(.response(status: 200, body: chatBody("x")), apiKey: nil)
            .complete(system: "s", user: "u")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)

        _ = try await client(.response(status: 200, body: chatBody("x")), apiKey: "")
            .complete(system: "s", user: "u")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func bearerHeaderWithKey() async throws {
        _ = try await client(.response(status: 200, body: chatBody("x")), apiKey: "sk-test")
            .complete(system: "s", user: "u")
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    }

    @Test func non200ThrowsHttp() async throws {
        let sut = client(.response(status: 500, body: Data("boom".utf8)))
        do {
            _ = try await sut.complete(system: "s", user: "u")
            Issue.record("expected error")
        } catch let error as LLMError {
            guard case .http(500, _) = error else {
                Issue.record("got \(error)")
                return
            }
        }
    }

    @Test func serviceUnavailableThrowsModelNotReady() async throws {
        let sut = client(.response(status: 503, body: Data("Loading model".utf8)))
        await #expect(throws: LLMError.modelNotReady) {
            _ = try await sut.complete(system: "s", user: "u")
        }
    }

    @Test func modelNotReadyMessageFitsLocalAndEndpoint() {
        #expect(LLMError.modelNotReady.userMessage
            == "The model isn't ready. Download it in Settings › Models, or load it on your server, then try again.")
    }

    @Test func connectionRefusedThrowsUnreachable() async throws {
        let sut = client(.failure(URLError(.cannotConnectToHost)))
        do {
            _ = try await sut.complete(system: "s", user: "u")
            Issue.record("expected error")
        } catch let error as LLMError {
            guard case .unreachable(let where_) = error else {
                Issue.record("got \(error)")
                return
            }
            #expect(where_ == "http://localhost:11434")
            #expect(error.userMessage
                == "Can't reach the endpoint at http://localhost:11434. Is the server running?")
        }
    }

    @Test func timeoutThrowsTimeout() async throws {
        let sut = client(.failure(URLError(.timedOut)))
        await #expect(throws: LLMError.timeout) {
            _ = try await sut.complete(system: "s", user: "u")
        }
    }

    @Test func emptyChoicesThrowsEmpty() async throws {
        let sut = client(.response(status: 200, body: Data(#"{"choices":[]}"#.utf8)))
        await #expect(throws: LLMError.emptyResponse) {
            _ = try await sut.complete(system: "s", user: "u")
        }
    }

    @Test func blankContentThrowsEmpty() async throws {
        let sut = client(.response(status: 200, body: chatBody("  \n")))
        await #expect(throws: LLMError.emptyResponse) {
            _ = try await sut.complete(system: "s", user: "u")
        }
    }

    @Test func testConnectionListsModels() async throws {
        let body = Data(#"{"object":"list","data":[{"id":"qwen3:8b","object":"model"},{"id":"llama3.2","object":"model"}]}"#.utf8)
        let ids = try await client(.response(status: 200, body: body), apiKey: "k").testConnection()
        #expect(ids == ["qwen3:8b", "llama3.2"])
        let request = try #require(StubProtocol.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
    }

    @Test func userMessagesNeverLeakKeyOrCredentials() {
        let errors: [LLMError] = [
            .unreachable("http://localhost:11434"), .http(401, "Unauthorized"), .timeout,
            .emptyResponse, .modelNotReady,
        ]
        for error in errors {
            #expect(!error.userMessage.isEmpty)
            #expect(!error.userMessage.contains("sk-"))
        }
    }

    @Test func unreachableStripsCredentialsFromURL() async throws {
        let withUser = EndpointConfig(
            baseURL: URL(string: "http://user:secret@10.0.0.2:8080/v1")!, model: "m", remoteConfirmed: false)
        await #expect(throws: LLMError.unreachable("http://10.0.0.2:8080")) {
            _ = try await client(.failure(URLError(.cannotFindHost)), config: withUser)
                .complete(system: "s", user: "u")
        }
    }

    @Test(arguments: [307, 308])
    func redirectIsRefused(status: Int) async throws {
        let sut = client(.redirect(status: status, location: "https://evil.example.com/v1/chat/completions"),
                         apiKey: "sk-test")
        await #expect(throws: LLMError.redirectRefused) {
            _ = try await sut.complete(system: "private notes", user: "u")
        }
        #expect(StubProtocol.requests.count == 1)
        #expect(StubProtocol.requests.allSatisfy { $0.url?.host() == "localhost" })
        #expect(LLMError.redirectRefused.userMessage
            == "The endpoint tried to redirect to another address. Use the final URL directly.")
    }

    @Test func testConnectionRefusesRedirect() async throws {
        let sut = client(.redirect(status: 307, location: "https://evil.example.com/v1/models"))
        await #expect(throws: LLMError.redirectRefused) {
            _ = try await sut.testConnection()
        }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func urlCancelledThrowsCancellation() async throws {
        let sut = client(.failure(URLError(.cancelled)))
        await #expect(throws: CancellationError.self) {
            _ = try await sut.complete(system: "s", user: "u")
        }
    }

    @Test func taskCancellationThrowsCancellation() async throws {
        let sut = client(.hang)
        let task = Task { try await sut.complete(system: "s", user: "u") }
        while StubProtocol.requests.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    // MARK: - response_format

    private static let schema = #"{"type":"object","properties":{"b":{},"a":{}}}"#

    private func bodyJSON(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @Test func sendsResponseFormatWithSchema() async throws {
        let sut = client(.response(status: 200, body: chatBody("ok")))
        let result = try await sut.complete(system: "s", user: "u", jsonSchema: Self.schema)
        #expect(result == "ok")

        let request = try #require(StubProtocol.requests.first)
        let json = try bodyJSON(request)
        let format = try #require(json["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let jsonSchema = try #require(format["json_schema"] as? [String: Any])
        #expect(jsonSchema["name"] as? String == "timesheet_lines")
        #expect(jsonSchema["strict"] == nil)
        #expect(jsonSchema["schema"] is [String: Any])
        #expect(json["model"] as? String == "qwen3:8b")
        let raw = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(raw.contains(Self.schema))
    }

    @Test func noResponseFormatWithoutSchema() async throws {
        _ = try await client(.response(status: 200, body: chatBody("x"))).complete(system: "s", user: "u")
        #expect(try bodyJSON(try #require(StubProtocol.requests.first))["response_format"] == nil)

        _ = try await client(.response(status: 200, body: chatBody("x")))
            .complete(system: "s", user: "u", jsonSchema: nil)
        #expect(try bodyJSON(try #require(StubProtocol.requests.first))["response_format"] == nil)
    }

    @Test func invalidSchemaSendsPlainRequest() async throws {
        _ = try await client(.response(status: 200, body: chatBody("x")))
            .complete(system: "s", user: "u", jsonSchema: "{not json")
        #expect(StubProtocol.requests.count == 1)
        #expect(try bodyJSON(try #require(StubProtocol.requests.first))["response_format"] == nil)
    }

    @Test(arguments: [400, 422])
    func retriesWithoutSchemaOnRejection(status: Int) async throws {
        let sut = OpenAICompatibleClient(
            config: config, apiKey: nil,
            session: StubProtocol.session(replying: [
                .response(status: status, body: Data(#"{"error":{"message":"unsupported"}}"#.utf8)),
                .response(status: 200, body: chatBody("ok")),
            ]))
        let result = try await sut.complete(system: "s", user: "u", jsonSchema: Self.schema)
        #expect(result == "ok")
        let requests = StubProtocol.requests
        #expect(requests.count == 2)
        #expect(try bodyJSON(requests[0])["response_format"] != nil)
        #expect(try bodyJSON(requests[1])["response_format"] == nil)
    }

    @Test func noRetryOnOtherErrors() async throws {
        do {
            _ = try await client(.response(status: 401, body: Data()))
                .complete(system: "s", user: "u", jsonSchema: Self.schema)
            Issue.record("expected error")
        } catch let error as LLMError {
            guard case .http(401, _) = error else {
                Issue.record("got \(error)")
                return
            }
        }
        #expect(StubProtocol.requests.count == 1)

        await #expect(throws: LLMError.modelNotReady) {
            _ = try await client(.response(status: 503, body: Data()))
                .complete(system: "s", user: "u", jsonSchema: Self.schema)
        }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func retryFailureIsReported() async throws {
        let sut = client(.response(status: 400, body: Data("bad".utf8)))
        do {
            _ = try await sut.complete(system: "s", user: "u", jsonSchema: Self.schema)
            Issue.record("expected error")
        } catch let error as LLMError {
            guard case .http(400, _) = error else {
                Issue.record("got \(error)")
                return
            }
        }
        #expect(StubProtocol.requests.count == 2)
    }
}
