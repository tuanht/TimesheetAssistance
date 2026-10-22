import Foundation

public protocol LLMClient: Sendable {
    func complete(system: String, user: String) async throws -> String
}

public enum LLMError: Error, Equatable, Sendable {
    /// Associated value is the endpoint origin (scheme, host, port), never credentials or path.
    case unreachable(String)
    /// Status code and a short, truncated server message.
    case http(Int, String)
    case timeout
    case emptyResponse
    case modelNotReady

    public var userMessage: String {
        switch self {
        case .unreachable(let origin):
            return "Can't reach the endpoint at \(origin). Is the server running?"
        case .http(401, _), .http(403, _):
            return "The endpoint rejected the API key. Check the key in Settings."
        case .http(404, _):
            return "The endpoint returned 404 Not Found. Check the base URL and model name in Settings."
        case .http(let status, let message):
            let detail = message.isEmpty ? "" : ": \(message)"
            return "The endpoint returned HTTP \(status)\(detail)"
        case .timeout:
            return "The endpoint took too long to respond. Try again, or pick a smaller model."
        case .emptyResponse:
            return "The model returned an empty response. Try again."
        case .modelNotReady:
            return "The model isn't loaded on the endpoint yet. Load it in your server, then try again."
        }
    }
}
