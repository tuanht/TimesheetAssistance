import Foundation
import TimesheetCore

/// Where each secret lives in the token store.
public enum TokenKey: String, Sendable, CaseIterable {
    case jiraAPIToken = "jira-api-token", jiraOAuth = "jira-oauth"
    case githubToken = "github-token", githubOAuth = "github-oauth"

    public var service: IntegrationService {
        switch self {
        case .jiraAPIToken, .jiraOAuth: .jira
        case .githubToken, .githubOAuth: .github
        }
    }
}

/// Secure storage for tokens; the app backs it with the Keychain.
public protocol TokenStore: Sendable {
    func get(_ key: TokenKey) -> String?
    func set(_ value: String, for key: TokenKey) throws
    func delete(_ key: TokenKey)
}

/// Forgets every token of one service.
public enum Disconnect {
    public static func service(_ s: IntegrationService, store: any TokenStore) {
        for key in TokenKey.allCases where key.service == s {
            store.delete(key)
        }
    }
}
