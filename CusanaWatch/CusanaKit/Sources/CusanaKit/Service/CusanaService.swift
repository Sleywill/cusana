import Foundation

/// Everything the watch shows in State B, resolved together.
public struct CheckSnapshot: Sendable, Equatable {
    public let checkIn: CheckIn
    public let order: Order
    /// Nil when the venue could not be read. The bill still renders.
    public let restaurant: Restaurant?
    /// Nil when the table could not be read, or the check-in has no table.
    public let table: Table?
    /// Which field proved this check-in belongs to the wearer. Recorded so the
    /// open question in `CheckInSelector` can be closed with real data.
    public let ownershipLink: CheckInSelector.OwnershipLink

    public var total: Amount { order.totalAmount }
    public var restaurantName: String { restaurant?.displayName ?? "your table" }
    public var tableLabel: String? { table?.label }

    /// The sentence the client asked for, verbatim:
    /// "you have a check for $80.24 at Patsy's"
    public var spokenSummary: String {
        "You have a check for \(total.accessibleDescription) at \(restaurantName)"
    }
}

/// Turns the five REST reads into the one thing the screen needs.
public struct CusanaService: Sendable {
    private let api: any CusanaAPI

    public init(api: any CusanaAPI) {
        self.api = api
    }

    /// Loads the wearer's current check, or nil for State A.
    ///
    /// Throws only on failures the diner needs to know about. A missing venue
    /// or table is degraded, not fatal — a bill with no restaurant name is
    /// still payable, and a red error screen at a live demo is not.
    public func loadCurrentCheck() async throws -> CheckSnapshot? {
        let user = try await api.currentUser()

        // Profile and check-ins are independent reads, so they overlap. On a
        // watch over Bluetooth-tethered networking this is the difference
        // between roughly one round trip and two.
        async let profileTask = loadProfile(userID: user.id)
        async let checkInsTask = api.checkIns(limit: 100)

        let profile = await profileTask
        let checkIns = try await checkInsTask

        let identity = CheckInSelector.Identity(
            userID: user.id,
            email: user.email,
            customerProfileID: profile?.id
        )

        guard let selection = CheckInSelector.selectActive(from: checkIns, identity: identity) else {
            CusanaLog.state.info("no open check-in for \(user.id) among \(checkIns.count) visible")
            return nil
        }

        CusanaLog.state.info(
            "check-in \(selection.checkIn.id) matched via \(selection.link.rawValue)"
        )

        let orders = try await api.orders(forCheckIn: selection.checkIn.id)
        guard let order = CheckInSelector.selectOpenOrder(from: orders) else {
            // A check-in that is open but whose order is already paid is not a
            // bill to settle. State A is the honest answer.
            CusanaLog.state.info(
                "check-in \(selection.checkIn.id) is open but has no unpaid order (\(orders.count) order(s) seen)"
            )
            return nil
        }

        let restaurantID = order.restaurantId ?? selection.checkIn.restaurantId
        let tableID = order.tableId ?? selection.checkIn.tableId

        // Both are cosmetic, both are fetched at once, and neither can fail the
        // screen — a bill with no venue name is still payable, and a red error
        // at a live demo is not. Failures are logged, never hidden.
        async let restaurantTask = loadRestaurant(id: restaurantID)
        async let tableTask = loadTable(id: tableID)

        return CheckSnapshot(
            checkIn: selection.checkIn,
            order: order,
            restaurant: await restaurantTask,
            table: await tableTask,
            ownershipLink: selection.link
        )
    }

    /// The profile lookup is allowed to fail, but never quietly.
    ///
    /// A missing profile is normal. A *failed* profile fetch is not: it removes
    /// the `customer_id == CustomerProfile.id` link, which is the likeliest way
    /// a check-in is tied to a diner. Losing it can turn a real bill into
    /// State A — the worst possible silent failure at a live demo — so it is
    /// logged as a warning that names the consequence.
    private func loadProfile(userID: String) async -> CustomerProfile? {
        do {
            return try await api.customerProfile(forUser: userID)
        } catch {
            let detail = (error as? CusanaError)?.diagnosticDescription ?? "\(error)"
            CusanaLog.network.warning(
                "CustomerProfile lookup failed for \(userID): \(detail) — ownership matching loses the customer_id→profile link and may fall through to State A"
            )
            return nil
        }
    }

    private func loadRestaurant(id: String?) async -> Restaurant? {
        guard let id else { return nil }
        do {
            return try await api.restaurant(id: id)
        } catch {
            log("Restaurant \(id)", error)
            return nil
        }
    }

    private func loadTable(id: String?) async -> Table? {
        guard let id else { return nil }
        do {
            return try await api.table(id: id)
        } catch {
            log("Table \(id)", error)
            return nil
        }
    }

    private func log(_ label: String, _ error: any Error) {
        let detail = (error as? CusanaError)?.diagnosticDescription ?? "\(error)"
        CusanaLog.network.notice("\(label) unavailable, continuing without it: \(detail)")
    }
}
