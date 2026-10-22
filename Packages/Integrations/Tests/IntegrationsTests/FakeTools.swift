import Foundation
@testable import Integrations

/// Records every tool call and answers with a fixed result or error.
actor FakeTools: ToolCalling {
    struct Call: Equatable {
        let name: String
        let arguments: [String: JSONValue]
    }

    private let outcome: Result<JSONValue, any Error>
    private(set) var calls: [Call] = []

    init(returning value: JSONValue) { outcome = .success(value) }
    init(throwing error: any Error) { outcome = .failure(error) }

    /// Parses `json` the way `MCPClient` parses a tool's text content.
    init(json: String) throws {
        self.init(returning: try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    func callTool(_ name: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        calls.append(Call(name: name, arguments: arguments))
        return try outcome.get()
    }
}
