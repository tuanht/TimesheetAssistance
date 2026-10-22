import Foundation
import TimesheetCore

/// An Atlassian site the signed-in account can reach.
public struct JiraSite: Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}

/// Reads a Jira issue with Atlassian's `getJiraIssue` tool. Response shapes are unverified (see the spike findings).
public struct JiraFetcher: ContextFetcher {
    private let tools: any ToolCalling
    private let siteId: String

    public init(tools: any ToolCalling, siteId: String) {
        self.tools = tools
        self.siteId = siteId
    }

    /// The signed-in account, for Settings' Test. A restricted toolset maps to `.notApproved(.jira)`.
    public func userInfo() async throws -> JSONValue {
        try await call("atlassianUserInfo", arguments: [:], reference: nil).decodedIfString
    }

    public func sites() async throws -> [JiraSite] {
        let result = try await call("getAccessibleAtlassianResources", arguments: [:], reference: nil)
        guard case .array(let items) = result.decodedIfString else { throw ContextError.unexpectedReply(.jira) }
        return items.compactMap { item in
            guard let id = item["id"]?.stringValue, let name = item["name"]?.stringValue,
                  let link = item["url"]?.stringValue, let url = URL(string: link) else { return nil }
            return JiraSite(id: id, name: name, url: url)
        }
    }

    public func fetch(_ reference: ContextReference) async throws -> FetchedSource {
        guard case .jira(let key) = reference else { throw ContextError.unexpectedReply(.jira) }
        let result = try await call(
            "getJiraIssue",
            arguments: ["cloudId": .string(siteId), "issueIdOrKey": .string(key)],
            reference: reference)
        let fields = result.decodedIfString["fields"]
        guard let title = fields?["summary"]?.stringValue,
              let state = fields?["status"]?["name"]?.stringValue else {
            throw ContextError.unexpectedReply(.jira)
        }
        return FetchedSource(
            reference: reference,
            title: title,
            state: state,
            detail: fields?["issuetype"]?["name"]?.stringValue,
            body: Self.plainText(fields?["description"]))
    }

    private func call(_ name: String, arguments: [String: JSONValue], reference: ContextReference?) async throws -> JSONValue {
        do {
            return try await tools.callTool(name, arguments: arguments)
        } catch let error as MCPToolError {
            throw Self.contextError(for: error, reference: reference)
        }
    }

    static func contextError(for error: MCPToolError, reference: ContextReference?) -> ContextError {
        // The raw message may hold ticket text: classify it, never pass it on.
        let text = error.message.lowercased()
        // "MCP error -32602: Tool <name> not found": the toolset is restricted by an admin setting or token scopes.
        if text.range(of: #"\btool\s+\S+\s+not found"#, options: .regularExpression) != nil {
            return .notApproved(.jira)
        }
        if let reference, ["404", "not found", "does not exist"].contains(where: text.contains) {
            return .notFound(reference.canonical)
        }
        return .unexpectedReply(.jira)
    }

    /// A description as plain text: a string as-is, or ADF with one line per text block.
    static func plainText(_ description: JSONValue?) -> String {
        switch description {
        case .string(let text)?: text
        case let adf? where adf["type"] != nil: adfLines(adf).joined(separator: "\n")
        default: ""
        }
    }

    private static let inlineTypes: Set<String> = ["text", "hardBreak", "mention", "emoji", "inlineCard", "date", "status"]

    /// A block whose children are all inline becomes one line; other blocks recurse.
    private static func adfLines(_ node: JSONValue) -> [String] {
        guard case .array(let children)? = node["content"], !children.isEmpty else { return [] }
        let allInline = children.allSatisfy { inlineTypes.contains($0["type"]?.stringValue ?? "") }
        guard allInline else { return children.flatMap(adfLines) }
        let line = children.map { child -> String in
            if child["type"]?.stringValue == "hardBreak" { return "\n" }
            return child["text"]?.stringValue ?? ""
        }.joined()
        return line.isEmpty ? [] : [line]
    }
}
