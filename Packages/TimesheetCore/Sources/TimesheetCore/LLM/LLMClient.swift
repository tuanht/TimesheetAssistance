import Foundation

public protocol LLMClient: Sendable {
    func complete(system: String, user: String) async throws -> String
    /// Clients that can constrain decoding force the reply to match `jsonSchema`; the others ignore it.
    func complete(system: String, user: String, jsonSchema: String?) async throws -> String
}

extension LLMClient {
    public func complete(system: String, user: String, jsonSchema: String?) async throws -> String {
        try await complete(system: system, user: user)
    }
}

public enum LLMError: Error, Equatable, Sendable {
    /// Associated value is the endpoint origin (scheme, host, port), never credentials or path.
    case unreachable(String)
    /// Status code and a short, truncated server message.
    case http(Int, String)
    case timeout
    case emptyResponse
    case modelNotReady
    /// An on-device model is on disk but couldn't be loaded (damaged or unsupported files).
    case modelLoadFailed
    /// The server answered with a redirect; redirects are refused so notes never reach an unvetted host.
    case redirectRefused

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
            return "The model isn't ready. Download it in Settings › Models, or load it on your server, then try again."
        case .modelLoadFailed:
            return "Couldn't load the model. Delete it in Settings › Models and download it again."
        case .redirectRefused:
            return "The endpoint tried to redirect to another address. Use the final URL directly."
        }
    }
}
