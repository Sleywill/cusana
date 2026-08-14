import Foundation

/// A money value.
///
/// Base44 sends money as a JSON number (`"total_amount": 80.24`). This is a
/// bill, so it is held as `Decimal` and never `Double`, and it is rounded to
/// cents on the way in — that makes the value exact regardless of whether the
/// JSON decoder routed the literal through a binary float.
public struct Amount: Hashable, Sendable, Comparable {
    public let value: Decimal

    public init(_ value: Decimal) {
        self.value = value.roundedToCents()
    }

    public static let zero = Amount(0)

    public static func < (lhs: Amount, rhs: Amount) -> Bool { lhs.value < rhs.value }
}

// MARK: - Codable

extension Amount: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Numbers are the observed shape. Strings are accepted too because a
        // Base44 schema change from number to string would otherwise take the
        // whole screen down, and a bill rendered from a string is still right.
        if let decimal = try? container.decode(Decimal.self) {
            self.init(decimal)
        } else if let string = try? container.decode(String.self),
                  let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) {
            self.init(decimal)
        } else {
            throw DecodingError.typeMismatch(
                Amount.self,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected a JSON number or numeric string for a money field."
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Display

extension Amount {
    /// `$80.24` — always a currency symbol, always two decimals.
    ///
    /// The demo is a US restaurant and the backend carries no currency code, so
    /// USD is hard-coded rather than guessed from the watch's locale. A diner
    /// with a French watch must still see `$80.24`, not `80,24 $US`.
    public var formatted: String {
        value.formatted(
            .currency(code: "USD")
                .locale(Locale(identifier: "en_US"))
                .precision(.fractionLength(2))
        )
    }

    /// Spoken by VoiceOver: "80 dollars and 24 cents".
    public var accessibleDescription: String {
        value.formatted(
            .currency(code: "USD")
                .locale(Locale(identifier: "en_US"))
                .presentation(.fullName)
        )
    }
}

extension Decimal {
    /// Rounds to 2 decimal places, half-up — the ordinary way money rounds.
    func roundedToCents() -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }
}
