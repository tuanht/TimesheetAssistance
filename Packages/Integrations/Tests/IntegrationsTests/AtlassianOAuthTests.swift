import Foundation
import Testing
import TimesheetCore
@testable import Integrations

/// Answers OAuth requests from a queue of replies, in order.
/// State is static, so the suite using it is `.serialized`.
final class OAuthStubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [(status: Int, body: String)] = []
    nonisolated(unsafe) private static var captured: [URLRequest] = []

    static func session(_ replies: [(status: Int, body: String)]) -> URLSession {
        lock.withLock {
            self.replies = replies
            captured = []
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OAuthStubProtocol.self]
        return URLSession(configuration: config)
    }

    static var requests: [URLRequest] { lock.withLock { captured } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            request.httpBody = data
        }
        let reply = Self.lock.withLock {
            Self.captured.append(request)
            return Self.replies.isEmpty ? (status: 500, body: "") : Self.replies.removeFirst()
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Stands in for the browser: records the authorize URL and answers with a callback.
final class FakePresenter: SignInPresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var presented: [(url: URL, scheme: String?)] = []
    private let reply: @Sendable (URL) -> URL

    /// By default, approves: echoes `state` and returns a code.
    init(reply: @escaping @Sendable (URL) -> URL = { FakePresenter.callback(for: $0, code: "test-code") }) {
        self.reply = reply
    }

    var calls: [(url: URL, scheme: String?)] { lock.withLock { presented } }

    func present(_ url: URL, callbackScheme: String?) async throws -> URL {
        lock.withLock { presented.append((url, callbackScheme)) }
        return reply(url)
    }

    static func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    static func callback(for authorize: URL, code: String?, state: String? = nil) -> URL {
        var parts = URLComponents(string: "timesheetassistant://oauth/atlassian")!
        parts.queryItems = [URLQueryItem(name: "state", value: state ?? query(authorize)["state"])]
            + (code.map { [URLQueryItem(name: "code", value: $0)] } ?? [])
        return parts.url!
    }
}

@Suite(.serialized)
struct AtlassianOAuthTests {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let resourceURL = "https://mcp.atlassian.com/.well-known/oauth-protected-resource/v2/mcp"
    private static let metadataURL = "https://auth.atlassian.com/issuer-test/.well-known/oauth-authorization-server"
    private static let registerURL = "https://auth.atlassian.com/issuer-test/dcr/register"
    private static let tokenURL = "https://auth.atlassian.com/oauth/token"

    private static let resource = (status: 200, body: """
        {"resource":"https://mcp.atlassian.com/v2/mcp",\
        "authorization_servers":["https://auth.atlassian.com/issuer-test"],"bearer_methods_supported":["header"]}
        """)
    private static func metadata(
        authorization: String = "https://auth.atlassian.com/authorize", token: String = tokenURL
    ) -> (status: Int, body: String) {
        (200, """
            {"issuer":"https://auth.atlassian.com/issuer-test","authorization_endpoint":"\(authorization)",\
            "token_endpoint":"\(token)","registration_endpoint":"\(registerURL)",\
            "code_challenge_methods_supported":["S256"],"token_endpoint_auth_methods_supported":["none"],\
            "scopes_supported":["read:jira:agent-interface","offline_access","read:me","write:jira-work"]}
            """)
    }
    private static let registered = (status: 201, body: #"{"client_id":"test-client-1","client_name":"x"}"#)
    private static let granted = (status: 200, body: """
        {"access_token":"test-access-1","refresh_token":"test-refresh-1","expires_in":3600,"token_type":"Bearer"}
        """)

    private static func oauth(
        _ replies: [(status: Int, body: String)], store: MemoryTokenStore = MemoryTokenStore(),
        presenter: FakePresenter = FakePresenter()
    ) -> AtlassianOAuth {
        AtlassianOAuth(
            store: store, presenter: presenter, session: OAuthStubProtocol.session(replies), now: { now })
    }

    private static func form(of request: URLRequest) -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private static func stored(_ token: OAuthToken) -> MemoryTokenStore {
        let store = MemoryTokenStore()
        try? store.setOAuthToken(token, for: .jiraOAuth)
        return store
    }

    @Test func signInRunsDiscoverRegisterAuthorizeExchange() async throws {
        let store = MemoryTokenStore()
        let presenter = FakePresenter()
        let oauth = Self.oauth(
            [Self.resource, Self.metadata(), Self.registered, Self.granted], store: store, presenter: presenter)
        try await oauth.signIn()

        let requests = OAuthStubProtocol.requests
        #expect(requests.map { $0.url?.absoluteString } == [
            Self.resourceURL, Self.metadataURL, Self.registerURL, Self.tokenURL,
        ])
        #expect(requests.map(\.httpMethod) == ["GET", "GET", "POST", "POST"])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })

        let registration = try JSONDecoder().decode(JSONValue.self, from: requests[2].httpBody ?? Data())
        #expect(registration == .object([
            "client_name": .string("TimesheetAssistant"),
            "redirect_uris": .array([.string("timesheetassistant://oauth/atlassian")]),
            "grant_types": .array([.string("authorization_code"), .string("refresh_token")]),
            "response_types": .array([.string("code")]),
            "token_endpoint_auth_method": .string("none"),
        ]))

        let call = try #require(presenter.calls.first)
        #expect(presenter.calls.count == 1)
        #expect(call.scheme == "timesheetassistant")
        #expect(call.url.host() == "auth.atlassian.com")
        #expect(call.url.path() == "/authorize")
        let query = FakePresenter.query(call.url)
        let exchange = Self.form(of: requests[3])
        let verifier = try #require(exchange["code_verifier"])
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "test-client-1")
        #expect(query["redirect_uri"] == "timesheetassistant://oauth/atlassian")
        #expect(query["scope"] == "read:jira:agent-interface offline_access read:me")
        #expect(query["code_challenge"] == PKCE.challenge(for: verifier))
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["resource"] == "https://mcp.atlassian.com/v2/mcp")
        #expect((query["state"] ?? "").count >= 32)

        #expect(exchange == [
            "grant_type": "authorization_code", "code": "test-code",
            "redirect_uri": "timesheetassistant://oauth/atlassian", "client_id": "test-client-1",
            "code_verifier": verifier, "resource": "https://mcp.atlassian.com/v2/mcp",
        ])
        #expect(store.oauthToken(.jiraOAuth) == OAuthToken(
            accessToken: "test-access-1", refreshToken: "test-refresh-1",
            expiresAt: Self.now.addingTimeInterval(3600), clientId: "test-client-1"))
    }

    @Test(arguments: [
        #"{"authorization_servers":["https://auth.example.com/issuer-test"]}"#,
        #"{"authorization_servers":["http://auth.atlassian.com/issuer-test"]}"#,
        #"{"authorization_servers":["https://atlassian.com.example.net/issuer-test"]}"#,
        #"{"authorization_servers":["https://acme.atlassian.net/issuer-test"]}"#,
        #"{"authorization_servers":[]}"#,
    ])
    func rejectsForeignIssuer(resource: String) async {
        let store = MemoryTokenStore()
        let presenter = FakePresenter()
        let oauth = Self.oauth([(200, resource)], store: store, presenter: presenter)
        await #expect(throws: ContextError.unexpectedReply(.jira)) { try await oauth.signIn() }
        #expect(OAuthStubProtocol.requests.count == 1)
        #expect(presenter.calls.isEmpty)
        #expect(store.get(.jiraOAuth) == nil)
    }

    @Test(arguments: [
        metadata(authorization: "https://auth.atlassian.com.example.com/authorize"),
        metadata(authorization: "https://user:pw@auth.atlassian.com/authorize"),
        metadata(token: "https://example.com/oauth/token"),
        metadata(token: "http://auth.atlassian.com/oauth/token"),
        metadata(token: "https://acme.atlassian.net/oauth/token"),
    ])
    func rejectsForeignAuthorizationHost(metadata: (status: Int, body: String)) async {
        let store = MemoryTokenStore()
        let presenter = FakePresenter()
        let oauth = Self.oauth([Self.resource, metadata], store: store, presenter: presenter)
        await #expect(throws: ContextError.unexpectedReply(.jira)) { try await oauth.signIn() }
        #expect(OAuthStubProtocol.requests.count == 2)
        #expect(presenter.calls.isEmpty)
        #expect(store.get(.jiraOAuth) == nil)
    }

    @Test func rejectsMetadataWithoutS256() async {
        let body = Self.metadata().body.replacingOccurrences(of: #"["S256"]"#, with: #"["plain"]"#)
        let oauth = Self.oauth([Self.resource, (200, body)])
        await #expect(throws: ContextError.unexpectedReply(.jira)) { try await oauth.signIn() }
    }

    @Test(arguments: [
        "state-wrong",   // state mismatch
        "no-code",       // right state, no code
        "denied",        // user denied
        "foreign",       // callback to another URL
    ])
    func stateMismatchFails(kind: String) async {
        let presenter = FakePresenter { authorize in
            switch kind {
            case "state-wrong": return FakePresenter.callback(for: authorize, code: "test-code", state: "other")
            case "no-code": return FakePresenter.callback(for: authorize, code: nil)
            case "denied":
                let state = FakePresenter.query(authorize)["state"] ?? ""
                return URL(string: "timesheetassistant://oauth/atlassian?error=access_denied&state=\(state)")!
            default:
                let state = FakePresenter.query(authorize)["state"] ?? ""
                return URL(string: "timesheetassistant://evil/atlassian?code=test-code&state=\(state)")!
            }
        }
        let store = MemoryTokenStore()
        let oauth = Self.oauth(
            [Self.resource, Self.metadata(), Self.registered, Self.granted], store: store, presenter: presenter)
        await #expect(throws: ContextError.signInAgain(.jira)) { try await oauth.signIn() }
        #expect(!OAuthStubProtocol.requests.contains { $0.url?.absoluteString == Self.tokenURL })
        #expect(store.oauthToken(.jiraOAuth) == nil)
    }

    @Test func presenterCancellationPropagates() async {
        struct Closed: SignInPresenter {
            func present(_ url: URL, callbackScheme: String?) async throws -> URL { throw CancellationError() }
        }
        let oauth = AtlassianOAuth(
            store: MemoryTokenStore(), presenter: Closed(),
            session: OAuthStubProtocol.session([Self.resource, Self.metadata(), Self.registered]), now: { Self.now })
        await #expect(throws: CancellationError.self) { try await oauth.signIn() }
    }

    @Test func exchangeRejectedSignInAgain() async {
        let oauth = Self.oauth([
            Self.resource, Self.metadata(), Self.registered,
            (400, #"{"error":"invalid_grant","error_description":"server text"}"#),
        ])
        await #expect(throws: ContextError.signInAgain(.jira)) { try await oauth.signIn() }
    }

    @Test func registrationReusedOnSecondSignIn() async throws {
        let store = MemoryTokenStore()
        let oauth = Self.oauth(
            [Self.resource, Self.metadata(), Self.registered, Self.granted,
             Self.resource, Self.metadata(), Self.granted],
            store: store)
        try await oauth.signIn()
        try await oauth.signIn()

        let requests = OAuthStubProtocol.requests
        #expect(requests.filter { $0.url?.absoluteString == Self.registerURL }.count == 1)
        #expect(requests.count == 7)
        let second = try #require(requests.last)
        #expect(second.url?.absoluteString == Self.tokenURL)
        #expect(Self.form(of: second)["client_id"] == "test-client-1")
        #expect(store.oauthToken(.jiraOAuth)?.clientId == "test-client-1")
    }

    @Test func freshTokenNotRefreshed() async throws {
        let store = Self.stored(OAuthToken(
            accessToken: "test-access-0", refreshToken: "test-refresh-0",
            expiresAt: Self.now.addingTimeInterval(61), clientId: "test-client-1"))
        let credential = try await Self.oauth([], store: store).credentials().credential()
        #expect(credential.authorizationHeader == "Bearer test-access-0")
        #expect(OAuthStubProtocol.requests.isEmpty)
    }

    @Test func refreshesNearExpiry() async throws {
        let store = Self.stored(OAuthToken(
            accessToken: "test-access-0", refreshToken: "test-refresh-0",
            expiresAt: Self.now.addingTimeInterval(30), clientId: "test-client-1"))
        let oauth = Self.oauth([
            Self.resource, Self.metadata(),
            (200, #"{"access_token":"test-access-2","expires_in":3600,"token_type":"Bearer"}"#),
        ], store: store)
        let credential = try await oauth.credentials().credential()
        #expect(credential.authorizationHeader == "Bearer test-access-2")

        let requests = OAuthStubProtocol.requests
        #expect(requests.map { $0.url?.absoluteString } == [Self.resourceURL, Self.metadataURL, Self.tokenURL])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(Self.form(of: requests[2]) == [
            "grant_type": "refresh_token", "refresh_token": "test-refresh-0", "client_id": "test-client-1",
            "resource": "https://mcp.atlassian.com/v2/mcp",
        ])
        // No new refresh token in the reply: the old one is kept.
        #expect(store.oauthToken(.jiraOAuth) == OAuthToken(
            accessToken: "test-access-2", refreshToken: "test-refresh-0",
            expiresAt: Self.now.addingTimeInterval(3600), clientId: "test-client-1"))
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let store = Self.stored(OAuthToken(
            accessToken: "test-access-0", refreshToken: "test-refresh-0",
            expiresAt: Self.now, clientId: "test-client-1"))
        let provider = Self.oauth([Self.resource, Self.metadata(), Self.granted], store: store).credentials()
        async let first = provider.credential()
        async let second = provider.credential()
        let headers = try await [first.authorizationHeader, second.authorizationHeader]
        #expect(headers == ["Bearer test-access-1", "Bearer test-access-1"])
        #expect(OAuthStubProtocol.requests.count == 3)
    }

    @Test func refreshFailureSignInAgain() async {
        let store = Self.stored(OAuthToken(
            accessToken: "test-access-0", refreshToken: "test-refresh-0",
            expiresAt: Self.now.addingTimeInterval(-10), clientId: "test-client-1"))
        let oauth = Self.oauth([
            Self.resource, Self.metadata(),
            (400, #"{"error":"invalid_grant","error_description":"server text"}"#),
        ], store: store)
        await #expect(throws: ContextError.signInAgain(.jira)) { try await oauth.credentials().credential() }
    }

    @Test func expiredWithoutRefreshTokenSignInAgain() async {
        let store = Self.stored(OAuthToken(
            accessToken: "test-access-0", refreshToken: nil,
            expiresAt: Self.now.addingTimeInterval(-10), clientId: "test-client-1"))
        await #expect(throws: ContextError.signInAgain(.jira)) {
            try await Self.oauth([], store: store).credentials().credential()
        }
        #expect(OAuthStubProtocol.requests.isEmpty)
    }

    @Test func missingTokenNotConnected() async {
        await #expect(throws: ContextError.notConnected(.jira)) {
            try await Self.oauth([]).credentials().credential()
        }
    }
}
