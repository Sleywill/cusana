import Foundation

/// Where the app points and what it authenticates with.
///
/// Nothing here is a literal in Swift. The token arrives via
/// `Config/Secrets.xcconfig` → Info.plist → this struct, so the credential is
/// never in a source file and never in git. See `Config/Secrets.example.xcconfig`.
public struct CusanaConfig: Sendable, Equatable {
    public let host: String
    public let appID: String
    public let accessToken: String

    /// `https://<host>/api/apps/<appID>` — every entity path hangs off this.
    public let baseURL: URL

    public init(host: String, appID: String, accessToken: String) throws {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty else {
            throw CusanaError.notConfigured("CUSANA_API_HOST is empty.")
        }
        guard !appID.isEmpty else {
            throw CusanaError.notConfigured("CUSANA_APP_ID is empty.")
        }
        guard !accessToken.isEmpty, !Self.placeholders.contains(accessToken) else {
            throw CusanaError.notConfigured(
                "CUSANA_TOKEN is missing. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and paste the JWT."
            )
        }
        guard let baseURL = URL(string: "https://\(host)/api/apps/\(appID)") else {
            throw CusanaError.invalidURL("https://\(host)/api/apps/\(appID)")
        }

        self.host = host
        self.appID = appID
        self.accessToken = accessToken
        self.baseURL = baseURL
    }

    /// Values that mean "nobody filled this in" — an unsubstituted build
    /// setting reaches the plist verbatim, and it must not be sent as a token.
    private static let placeholders: Set<String> = [
        "$(CUSANA_TOKEN)",
        "PASTE_THE_JWT_HERE",
        "REPLACE_ME",
    ]

    /// When the baked token stops working, read from its own `exp` claim.
    /// Nil when the token is not a JWT or carries no expiry.
    public var tokenExpiry: Date? { JWT.expiry(of: accessToken) }

    /// Checked before the first request so an expired token produces
    /// "Session expired" immediately instead of a puzzling 403 mid-demo.
    public func validateTokenFreshness(now: Date = Date()) throws {
        if let tokenExpiry, tokenExpiry <= now {
            throw CusanaError.tokenExpired(on: tokenExpiry)
        }
    }
}

// MARK: - Loading from the app bundle

extension CusanaConfig {
    public enum InfoKey {
        public static let host = "CusanaAPIHost"
        public static let appID = "CusanaAppID"
        public static let accessToken = "CusanaAccessToken"
    }

    /// Reads the three Info.plist keys the xcconfig substitutes into.
    public static func fromBundle(_ bundle: Bundle = .main) throws -> CusanaConfig {
        func string(_ key: String) -> String {
            bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        }
        return try CusanaConfig(
            host: string(InfoKey.host),
            appID: string(InfoKey.appID),
            accessToken: string(InfoKey.accessToken)
        )
    }
}

// MARK: - JWT

/// Reads claims out of a token we already hold.
///
/// This is *not* validation — there is no signature check and there must not
/// be; the server is the only thing entitled to decide a token is good. It
/// exists so the watch can say "session expired" before spending ten seconds
/// on a request that was always going to 403.
enum JWT {
    static func expiry(of token: String) -> Date? {
        guard let exp = claims(of: token)?["exp"] else { return nil }
        // `exp` is seconds since epoch, but JSON may hand it back as either.
        if let seconds = exp as? Double { return Date(timeIntervalSince1970: seconds) }
        if let seconds = exp as? Int { return Date(timeIntervalSince1970: Double(seconds)) }
        return nil
    }

    static func claims(of token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, let payload = base64URLDecode(String(segments[1])) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // base64url drops the padding that Foundation's decoder insists on.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
