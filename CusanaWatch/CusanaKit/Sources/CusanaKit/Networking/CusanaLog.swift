import Foundation
import OSLog

/// Loggers for the whole kit.
///
/// Errors are logged with context at the point they are caught and then
/// rethrown — never caught and turned into a default value. If the watch shows
/// State A ("no active check-in"), the log says whether that was genuinely no
/// data or a record that failed to decode.
public enum CusanaLog {
    private static let subsystem = "xyz.sleywil.cusanawatch"

    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let decoding = Logger(subsystem: subsystem, category: "decoding")
    public static let state = Logger(subsystem: subsystem, category: "state")

    /// Redacts a bearer token down to something safe to print.
    ///
    /// The probe and the logs both want to say *which* token is in play without
    /// ever emitting one. Never log `accessToken` directly.
    public static func fingerprint(_ token: String) -> String {
        guard token.count > 12 else { return "<\(token.count) chars>" }
        return "\(token.prefix(6))…\(token.suffix(4)) (\(token.count) chars)"
    }
}
