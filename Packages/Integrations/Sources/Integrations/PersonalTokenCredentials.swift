import Foundation
import TimesheetCore

/// A personal token from the store: Jira API token as Basic with the account email, GitHub token as Bearer.
public struct PersonalTokenCredentials: CredentialProvider {
    private let service: IntegrationService
    private let email: String?
    private let store: any TokenStore

    public init(service: IntegrationService, email: String?, store: any TokenStore) {
        self.service = service
        self.email = email
        self.store = store
    }

    public func credential() async throws -> Credential {
        switch service {
        case .jira:
            let email = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let token = token(.jiraAPIToken), !email.isEmpty else { throw ContextError.notConnected(.jira) }
            return .basic(email: email, token: token)
        case .github:
            guard let token = token(.githubToken) else { throw ContextError.notConnected(.github) }
            return .bearer(token)
        }
    }

    private func token(_ key: TokenKey) -> String? {
        guard let token = store.get(key), !token.isEmpty else { return nil }
        return token
    }
}
