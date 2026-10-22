import Foundation
import Testing
@testable import Integrations

struct PKCETests {
    /// RFC 7636 Appendix B.
    @Test func challengeMatchesRFC7636Vector() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierLengthAndCharset() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let first = PKCE.make()
        let second = PKCE.make()

        #expect((43...128).contains(first.verifier.count))
        #expect(first.verifier.allSatisfy(allowed.contains))
        #expect(first.challenge == PKCE.challenge(for: first.verifier))
        #expect(!first.challenge.contains("="))
        #expect(first.verifier != second.verifier)
    }
}
