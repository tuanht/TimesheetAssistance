import Foundation

/// A service an entry can pull context from.
public enum IntegrationService: String, Codable, CaseIterable, Sendable {
    case jira, github

    public var displayName: String {
        switch self {
        case .jira: "Jira"
        case .github: "GitHub"
        }
    }
}

/// A Jira issue or GitHub pull request mentioned by an entry.
public enum ContextReference: Hashable, Sendable {
    case jira(key: String)
    case pullRequest(owner: String, repo: String, number: Int)

    /// "ABC-123" or "owner/repo#45".
    public var canonical: String {
        switch self {
        case .jira(let key): key
        case .pullRequest(let owner, let repo, let number): "\(owner)/\(repo)#\(number)"
        }
    }

    public var service: IntegrationService {
        switch self {
        case .jira: .jira
        case .pullRequest: .github
        }
    }
}
