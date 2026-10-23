import Foundation
import TimesheetCore

/// Calls one MCP tool. `MCPClient` in the app; a fake in tests.
public protocol ToolCalling: Sendable {
    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> JSONValue
}

extension MCPClient: ToolCalling {}

/// Fetches one referenced issue or pull request.
public protocol ContextFetcher: Sendable {
    func fetch(_ reference: ContextReference) async throws -> FetchedSource
}

extension JSONValue {
    var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// Tool text that `MCPClient` couldn't parse is kept as a string; try once more here.
    var decodedIfString: JSONValue {
        guard case .string(let text) = self,
              let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return self }
        return value
    }
}
