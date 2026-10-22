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
        let result = try await call("pull_request_read", arguments: [
            "method": .string("get"),
            "owner": .string(owner),
            "repo": .string(repo),
            "pullNumber": .number(Double(number)),
        ], reference: reference)
        return try Self.source(from: result.decodedIfString, reference: reference)
    }

    /// The signed-in account, for Settings' Test.
    public func me() async throws -> JSONValue {
        try await call("get_me", arguments: [:], reference: nil).decodedIfString
    }

    private func call(_ name: String, arguments: [String: JSONValue], reference: ContextReference?) async throws -> JSONValue {
        do {
            return try await tools.callTool(name, arguments: arguments)
        } catch let error as MCPToolError {
            // The raw message may hold PR text: classify it, never pass it on.
            if let reference, error.message.lowercased().contains("404 not found") {
                throw ContextError.notFound(reference.canonical)
            }
            throw ContextError.unexpectedReply(.github)
        }
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
