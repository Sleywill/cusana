import Foundation

/// The four reads the watch needs, plus identity.
///
/// Milestone 1 is read-only on purpose — there is no settle method here yet.
/// Adding one is the first line of Milestone 2, and it is deliberately absent
/// rather than stubbed so nothing can call a fake success by accident.
public protocol CusanaAPI: Sendable {
    /// Who the baked token belongs to.
    func currentUser() async throws -> CusanaUser
    /// The wearer's profile, if one exists. Used only to resolve check-in
    /// ownership; a nil profile is normal, not an error.
    func customerProfile(forUser userID: String) async throws -> CustomerProfile?
    /// Every check-in the token can see. Ownership and open/closed filtering
    /// happen above this, in `CheckInSelector`, so they can be unit-tested.
    func checkIns(limit: Int) async throws -> [CheckIn]
    /// Orders belonging to a check-in.
    func orders(forCheckIn checkInID: String) async throws -> [Order]
    /// Nil rather than throwing when the venue cannot be read — the total is
    /// still worth showing without a name above it.
    func restaurant(id: String) async throws -> Restaurant?
    func table(id: String) async throws -> Table?
}

/// Records whether the backend honoured a query-string filter.
///
/// `API-CONTRACT.md` says entity endpoints take `?limit=N` but leaves
/// server-side filtering untested, and `M1-BUILD-SPEC.md` asks which one we
/// ended up using — it decides how the settle call is addressed in Milestone 2.
/// So the client always sends the filter, always re-applies it client-side, and
/// records what the server appeared to do.
public actor FilterCapabilityLog {
    public enum Result: String, Sendable {
        /// Server returned only matching records.
        case serverSideHonoured
        /// Server returned records we had to filter out ourselves.
        case ignoredByServer
        /// Nothing came back, so the question is unanswered.
        case inconclusive
    }

    public static let shared = FilterCapabilityLog()

    private var results: [String: Result] = [:]

    public func record(entity: String, parameter: String, result: Result) {
        results["\(entity)?\(parameter)"] = result
        CusanaLog.network.info("filter \(entity)?\(parameter) → \(result.rawValue)")
    }

    public func snapshot() -> [String: Result] { results }
}
