import Foundation

// Field names and types below are transcribed from API-CONTRACT.md, which was
// captured by intercepting the live web app — not from documentation. Base44
// publishes none.
//
// Everything except `id` and the field the screen cannot work without is
// optional. Real Base44 records carry nulls (`stripe_charge_id` is null on a
// settled order) and there is no schema guarantee that a field observed once is
// always present. An over-strict model turns a missing nullable into a blank
// screen at a live demo.
//
// Decoding uses `.convertFromSnakeCase`, so `total_amount` lands in
// `totalAmount` with no hand-written CodingKeys.

/// A diner's session at a table.
public struct CheckIn: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let guestName: String?
    public let customerId: String?
    public let restaurantId: String?
    public let tableId: String?
    public let allergyGroupId: String?
    public let partySize: Int?
    public let checkedInAt: Date?
    public let status: CheckInStatus
    public let stripePreauthId: String?
    public let preauthAmount: Amount?
    public let preauthStatus: String?
    public let createdDate: Date?
    public let updatedDate: Date?
    public let createdById: String?
    public let createdBy: String?
    public let isSample: Bool?

    /// Best available timestamp for "when did this check-in start", used to pick
    /// the newest one. `checked_in_at` is the true field; `created_date` is the
    /// fallback for records where it is null.
    public var startedAt: Date? { checkedInAt ?? createdDate }
}

/// The bill for a check-in.
public struct Order: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let checkinId: String?
    public let restaurantId: String?
    public let tableId: String?
    public let subtotal: Amount?
    /// Gratuity as a percentage, e.g. `18` — not `0.18`.
    public let gratuityRate: Decimal?
    public let gratuityAmount: Amount?
    /// What the watch shows. Subtotal + gratuity, already summed by the backend.
    public let totalAmount: Amount
    public let paymentCardUsed: String?
    public let stripeChargeId: String?
    public let status: OrderStatus
    public let createdDate: Date?
    public let updatedDate: Date?
    public let createdById: String?
    public let createdBy: String?
    public let isSample: Bool?
}

/// The venue. Only `name` is used by the watch, and even that degrades.
///
/// No Restaurant record was captured before this was written, so every field
/// beyond `id` is optional and the set is deliberately small. `scripts/probe.sh`
/// prints the raw JSON so the real shape can be confirmed against this.
public struct Restaurant: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let address: String?
    public let phone: String?
    public let createdDate: Date?
    public let updatedDate: Date?

    /// What to print when the venue could not be loaded or has no name.
    public var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "your table"
        }
        return name
    }
}

/// A physical table in the venue. Shown so the diner can confirm the watch is
/// looking at *their* check before they pay it.
public struct Table: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let restaurantId: String?
    public let tableNumber: Int?
    public let capacity: Int?
    public let status: TableStatus
    public let positionX: Double?
    public let positionY: Double?
    public let createdDate: Date?
    public let updatedDate: Date?

    /// `Table 12`, or nil when the number is missing — the label is dropped
    /// rather than rendered as "Table —".
    public var label: String? {
        guard let tableNumber else { return nil }
        return "Table \(tableNumber)"
    }
}

/// The diner's profile record.
///
/// The watch needs this for one reason: `CheckIn.customer_id` may point at a
/// `CustomerProfile.id` rather than at a `User.id`. In Cusana the *host* scans
/// the QR at the till, so the check-in is plausibly created by staff and the
/// only link back to the diner is `customer_id`. See `CheckInOwnership`.
public struct CustomerProfile: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let userId: String?
    public let phoneNumber: String?
    public let visitCount: Int?
    public let isVip: Bool?
    /// The diner's preferred tip percentage — the source of `Order.gratuity_rate`.
    public let defaultGratuity: Decimal?
    public let defaultCardLabel: String?
    public let defaultCardLast4: String?
}

/// The signed-in user, from `/auth/me`.
///
/// Used only to work out which check-in belongs to the wearer. Listing `User`
/// is 403 for a diner token; `/auth/me` is the supported way to ask "who am I".
public struct CusanaUser: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let email: String?
    public let fullName: String?
    public let role: String?
}
