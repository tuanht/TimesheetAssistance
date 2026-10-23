import Foundation
import Testing
import TimesheetCore
@testable import Integrations

/// An in-memory `TokenStore` for tests.
final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TokenKey: String]

    init(_ values: [TokenKey: String] = [:]) { self.values = values }

    func get(_ key: TokenKey) -> String? { lock.withLock { values[key] } }
    func set(_ value: String, for key: TokenKey) throws { lock.withLock { values[key] = value } }
    func delete(_ key: TokenKey) { _ = lock.withLock { values.removeValue(forKey: key) } }
}

struct PersonalTokenCredentialsTests {
    private static let token = "test-token-0123456789"

    @Test func jiraUsesBasicWithEmail() async throws {
        let store = MemoryTokenStore([.jiraAPIToken: Self.token])
        let credential = try await PersonalTokenCredentials(service: .jira, email: "dev@example.com", store: store)
            .credential()
        #expect(credential.authorizationHeader
            == "Basic " + Data("dev@example.com:\(Self.token)".utf8).base64EncodedString())
    }

    @Test func githubUsesBearer() async throws {
        let store = MemoryTokenStore([.githubToken: Self.token])
        let credential = try await PersonalTokenCredentials(service: .github, email: nil, store: store).credential()
        #expect(credential.authorizationHeader == "Bearer \(Self.token)")
    }

    @Test(arguments: IntegrationService.allCases)
    func missingTokenNotConnected(service: IntegrationService) async {
        let provider = PersonalTokenCredentials(service: service, email: "dev@example.com", store: MemoryTokenStore())
        await #expect(throws: ContextError.notConnected(service)) { try await provider.credential() }
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func missingEmailNotConnected(email: String?) async {
        let store = MemoryTokenStore([.jiraAPIToken: Self.token])
        let provider = PersonalTokenCredentials(service: .jira, email: email, store: store)
        await #expect(throws: ContextError.notConnected(.jira)) { try await provider.credential() }
    }

    @Test func oauthTokenUsesBearer() async throws {
        let store = MemoryTokenStore()
        try store.setOAuthToken(
            OAuthToken(accessToken: Self.token, refreshToken: nil, expiresAt: nil, clientId: "client-1"),
            for: .githubOAuth)
        let credential = try await StoredOAuthCredentials(key: .githubOAuth, service: .github, store: store)
            .credential()
        #expect(credential.authorizationHeader == "Bearer \(Self.token)")
    }

    @Test func expiredOAuthSignInAgain() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = MemoryTokenStore()
        try store.setOAuthToken(
            OAuthToken(
                accessToken: Self.token, refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(-1),
                clientId: "client-1"),
            for: .githubOAuth)
        let provider = StoredOAuthCredentials(key: .githubOAuth, service: .github, store: store, now: { now })
        await #expect(throws: ContextError.signInAgain(.github)) { try await provider.credential() }
    }

    @Test func missingOAuthNotConnected() async {
        let provider = StoredOAuthCredentials(key: .jiraOAuth, service: .jira, store: MemoryTokenStore())
        await #expect(throws: ContextError.notConnected(.jira)) { try await provider.credential() }
    }

    @Test func unreadableOAuthSignInAgain() async {
        let store = MemoryTokenStore([.githubOAuth: "not json"])
        let provider = StoredOAuthCredentials(key: .githubOAuth, service: .github, store: store)
        await #expect(throws: ContextError.signInAgain(.github)) { try await provider.credential() }
    }

    @Test func disconnectDeletesBothKeys() {
        let store = MemoryTokenStore(Dictionary(uniqueKeysWithValues: TokenKey.allCases.map { ($0, "value") }))
        Disconnect.service(.jira, store: store)
        #expect(store.get(.jiraAPIToken) == nil)
        #expect(store.get(.jiraOAuth) == nil)
        #expect(store.get(.githubToken) == "value")
        #expect(store.get(.githubOAuth) == "value")

        Disconnect.service(.github, store: store)
        #expect(store.get(.githubToken) == nil)
        #expect(store.get(.githubOAuth) == nil)
    }
}
