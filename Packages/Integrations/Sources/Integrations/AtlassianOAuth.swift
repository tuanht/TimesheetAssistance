import Foundation
import TimesheetCore

/// OAuth sign-in to Atlassian's MCP server: discovery, dynamic client registration and PKCE.
/// Atlassian's OAuth hosts get only OAuth traffic; the access token goes only to the MCP host,
/// through `credentials()`. Every error is a `ContextError` or `CancellationError`, never server text.
public struct AtlassianOAuth: Sendable {
    public static let redirectURI = URL(string: "timesheetassistant://oauth/atlassian")!
    static let callbackScheme = "timesheetassistant"
    static let clientName = "TimesheetAssistant"
    static let scope = "read:jira:agent-interface offline_access read:me"
    /// Refresh this long before expiry, so a token doesn't lapse mid-request.
    static let expirySkew: TimeInterval = 60
    static let resource = MCPServer.atlassian.url

    struct Endpoints {
        let authorization: URL
        let token: URL
        let registration: URL
    }

    private let store: any TokenStore
    private let presenter: any SignInPresenter
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let gate = RefreshGate()

    public init(store: any TokenStore, presenter: any SignInPresenter, session: URLSession? = nil) {
        self.init(store: store, presenter: presenter, session: session, now: Date.init)
    }

    init(
        store: any TokenStore, presenter: any SignInPresenter, session: URLSession?,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.presenter = presenter
        self.session = session ?? URLSession(
            configuration: .ephemeral, delegate: RedirectRefuser.shared, delegateQueue: nil)
        self.now = now
    }

    public func signIn() async throws {
        let endpoints = try await discover()
        let clientId = try await registeredClientId(at: endpoints.registration)
        let pkce = PKCE.make()
        let state = PKCE.randomToken()
        let callback = try await present(authorizeURL(endpoints.authorization, clientId: clientId, pkce: pkce, state: state))
        let code = try Self.code(from: callback, state: state)
        let reply = try await post(endpoints.token, form: [
            "grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirectURI.absoluteString,
            "client_id": clientId, "code_verifier": pkce.verifier, "resource": Self.resource.absoluteString,
        ])
        let token = try token(from: reply, clientId: clientId, keepingRefresh: nil)
        do { try store.setOAuthToken(token, for: .jiraOAuth) } catch { throw ContextError.signInAgain(.jira) }
    }

    public func credentials() -> any CredentialProvider {
        Credentials(oauth: self)
    }

    private struct Credentials: CredentialProvider {
        let oauth: AtlassianOAuth
        func credential() async throws -> Credential { .bearer(try await oauth.validToken().accessToken) }
    }

    // MARK: - Refresh

    /// The stored token, refreshed first when it expires within `expirySkew`.
    func validToken() async throws -> OAuthToken {
        // Inside the gate the store is read again, so a caller that saw a stale token reuses the refresh.
        try await gate.run { [self] in
            guard store.get(.jiraOAuth) != nil else { throw ContextError.notConnected(.jira) }
            guard let token = store.oauthToken(.jiraOAuth), !token.accessToken.isEmpty else {
                throw ContextError.signInAgain(.jira)
            }
            guard let expiresAt = token.expiresAt, expiresAt.timeIntervalSince(now()) <= Self.expirySkew else {
                return token
            }
            guard let refresh = token.refreshToken, !refresh.isEmpty else { throw ContextError.signInAgain(.jira) }
            let endpoints = try await discover()
            let reply = try await post(endpoints.token, form: [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": token.clientId,
                "resource": Self.resource.absoluteString,
            ])
            let fresh = try self.token(from: reply, clientId: token.clientId, keepingRefresh: refresh)
            // If saving fails the token still works now; the next refresh then asks to sign in again.
            try? store.setOAuthToken(fresh, for: .jiraOAuth)
            return fresh
        }
    }

    // MARK: - Steps

    func discover() async throws -> Endpoints {
        var resourceDoc = URLComponents()
        resourceDoc.scheme = Self.resource.scheme
        resourceDoc.host = Self.resource.host()
        resourceDoc.path = "/.well-known/oauth-protected-resource" + Self.resource.path()
        guard let resourceURL = resourceDoc.url else { throw ContextError.unexpectedReply(.jira) }

        let resource = try await get(resourceURL)
        guard case .array(let servers)? = resource["authorization_servers"],
              case .string(let first)? = servers.first, let issuer = URL(string: first), Self.isAtlassian(issuer)
        else { throw ContextError.unexpectedReply(.jira) }

        let metadata = try await get(issuer.appending(path: ".well-known/oauth-authorization-server"))
        guard let authorization = Self.atlassianURL(metadata["authorization_endpoint"]),
              let token = Self.atlassianURL(metadata["token_endpoint"]),
              let registration = Self.atlassianURL(metadata["registration_endpoint"]),
              case .array(let methods)? = metadata["code_challenge_methods_supported"], methods.contains(.string("S256"))
        else { throw ContextError.unexpectedReply(.jira) }
        return Endpoints(authorization: authorization, token: token, registration: registration)
    }

    /// The client ID from an earlier sign-in, or a new public client registered once.
    private func registeredClientId(at registration: URL) async throws -> String {
        if let clientId = store.oauthToken(.jiraOAuth)?.clientId, !clientId.isEmpty { return clientId }
        let body: JSONValue = .object([
            "client_name": .string(Self.clientName),
            "redirect_uris": .array([.string(Self.redirectURI.absoluteString)]),
            "grant_types": .array([.string("authorization_code"), .string("refresh_token")]),
            "response_types": .array([.string("code")]),
            "token_endpoint_auth_method": .string("none"),
        ])
        var request = Self.request(registration, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        guard case .string(let clientId)? = try await send(request)["client_id"], !clientId.isEmpty else {
            throw ContextError.unexpectedReply(.jira)
        }
        return clientId
    }

    private func authorizeURL(_ endpoint: URL, clientId: String, pkce: PKCE, state: String) throws -> URL {
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ContextError.unexpectedReply(.jira)
        }
        let query = FormEncoding.encode([
            "response_type": "code", "client_id": clientId, "redirect_uri": Self.redirectURI.absoluteString,
            "scope": Self.scope, "state": state, "code_challenge": pkce.challenge, "code_challenge_method": "S256",
            "resource": Self.resource.absoluteString,
        ])
        let existing = parts.percentEncodedQuery
        parts.percentEncodedQuery = [existing, query].compactMap { $0 }.joined(separator: "&")
        guard let url = parts.url else { throw ContextError.unexpectedReply(.jira) }
        return url
    }

    private func present(_ url: URL) async throws -> URL {
        do {
            return try await presenter.present(url, callbackScheme: Self.callbackScheme)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ContextError {
            throw error
        } catch {
            throw ContextError.signInAgain(.jira)
        }
    }

    /// The authorization code, if the callback is ours and its `state` matches.
    static func code(from callback: URL, state: String) throws -> String {
        guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == redirectURI.scheme, parts.host == redirectURI.host(), parts.path == redirectURI.path()
        else { throw ContextError.signInAgain(.jira) }
        let items = parts.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state, let code = value("code"), !code.isEmpty else {
            throw ContextError.signInAgain(.jira)
        }
        return code
    }

    private func token(from reply: JSONValue, clientId: String, keepingRefresh old: String?) throws -> OAuthToken {
        guard case .string(let access)? = reply["access_token"], !access.isEmpty else {
            throw ContextError.unexpectedReply(.jira)
        }
        var refresh = old
        if case .string(let value)? = reply["refresh_token"], !value.isEmpty { refresh = value }
        var expiresAt: Date?
        if case .number(let seconds)? = reply["expires_in"], seconds.isFinite { expiresAt = now().addingTimeInterval(seconds) }
        return OAuthToken(accessToken: access, refreshToken: refresh, expiresAt: expiresAt, clientId: clientId)
    }

    // MARK: - Hosts

    /// HTTPS, no credentials in the URL, and an Atlassian service host (never a tenant `*.atlassian.net` site).
    static func isAtlassian(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user() == nil, url.password() == nil,
              let host = url.host(percentEncoded: false)?.lowercased()
        else { return false }
        return host == "atlassian.com" || host.hasSuffix(".atlassian.com")
    }

    private static func atlassianURL(_ value: JSONValue?) -> URL? {
        guard case .string(let text)? = value, let url = URL(string: text), isAtlassian(url) else { return nil }
        return url
    }

    // MARK: - HTTP

    private static func request(_ url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get(_ url: URL) async throws -> JSONValue {
        try await send(Self.request(url, method: "GET"))
    }

    /// A token-endpoint call. A rejected code or refresh token (400/401) means signing in again.
    private func post(_ url: URL, form: [String: String]) async throws -> JSONValue {
        var request = Self.request(url, method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(FormEncoding.encode(form).utf8)
        return try await send(request, rejected: .signInAgain(.jira))
    }

    private func send(_ request: URLRequest, rejected: ContextError = .unexpectedReply(.jira)) async throws -> JSONValue {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectRefuser.shared)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw ContextError.unreachable(.jira)
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ContextError.unexpectedReply(.jira) }
        switch http.statusCode {
        case 200..<300: break
        // Redirects are refused, so Atlassian is effectively unreachable.
        case 300..<400: throw ContextError.unreachable(.jira)
        case 400, 401: throw rejected
        default: throw ContextError.unexpectedReply(.jira)
        }
        guard let reply = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = reply else {
            throw ContextError.unexpectedReply(.jira)
        }
        return reply
    }
}

/// Runs one refresh at a time and lets concurrent callers share it,
/// since a refresh token may be single-use.
private actor RefreshGate {
    private var inFlight: Task<OAuthToken, Error>?

    func run(_ work: @escaping @Sendable () async throws -> OAuthToken) async throws -> OAuthToken {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await work() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
