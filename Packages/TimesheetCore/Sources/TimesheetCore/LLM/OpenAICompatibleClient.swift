import Foundation

public struct OpenAICompatibleClient: LLMClient {
    public let config: EndpointConfig
    private let apiKey: String?
    private let session: URLSession
    private let timeout: TimeInterval

    public init(config: EndpointConfig, apiKey: String?, session: URLSession = .shared, timeout: TimeInterval = 120) {
        self.config = config
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
    }

    public func complete(system: String, user: String) async throws -> String {
        var request = makeRequest(path: "chat/completions")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: config.model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            temperature: 0.2,
            stream: false))

        let data = try await send(request)
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw LLMError.emptyResponse }
        return content
    }

    public func testConnection() async throws -> [String] {
        var request = makeRequest(path: "models")
        request.httpMethod = "GET"
        let data = try await send(request)
        guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw LLMError.emptyResponse
        }
        return decoded.data.map(\.id)
    }

    // MARK: - Request plumbing

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: endpointURL(path), timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// `{base}/v1/{path}`, accepting a base that already ends in `/v1` (with or without a trailing slash).
    private func endpointURL(_ path: String) -> URL {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        var basePath = components.path
        while basePath.hasSuffix("/") { basePath.removeLast() }
        if !basePath.hasSuffix("/v1") { basePath += "/v1" }
        components.path = basePath + "/" + path
        components.query = nil
        components.fragment = nil
        return components.url ?? config.baseURL
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .timedOut ? LLMError.timeout : LLMError.unreachable(origin)
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.emptyResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 503:
            throw LLMError.modelNotReady
        default:
            throw LLMError.http(http.statusCode, Self.serverMessage(data))
        }
    }

    /// Scheme, host and port only, so credentials embedded in the URL never reach a message.
    private var origin: String {
        guard let scheme = config.baseURL.scheme, let host = config.baseURL.host() else {
            return "the configured URL"
        }
        let shownHost = host.contains(":") ? "[\(host)]" : host
        let port = config.baseURL.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(shownHost)\(port)"
    }

    /// Prefers the OpenAI-style `error.message`, else the raw text, truncated.
    private static func serverMessage(_ data: Data) -> String {
        let text: String
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            text = decoded.error.message
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 200 ? String(trimmed.prefix(200)) + "…" : trimmed
    }
}

private struct ChatRequest: Encodable {
    struct Message: Codable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }

    let choices: [Choice]
}

private struct ModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct ErrorResponse: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}
