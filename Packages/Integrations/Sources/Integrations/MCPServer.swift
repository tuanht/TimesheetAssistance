import Foundation
import TimesheetCore

/// A remote MCP server and the read-only tools the app may call on it.
public struct MCPServer: Sendable {
    public let service: IntegrationService
    public let url: URL
    public let allowedTools: Set<String>

    /// Atlassian's endpoint for API-token auth. Tool names are unverified (see the spike findings).
    public static let atlassian = MCPServer(
        service: .jira,
        url: URL(string: "https://mcp.atlassian.com/v2/mcp")!,
        allowedTools: ["getJiraIssue", "getAccessibleAtlassianResources", "atlassianUserInfo"])

    public static let github = MCPServer(
        service: .github,
        url: URL(string: "https://api.githubcopilot.com/mcp/")!,
        allowedTools: ["pull_request_read", "get_me"])
}
