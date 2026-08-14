import Foundation

// Base44 status fields are free-form strings. We have only ever observed
// `closed`, `paid` and `available` in live data, so a closed Swift `enum` would
// crash — or worse, silently drop a record — the first time the backend emits a
// value we have not seen. These are `RawRepresentable` string wrappers instead:
// exhaustive matching is impossible, unknown values round-trip intact, and the
// named constants still give autocomplete and typo-safety.

/// `CheckIn.status`
public struct CheckInStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Observed in live data.
    public static let closed = CheckInStatus(rawValue: "closed")
    /// Not yet observed — inferred as the counterpart to `closed`.
    public static let active = CheckInStatus(rawValue: "active")
    public static let open = CheckInStatus(rawValue: "open")

    /// A check-in the watch should render. Deliberately "not closed" rather
    /// than "is active": we know what a finished check-in looks like, and we do
    /// not yet know every name the backend gives a live one.
    public var isSettled: Bool { self == .closed }
}

/// `Order.status`
public struct OrderStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Observed in live data.
    public static let paid = OrderStatus(rawValue: "paid")
    /// Not yet observed.
    public static let open = OrderStatus(rawValue: "open")
    public static let pending = OrderStatus(rawValue: "pending")

    public var isSettled: Bool { self == .paid }
}

/// `Table.status`
public struct TableStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Observed in live data.
    public static let available = TableStatus(rawValue: "available")
    /// Not yet observed.
    public static let occupied = TableStatus(rawValue: "occupied")
}
