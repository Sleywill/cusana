import Foundation

/// Every way the watch can fail to show a bill.
///
/// The cases are split by *what the diner should do about it*, not by where in
/// the stack the failure happened — that is what makes `title`/`message` worth
/// showing on a 41mm screen. `.unauthorised` is called out separately because
/// it is the single most likely failure in this build: the app carries a baked
/// bearer token, and when that token dies everything else looks fine.
public enum CusanaError: Error, Equatable, Sendable {
    /// No token was compiled in, or it is still the placeholder.
    case notConfigured(String)
    /// The token was rejected — 401/403. Expired, revoked, or wrong app.
    case unauthorised
    /// The baked token's `exp` claim is in the past. Caught before any request.
    case tokenExpired(on: Date)
    /// Any other non-2xx response.
    case http(status: Int, body: String?)
    /// Ran past the request timeout or our own deadline guard.
    case timedOut
    /// No route to the network at all.
    case offline
    /// URLSession failed for some other reason.
    case transport(String)
    /// The response was not the JSON we expect.
    case decoding(String)
    case invalidURL(String)
}

extension CusanaError {
    /// Short enough for a watch. Two or three words.
    public var title: String {
        switch self {
        case .notConfigured:        "Setup needed"
        case .unauthorised,
             .tokenExpired:         "Session expired"
        case .http:                 "Server error"
        case .timedOut:             "Timed out"
        case .offline:              "No connection"
        case .transport:            "Connection failed"
        case .decoding:             "Unexpected data"
        case .invalidURL:           "Setup needed"
        }
    }

    /// One line of plain language. No jargon, no status codes — the person
    /// reading this is sitting at a restaurant table, not debugging.
    public var message: String {
        switch self {
        case .notConfigured:
            "This build has no access token."
        case .unauthorised, .tokenExpired:
            "Cusana needs a new sign-in."
        case .http(let status, _):
            "Cusana returned an error (\(status))."
        case .timedOut:
            "Cusana took too long to answer."
        case .offline:
            "Check your iPhone or Wi-Fi."
        case .transport:
            "Couldn't reach Cusana."
        case .decoding:
            "Cusana sent something unexpected."
        case .invalidURL:
            "This build is misconfigured."
        }
    }

    /// Whether a Retry button is worth offering. A bad token will not fix
    /// itself, so offering Retry there just teaches the diner it does nothing.
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .offline, .transport, .http: true
        case .notConfigured, .unauthorised, .tokenExpired, .decoding, .invalidURL: false
        }
    }

    /// The full detail, for logs and the probe — never for the watch screen.
    public var diagnosticDescription: String {
        switch self {
        case .notConfigured(let hint):      "not configured: \(hint)"
        case .unauthorised:                 "unauthorised: token rejected (401/403)"
        case .tokenExpired(let date):       "token expired on \(date.formatted(.iso8601))"
        case .http(let status, let body):   "http \(status): \(body ?? "<empty body>")"
        case .timedOut:                     "timed out"
        case .offline:                      "offline"
        case .transport(let detail):        "transport: \(detail)"
        case .decoding(let detail):         "decoding: \(detail)"
        case .invalidURL(let detail):       "invalid URL: \(detail)"
        }
    }

    /// Maps a `URLError` onto the case that tells the diner the right thing.
    static func from(urlError: URLError) -> CusanaError {
        switch urlError.code {
        case .timedOut:
            .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .internationalRoamingOff:
            .offline
        default:
            .transport("\(urlError.code.rawValue) \(urlError.localizedDescription)")
        }
    }
}
