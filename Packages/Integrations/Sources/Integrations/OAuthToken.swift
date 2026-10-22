import Foundation
import TimesheetCore

/// An OAuth grant, stored as JSON under the `*OAuth` token keys.
public struct OAuthToken: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var clientId: String

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?, clientId: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.clientId = clientId
    }
}

extension TokenStore {
    /// The stored grant, or nil if it is missing or unreadable.
    public func oauthToken(_ key: TokenKey) -> OAuthToken? {
        guard let json = get(key) else { return nil }
        return try? JSONDecoder().decode(OAuthToken.self, from: Data(json.utf8))
    }

    public func setOAuthToken(_ token: OAuthToken, for key: TokenKey) throws {
        try set(String(decoding: JSONEncoder().encode(token), as: UTF8.self), for: key)
    }
}

/// The stored OAuth access token as Bearer. Refresh needs a client secret we don't ship,
/// so an expired token means signing in again.
public struct StoredOAuthCredentials: CredentialProvider {
    private let key: TokenKey
    private let service: IntegrationService
    private let store: any TokenStore
    private let now: @Sendable () -> Date

    public init(
        key: TokenKey, service: IntegrationService, store: any TokenStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.key = key
        self.service = service
        self.store = store
        self.now = now
    }

    public func credential() async throws -> Credential {
        guard store.get(key) != nil else { throw ContextError.notConnected(service) }
        guard let token = store.oauthToken(key), !token.accessToken.isEmpty else {
            throw ContextError.signInAgain(service)
        }
        if let expiresAt = token.expiresAt, expiresAt < now() { throw ContextError.signInAgain(service) }
        return .bearer(token.accessToken)
    }
}
