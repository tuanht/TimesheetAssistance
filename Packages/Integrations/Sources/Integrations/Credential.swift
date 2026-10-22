import Foundation

/// What the app sends as `Authorization` to an MCP server.
public enum Credential: Sendable {
    case bearer(String)
    case basic(email: String, token: String)

    var authorizationHeader: String {
        switch self {
        case .bearer(let token):
            "Bearer \(token)"
        case .basic(let email, let token):
            "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
        }
    }
}

/// Supplies the current credential, refreshing it if needed.
public protocol CredentialProvider: Sendable {
    func credential() async throws -> Credential
}
