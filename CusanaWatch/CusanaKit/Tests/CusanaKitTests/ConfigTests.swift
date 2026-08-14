import Foundation
import Testing
@testable import CusanaKit

@Suite("Configuration and the baked token")
struct ConfigTests {

    /// A structurally valid JWT with the given expiry. Not signed by anything —
    /// the client only ever *reads* `exp`, it never validates.
    private func makeToken(expiringAt expiry: Date) -> String {
        func segment(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = segment(["alg": "HS256", "typ": "JWT"])
        let payload = segment(["exp": Int(expiry.timeIntervalSince1970), "sub": "user_1"])
        return "\(header).\(payload).not-a-real-signature"
    }

    @Test("the base URL is assembled exactly as captured from the live app")
    func baseURL() throws {
        let config = try CusanaConfig(
            host: "cusana-connect-core.base44.app",
            appID: "69fc9f3c47869d944ddbb02b",
            accessToken: "token"
        )
        #expect(config.baseURL.absoluteString ==
                "https://cusana-connect-core.base44.app/api/apps/69fc9f3c47869d944ddbb02b")
    }

    @Test("an empty token is refused with an instruction, not a crash")
    func emptyToken() {
        #expect(throws: CusanaError.self) {
            try CusanaConfig(host: "h", appID: "a", accessToken: "")
        }
    }

    @Test("an unsubstituted build setting is refused as a token", arguments: [
        "$(CUSANA_TOKEN)", "PASTE_THE_JWT_HERE", "REPLACE_ME",
    ])
    func placeholderToken(placeholder: String) {
        // If Secrets.xcconfig is missing, the literal `$(CUSANA_TOKEN)` reaches
        // the Info.plist. Sending that as a bearer token would produce a
        // baffling 403; "Setup needed" is the truth.
        #expect(throws: CusanaError.self) {
            try CusanaConfig(host: "h", appID: "a", accessToken: placeholder)
        }
    }

    @Test("surrounding whitespace is trimmed off a pasted token")
    func trimsWhitespace() throws {
        // Pasting out of a browser console reliably brings a newline along.
        let config = try CusanaConfig(host: " h ", appID: " a ", accessToken: "  abc.def.ghi\n")
        #expect(config.accessToken == "abc.def.ghi")
        #expect(config.host == "h")
    }

    @Test("the token's own expiry is read out of its exp claim")
    func readsExpiry() throws {
        let expiry = Date(timeIntervalSince1970: 1_794_614_400)
        let config = try CusanaConfig(host: "h", appID: "a", accessToken: makeToken(expiringAt: expiry))

        let read = try #require(config.tokenExpiry)
        #expect(abs(read.timeIntervalSince(expiry)) < 1)
    }

    @Test("an expired token fails before a request is ever sent")
    func expiredTokenIsCaughtEarly() throws {
        // The point: "Session expired" immediately, instead of ten seconds of
        // spinner followed by an unexplained 403 mid-demo.
        let config = try CusanaConfig(
            host: "h", appID: "a",
            accessToken: makeToken(expiringAt: Date(timeIntervalSinceNow: -3600))
        )
        #expect(throws: CusanaError.self) { try config.validateTokenFreshness() }
    }

    @Test("a live token passes the freshness check")
    func freshTokenPasses() throws {
        let config = try CusanaConfig(
            host: "h", appID: "a",
            accessToken: makeToken(expiringAt: Date(timeIntervalSinceNow: 86_400))
        )
        #expect(throws: Never.self) { try config.validateTokenFreshness() }
    }

    @Test("a non-JWT token has no readable expiry and is not blocked")
    func opaqueTokenIsAllowed() throws {
        // We must not refuse a token just because we cannot read it.
        let config = try CusanaConfig(host: "h", appID: "a", accessToken: "an-opaque-token")
        #expect(config.tokenExpiry == nil)
        #expect(throws: Never.self) { try config.validateTokenFreshness() }
    }

    @Test("the token fingerprint never reveals the token")
    func fingerprintIsSafe() {
        // Logs and the probe both print this. It must stay useless to a thief.
        let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.secret-signature-part"
        let fingerprint = CusanaLog.fingerprint(token)

        #expect(!fingerprint.contains("secret-signature-part"))
        #expect(fingerprint.count < token.count / 2)
        #expect(fingerprint.contains("\(token.count) chars"))
    }
}
