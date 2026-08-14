import Foundation
import Testing
@testable import CusanaKit

/// How the service behaves when parts of the backend misbehave.
///
/// The theme: decorative failures degrade, load-bearing failures surface. A
/// live demo should never get a red error screen because a venue name would not
/// load, and should never get a calm "no check-in" because something broke.
@Suite("Composing a check from a flaky backend")
struct ServiceTests {

    /// Lets each endpoint be failed independently.
    private struct PartialAPI: CusanaAPI {
        var failProfile = false
        var failRestaurant = false
        var failTable = false
        var failOrders = false
        var checkInCustomerID: String? = MockCusanaAPI.profileID

        func currentUser() async throws -> CusanaUser { MockCusanaAPI.user }

        func customerProfile(forUser userID: String) async throws -> CustomerProfile? {
            if failProfile { throw CusanaError.http(status: 500, body: nil) }
            return MockCusanaAPI.profile
        }

        func checkIns(limit: Int) async throws -> [CheckIn] {
            [MockCusanaAPI.checkIn(customerID: checkInCustomerID)]
        }

        func orders(forCheckIn checkInID: String) async throws -> [Order] {
            if failOrders { throw CusanaError.timedOut }
            return [MockCusanaAPI.order(status: .open)]
        }

        func restaurant(id: String) async throws -> Restaurant? {
            if failRestaurant { throw CusanaError.http(status: 404, body: nil) }
            return MockCusanaAPI.restaurant
        }

        func table(id: String) async throws -> Table? {
            if failTable { throw CusanaError.http(status: 404, body: nil) }
            return MockCusanaAPI.table
        }
    }

    @Test("a venue that will not load still shows the bill")
    func restaurantFailureDegrades() async throws {
        let service = CusanaService(api: PartialAPI(failRestaurant: true))

        let snapshot = try #require(await service.loadCurrentCheck())

        #expect(snapshot.total.formatted == "$80.24", "the number is the point; it must survive")
        #expect(snapshot.restaurant == nil)
        #expect(snapshot.restaurantName == "your table")
    }

    @Test("a table that will not load still shows the bill")
    func tableFailureDegrades() async throws {
        let service = CusanaService(api: PartialAPI(failTable: true))

        let snapshot = try #require(await service.loadCurrentCheck())

        #expect(snapshot.total.formatted == "$80.24")
        #expect(snapshot.tableLabel == nil, "the label is dropped rather than faked")
    }

    @Test("a failed profile lookup does not fail the screen")
    func profileFailureDegrades() async throws {
        // A 500 on CustomerProfile must not throw. It removes the
        // customer_id→profile link, so this check-in — whose customer_id points
        // at the profile — correctly falls through to State A, and the log says
        // why. What must never happen is the whole load throwing.
        let service = CusanaService(api: PartialAPI(failProfile: true))

        let snapshot = try await service.loadCurrentCheck()

        #expect(snapshot == nil)
    }

    @Test("with the profile down, a check-in linked by user id is still found")
    func profileFailureStillMatchesOtherLinks() async throws {
        // Same failure, but this check-in is reachable by customer_id == User.id,
        // so the diner still sees their bill.
        let service = CusanaService(
            api: PartialAPI(failProfile: true, checkInCustomerID: MockCusanaAPI.userID)
        )

        let snapshot = try #require(await service.loadCurrentCheck())

        #expect(snapshot.total.formatted == "$80.24")
        #expect(snapshot.ownershipLink == .customerIDMatchesUser)
    }

    @Test("a failed order fetch surfaces as an error, never as 'no check-in'")
    func orderFailureIsLoadBearing() async {
        // The distinction that matters: a broken backend must not look
        // identical to an empty one. State E, not State A.
        let service = CusanaService(api: PartialAPI(failOrders: true))

        await #expect(throws: CusanaError.timedOut) {
            try await service.loadCurrentCheck()
        }
    }

    @Test("everything working produces a complete snapshot")
    func happyPath() async throws {
        let snapshot = try #require(await CusanaService(api: PartialAPI()).loadCurrentCheck())

        #expect(snapshot.restaurantName == "Patsy's")
        #expect(snapshot.tableLabel == "Table 12")
        #expect(snapshot.total.formatted == "$80.24")
        #expect(snapshot.ownershipLink == .customerIDMatchesProfile)
        #expect(snapshot.order.subtotal?.formatted == "$68.00")
        #expect(snapshot.order.gratuityAmount?.formatted == "$12.24")
    }
}
