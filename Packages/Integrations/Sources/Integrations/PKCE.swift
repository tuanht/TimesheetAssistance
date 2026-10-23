import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
#error("PKCE needs CryptoKit for SHA-256")
#endif

/// An RFC 7636 proof key: a random verifier and its S256 challenge, both base64url without padding.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public static func make() -> PKCE {
        let verifier = randomToken()
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 32 random bytes as 43 base64url characters; also used for the OAuth `state`.
    static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
