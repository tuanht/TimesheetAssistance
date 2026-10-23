import Foundation

/// How the app authenticates to an integration's MCP server.
public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    case personalToken, appSignIn

    public var displayName: String {
        switch self {
        case .personalToken: "Personal token"
        case .appSignIn: "App sign-in"
        }
    }

    /// A method added by a newer version reads as a personal token instead of failing the file.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AuthMethod(rawValue: raw) ?? .personalToken
    }
}

/// Non-secret Jira and GitHub settings. Tokens live in the Keychain, never here.
public struct IntegrationSettings: Codable, Equatable, Sendable {
    public var jiraMethod: AuthMethod
    /// The Atlassian cloudId of the chosen site.
    public var jiraSiteId: String?
    /// The account email used with a Jira API token.
    public var jiraEmail: String?
    public var githubMethod: AuthMethod
    public var githubAppClientId: String?
    /// "owner/repo", used for PR references written as a bare "#45".
    public var defaultRepo: String?

    public init(
        jiraMethod: AuthMethod, jiraSiteId: String?, jiraEmail: String?,
        githubMethod: AuthMethod, githubAppClientId: String?, defaultRepo: String?
    ) {
        self.jiraMethod = jiraMethod
        self.jiraSiteId = jiraSiteId
        self.jiraEmail = jiraEmail
        self.githubMethod = githubMethod
        self.githubAppClientId = githubAppClientId
        self.defaultRepo = defaultRepo
    }

    public static let `default` = IntegrationSettings(
        jiraMethod: .personalToken, jiraSiteId: nil, jiraEmail: nil,
        githubMethod: .personalToken, githubAppClientId: nil, defaultRepo: nil)
}

// MARK: Decoding
// Same forward-compatible rule as the other settings: an absent field takes its default.

extension IntegrationSettings {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IntegrationSettings.default
        self.init(
            jiraMethod: try c.decodeIfPresent(AuthMethod.self, forKey: .jiraMethod) ?? d.jiraMethod,
            jiraSiteId: try c.decodeIfPresent(String.self, forKey: .jiraSiteId) ?? d.jiraSiteId,
            jiraEmail: try c.decodeIfPresent(String.self, forKey: .jiraEmail) ?? d.jiraEmail,
            githubMethod: try c.decodeIfPresent(AuthMethod.self, forKey: .githubMethod) ?? d.githubMethod,
            githubAppClientId: try c.decodeIfPresent(String.self, forKey: .githubAppClientId)
                ?? d.githubAppClientId,
            defaultRepo: try c.decodeIfPresent(String.self, forKey: .defaultRepo) ?? d.defaultRepo)
    }
}
