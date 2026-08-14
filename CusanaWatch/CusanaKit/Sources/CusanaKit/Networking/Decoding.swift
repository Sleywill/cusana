import Foundation

public enum CusanaDecoding {
    /// The one decoder the whole client uses.
    ///
    /// - snake_case conversion, so models need no hand-written CodingKeys.
    /// - ISO8601 **with fractional seconds**. Foundation's built-in `.iso8601`
    ///   strategy rejects `2026-08-14T10:22:31.123Z` outright, which is the
    ///   shape Base44 actually sends, so the strategy is custom and tries both.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseISO8601(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an ISO8601 date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }

    // `Date.ISO8601FormatStyle` is a Sendable value type, unlike
    // `ISO8601DateFormatter`, so these are safe to share across tasks.
    private static let withFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func parseISO8601(_ string: String) -> Date? {
        if let date = try? withFractionalSeconds.parse(string) { return date }
        if let date = try? withoutFractionalSeconds.parse(string) { return date }
        return nil
    }
}

/// A list decoded record-by-record, where a record that fails to decode is
/// dropped instead of taking the request down with it.
///
/// This matters more than it looks. The watch fetches *all* check-ins and
/// filters client-side; a single malformed row belonging to another diner would
/// otherwise blank the screen of the person standing at the till. Failures are
/// carried out in `failures` so they can be logged — never silently discarded.
struct LenientList<Element: Decodable & Sendable>: Decodable {
    let elements: [Element]
    let failures: [String]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        var failures: [String] = []

        while !container.isAtEnd {
            // Decoding through `Attempt` is what makes this safe: a throwing
            // `container.decode(Element.self)` does not advance the unkeyed
            // container's index, so retrying would spin forever. `Attempt`
            // never throws, so the index always moves on.
            let attempt = try container.decode(Attempt<Element>.self)
            switch attempt {
            case .decoded(let element): elements.append(element)
            case .failed(let description): failures.append(description)
            }
        }

        self.elements = elements
        self.failures = failures
    }

    private enum Attempt<Value: Decodable>: Decodable {
        case decoded(Value)
        case failed(String)

        init(from decoder: any Decoder) throws {
            do {
                self = .decoded(try Value(from: decoder))
            } catch {
                self = .failed(Self.describe(error))
            }
        }

        private static func describe(_ error: any Error) -> String {
            guard let decodingError = error as? DecodingError else {
                return String(describing: error)
            }
            switch decodingError {
            case .keyNotFound(let key, let context):
                return "missing '\(key.stringValue)' at \(path(context))"
            case .typeMismatch(let type, let context):
                return "wrong type for \(type) at \(path(context))"
            case .valueNotFound(let type, let context):
                return "null where \(type) required at \(path(context))"
            case .dataCorrupted(let context):
                return "corrupt value at \(path(context)): \(context.debugDescription)"
            @unknown default:
                return String(describing: decodingError)
            }
        }

        private static func path(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "<root>" : path
        }
    }
}
