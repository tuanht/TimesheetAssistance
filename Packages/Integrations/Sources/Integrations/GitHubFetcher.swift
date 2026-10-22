import Foundation
import TimesheetCore

/// Reads a pull request with GitHub's `pull_request_read` tool.
public struct GitHubFetcher: ContextFetcher {
    private let tools: any ToolCalling

    public init(tools: any ToolCalling) {
        self.tools = tools
    }

    public func fetch(_ reference: ContextReference) async throws -> FetchedSource {
        guard case .pullRequest(let owner, let repo, let number) = reference else {
            throw ContextError.unexpectedReply(.github)
        }
        let result: JSONValue
        do {
            result = try await tools.callTool("pull_request_read", arguments: [
                "method": .string("get"),
                "owner": .string(owner),
                "repo": .string(repo),
                "pullNumber": .number(Double(number)),
            ])
        } catch let error as MCPToolError {
            // The raw message may hold PR text: classify it, never pass it on.
            throw error.message.lowercased().contains("404 not found")
                ? ContextError.notFound(reference.canonical)
                : ContextError.unexpectedReply(.github)
        }
        return try Self.source(from: result.decodedIfString, reference: reference)
    }

    static func source(from pr: JSONValue, reference: ContextReference) throws -> FetchedSource {
        guard let title = pr["title"]?.stringValue, let state = pr["state"]?.stringValue else {
            throw ContextError.unexpectedReply(.github)
        }
        var detail: String?
        if let head = pr["head"]?["ref"]?.stringValue, let base = pr["base"]?["ref"]?.stringValue {
            detail = "\(head) → \(base)"
        }
        return FetchedSource(
            reference: reference,
            title: title,
            state: pr["merged"] == .bool(true) ? "merged" : state,
            detail: detail,
            body: pr["body"]?.stringValue ?? "")
    }
}
