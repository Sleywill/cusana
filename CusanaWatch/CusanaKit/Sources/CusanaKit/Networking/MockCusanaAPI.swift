import Foundation

/// A canned backend.
///
/// Values match the one real settled record in `API-CONTRACT.md` — subtotal
/// 68.00, gratuity 18% = 12.24, total **80.24** — so previews, tests and the
/// simulator all show the exact figure the client quoted, and a layout that
/// fits here fits the real thing.
public struct MockCusanaAPI: CusanaAPI {
    public enum Scenario: Sendable {
        /// State B, with a bill.
        case seated
        /// State A.
        case notSeated
        /// An open check-in whose order is already paid.
        case seatedButSettled
        /// State E.
        case failing(CusanaError)
        /// State B, but slow enough to watch the spinner.
        case slow(Duration)
        /// An open check-in the identity rules cannot claim — the case that
        /// proves State A is reported rather than someone else's bill shown.
        case checkInBelongsToSomeoneElse
    }

    public let scenario: Scenario

    public init(scenario: Scenario = .seated) {
        self.scenario = scenario
    }

    // MARK: - Fixtures

    public static let userID = "user_demo_0001"
    public static let profileID = "profile_demo_0001"
    public static let checkInID = "checkin_demo_0001"

    public static let user = CusanaUser(
        id: userID, email: "diner@example.com", fullName: "Demo Diner", role: "user"
    )

    public static let profile = CustomerProfile(
        id: profileID, userId: userID, phoneNumber: nil, visitCount: 4, isVip: false,
        defaultGratuity: 18, defaultCardLabel: "default", defaultCardLast4: "4242"
    )

    public static let restaurant = Restaurant(
        id: "rest_demo_0001", name: "Patsy's", address: nil, phone: nil,
        createdDate: nil, updatedDate: nil
    )

    public static let table = Table(
        id: "table_demo_0012", restaurantId: restaurant.id, tableNumber: 12, capacity: 4,
        status: .occupied, positionX: nil, positionY: nil, createdDate: nil, updatedDate: nil
    )

    public static func checkIn(
        status: CheckInStatus = .active,
        customerID: String? = profileID
    ) -> CheckIn {
        CheckIn(
            id: checkInID, guestName: "Demo Diner", customerId: customerID,
            restaurantId: restaurant.id, tableId: table.id, allergyGroupId: nil,
            partySize: 2, checkedInAt: Date(timeIntervalSince1970: 1_786_000_000),
            status: status, stripePreauthId: nil, preauthAmount: nil, preauthStatus: nil,
            createdDate: Date(timeIntervalSince1970: 1_786_000_000), updatedDate: nil,
            createdById: "user_host_0001", createdBy: "host@patsys.example", isSample: false
        )
    }

    public static func order(status: OrderStatus = .open) -> Order {
        Order(
            id: "order_demo_0001", checkinId: checkInID, restaurantId: restaurant.id,
            tableId: table.id,
            subtotal: Amount(Decimal(string: "68.00")!),
            gratuityRate: 18,
            gratuityAmount: Amount(Decimal(string: "12.24")!),
            totalAmount: Amount(Decimal(string: "80.24")!),
            paymentCardUsed: "default", stripeChargeId: nil, status: status,
            createdDate: Date(timeIntervalSince1970: 1_786_000_100), updatedDate: nil,
            createdById: "user_host_0001", createdBy: "host@patsys.example", isSample: false
        )
    }

    /// The State B snapshot, without going through the service.
    public static let snapshot = CheckSnapshot(
        checkIn: checkIn(), order: order(), restaurant: restaurant, table: table,
        ownershipLink: .customerIDMatchesProfile
    )

    // MARK: - CusanaAPI

    public func currentUser() async throws -> CusanaUser {
        try await gate()
        return Self.user
    }

    public func customerProfile(forUser userID: String) async throws -> CustomerProfile? {
        try await gate()
        return Self.profile
    }

    public func checkIns(limit: Int) async throws -> [CheckIn] {
        try await gate()
        switch scenario {
        case .notSeated:
            return [Self.checkIn(status: .closed)]
        case .checkInBelongsToSomeoneElse:
            return [Self.checkIn(customerID: "profile_someone_else")]
        default:
            return [Self.checkIn()]
        }
    }

    public func orders(forCheckIn checkInID: String) async throws -> [Order] {
        try await gate()
        return [Self.order(status: scenario.isSettledOrder ? .paid : .open)]
    }

    public func restaurant(id: String) async throws -> Restaurant? {
        try await gate()
        return Self.restaurant
    }

    public func table(id: String) async throws -> Table? {
        try await gate()
        return Self.table
    }

    /// Applies the scenario's failure or delay to every call.
    private func gate() async throws {
        switch scenario {
        case .failing(let error): throw error
        case .slow(let delay): try await Task.sleep(for: delay)
        default: break
        }
    }
}

extension MockCusanaAPI.Scenario {
    var isSettledOrder: Bool {
        if case .seatedButSettled = self { return true }
        return false
    }
}

extension CusanaService {
    /// Preview/test convenience.
    public static func mock(_ scenario: MockCusanaAPI.Scenario = .seated) -> CusanaService {
        CusanaService(api: MockCusanaAPI(scenario: scenario))
    }
}
