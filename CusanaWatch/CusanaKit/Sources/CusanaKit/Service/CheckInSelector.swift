import Foundation

/// Picks the one check-in the watch should show.
///
/// This is pure, separate and heavily tested because it is the only place the
/// app can show the *wrong person's bill*, and because how a check-in links
/// back to a diner is genuinely unresolved.
///
/// In Cusana the host scans the diner's QR at the till, so the `CheckIn` record
/// is plausibly created by restaurant staff, not by the diner. That makes
/// `created_by` an unreliable owner. `customer_id` is the real link, but it may
/// hold either a `User.id` or a `CustomerProfile.id` — the captured contract
/// does not say which, and the only closed record we have cannot settle it.
///
/// Rather than guess, all four plausible links are accepted and the one that
/// matched is reported, so a single live check-in tells us the answer for good.
/// See `scripts/probe.sh` and `cusana-probe`.
public enum CheckInSelector {

    /// Which field established that a check-in belongs to the wearer.
    public enum OwnershipLink: String, Sendable, CaseIterable {
        case customerIDMatchesProfile = "customer_id == CustomerProfile.id"
        case customerIDMatchesUser = "customer_id == User.id"
        case createdByID = "created_by_id == User.id"
        case createdByEmail = "created_by == User.email"
    }

    public struct Identity: Sendable, Equatable {
        public let userID: String
        public let email: String?
        public let customerProfileID: String?

        public init(userID: String, email: String? = nil, customerProfileID: String? = nil) {
            self.userID = userID
            self.email = email
            self.customerProfileID = customerProfileID
        }
    }

    public struct Selection: Sendable, Equatable {
        public let checkIn: CheckIn
        public let link: OwnershipLink
    }

    /// Returns the newest open check-in belonging to `identity`.
    ///
    /// "Open" is *not closed*, not *is active*: `closed` is the only status ever
    /// observed, so we can recognise a finished check-in but cannot enumerate
    /// the names a live one might have. Excluding what we know is done is safe;
    /// allow-listing what we think is live would blank the screen the moment
    /// Base44 introduces `seated` or `ordering`.
    public static func selectActive(
        from checkIns: [CheckIn],
        identity: Identity,
        now: Date = Date()
    ) -> Selection? {
        let open = checkIns.filter { !$0.status.isSettled }

        let owned: [Selection] = open.compactMap { checkIn in
            guard let link = ownershipLink(of: checkIn, for: identity) else { return nil }
            return Selection(checkIn: checkIn, link: link)
        }

        // Newest first. A check-in with no timestamp at all sorts last rather
        // than being dropped — the demo account is a single diner, and showing
        // an undated check beats showing nothing.
        let newest = owned.max { lhs, rhs in
            switch (lhs.checkIn.startedAt, rhs.checkIn.startedAt) {
            case let (l?, r?):  l < r
            case (nil, _?):     true
            case (_?, nil):     false
            case (nil, nil):    lhs.checkIn.id < rhs.checkIn.id
            }
        }

        if newest == nil, !open.isEmpty {
            // The distinction that matters at a demo: there *are* open
            // check-ins, we just cannot prove one is the wearer's.
            CusanaLog.state.error(
                "\(open.count) open check-in(s) visible but none matched identity \(identity.userID) — ownership field is not one of the four we handle"
            )
        }

        return newest
    }

    /// Public so `cusana-probe` can report, per check-in, which link held —
    /// that is how the open question above gets closed with real data.
    public static func ownershipLink(of checkIn: CheckIn, for identity: Identity) -> OwnershipLink? {
        if let profileID = identity.customerProfileID, checkIn.customerId == profileID {
            return .customerIDMatchesProfile
        }
        if checkIn.customerId == identity.userID {
            return .customerIDMatchesUser
        }
        if checkIn.createdById == identity.userID {
            return .createdByID
        }
        if let email = identity.email, let createdBy = checkIn.createdBy,
           createdBy.caseInsensitiveCompare(email) == .orderedSame {
            return .createdByEmail
        }
        return nil
    }

    /// Picks the unpaid order for a check-in.
    ///
    /// Orders are already narrowed to one check-in by the caller. If more than
    /// one is open — not expected, but cheap to handle — the newest wins, since
    /// that is the bill the diner is looking at.
    public static func selectOpenOrder(from orders: [Order]) -> Order? {
        let unpaid = orders.filter { !$0.status.isSettled }
        guard !unpaid.isEmpty else { return nil }
        if unpaid.count > 1 {
            CusanaLog.state.notice("\(unpaid.count) unpaid orders on one check-in; using the newest")
        }
        return unpaid.max { lhs, rhs in
            (lhs.createdDate ?? .distantPast) < (rhs.createdDate ?? .distantPast)
        }
    }
}
