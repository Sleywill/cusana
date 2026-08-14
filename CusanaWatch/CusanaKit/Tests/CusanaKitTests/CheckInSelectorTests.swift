import Foundation
import Testing
@testable import CusanaKit

/// The only place the app can show the wrong person's bill, so it gets the
/// most tests.
@Suite("Choosing which check-in to show")
struct CheckInSelectorTests {

    let identity = CheckInSelector.Identity(
        userID: "user_1", email: "diner@example.com", customerProfileID: "profile_1"
    )

    // MARK: - Ownership

    @Test("customer_id pointing at the CustomerProfile is recognised")
    func linkViaProfile() {
        // The likeliest real shape: the host creates the check-in at the till,
        // so the only link back to the diner is customer_id.
        let checkIn = makeCheckIn(customerId: "profile_1", createdById: "user_host")
        #expect(CheckInSelector.ownershipLink(of: checkIn, for: identity) == .customerIDMatchesProfile)
    }

    @Test("customer_id pointing at the User is recognised too")
    func linkViaUser() {
        let checkIn = makeCheckIn(customerId: "user_1", createdById: "user_host")
        #expect(CheckInSelector.ownershipLink(of: checkIn, for: identity) == .customerIDMatchesUser)
    }

    @Test("a diner-created check-in is recognised by created_by_id")
    func linkViaCreatedBy() {
        let checkIn = makeCheckIn(customerId: nil, createdById: "user_1")
        #expect(CheckInSelector.ownershipLink(of: checkIn, for: identity) == .createdByID)
    }

    @Test("created_by email matches case-insensitively")
    func linkViaEmail() {
        let checkIn = makeCheckIn(customerId: nil, createdById: nil, createdBy: "DINER@Example.com")
        #expect(CheckInSelector.ownershipLink(of: checkIn, for: identity) == .createdByEmail)
    }

    @Test("someone else's check-in matches nothing")
    func strangerIsRejected() {
        let checkIn = makeCheckIn(customerId: "profile_999", createdById: "user_999", createdBy: "other@example.com")
        #expect(CheckInSelector.ownershipLink(of: checkIn, for: identity) == nil)
    }

    @Test("a nil customer_id never matches a nil profile id")
    func nilsDoNotMatch() {
        // The bug this guards: an identity with no CustomerProfile matching
        // every check-in whose customer_id is also null.
        let anonymous = CheckInSelector.Identity(userID: "user_1", email: nil, customerProfileID: nil)
        let checkIn = makeCheckIn(customerId: nil, createdById: "user_999", createdBy: nil)
        #expect(CheckInSelector.ownershipLink(of: checkIn, for: anonymous) == nil)
    }

    // MARK: - Selection

    @Test("a closed check-in is never selected")
    func closedIsIgnored() {
        let checkIn = makeCheckIn(customerId: "profile_1", status: .closed)
        #expect(CheckInSelector.selectActive(from: [checkIn], identity: identity) == nil)
    }

    @Test("an unrecognised status is treated as open, not dropped")
    func unknownStatusIsOpen() {
        // Deliberate: `closed` is the only status ever observed, so we exclude
        // what we know is finished rather than allow-list what we think is live.
        // If Base44 adds "ordering", the diner still sees their bill.
        let checkIn = makeCheckIn(customerId: "profile_1", status: CheckInStatus(rawValue: "ordering"))
        #expect(CheckInSelector.selectActive(from: [checkIn], identity: identity)?.checkIn.id == checkIn.id)
    }

    @Test("the newest open check-in wins")
    func newestWins() {
        let older = makeCheckIn(id: "old", customerId: "profile_1", checkedInAt: date("2026-08-14T18:00:00Z"))
        let newer = makeCheckIn(id: "new", customerId: "profile_1", checkedInAt: date("2026-08-14T20:00:00Z"))

        let selection = CheckInSelector.selectActive(from: [older, newer], identity: identity)

        #expect(selection?.checkIn.id == "new")
    }

    @Test("a check-in with no timestamp loses to one that has a timestamp")
    func undatedSortsLast() {
        let dated = makeCheckIn(id: "dated", customerId: "profile_1", checkedInAt: date("2026-08-14T18:00:00Z"))
        let undated = makeCheckIn(id: "undated", customerId: "profile_1", checkedInAt: nil, createdDate: nil)

        #expect(CheckInSelector.selectActive(from: [undated, dated], identity: identity)?.checkIn.id == "dated")
    }

    @Test("an undated check-in is still selected when it is the only one")
    func undatedStillSelected() {
        // Showing an undated check beats showing nothing at a live demo.
        let undated = makeCheckIn(id: "undated", customerId: "profile_1", checkedInAt: nil, createdDate: nil)
        #expect(CheckInSelector.selectActive(from: [undated], identity: identity)?.checkIn.id == "undated")
    }

    @Test("created_date substitutes when checked_in_at is null")
    func createdDateFallback() {
        let older = makeCheckIn(id: "old", customerId: "profile_1", checkedInAt: nil, createdDate: date("2026-08-14T18:00:00Z"))
        let newer = makeCheckIn(id: "new", customerId: "profile_1", checkedInAt: nil, createdDate: date("2026-08-14T20:00:00Z"))

        #expect(CheckInSelector.selectActive(from: [older, newer], identity: identity)?.checkIn.id == "new")
    }

    @Test("another diner's open check-in yields nothing, not their bill")
    func neverShowsAStrangersBill() {
        // The failure that would be worst in front of an evaluator.
        let stranger = makeCheckIn(id: "stranger", customerId: "profile_999", createdById: "user_999")
        #expect(CheckInSelector.selectActive(from: [stranger], identity: identity) == nil)
    }

    @Test("mine is picked out of a crowd of other diners' check-ins")
    func picksMineFromMany() {
        let others = (1...5).map { makeCheckIn(id: "other\($0)", customerId: "profile_\($0 + 100)") }
        let mine = makeCheckIn(id: "mine", customerId: "profile_1", checkedInAt: date("2026-08-14T20:00:00Z"))

        let selection = CheckInSelector.selectActive(from: others + [mine], identity: identity)

        #expect(selection?.checkIn.id == "mine")
        #expect(selection?.link == .customerIDMatchesProfile)
    }

    @Test("an empty list yields nothing")
    func emptyList() {
        #expect(CheckInSelector.selectActive(from: [], identity: identity) == nil)
    }

    // MARK: - Orders

    @Test("a paid order is not offered for settling")
    func paidOrderIgnored() {
        #expect(CheckInSelector.selectOpenOrder(from: [makeOrder(status: .paid)]) == nil)
    }

    @Test("an unpaid order is selected")
    func openOrderSelected() {
        #expect(CheckInSelector.selectOpenOrder(from: [makeOrder(status: .open)])?.id == "order_1")
    }

    @Test("with several unpaid orders the newest wins")
    func newestOrderWins() {
        let older = makeOrder(id: "old", createdDate: date("2026-08-14T18:00:00Z"))
        let newer = makeOrder(id: "new", createdDate: date("2026-08-14T20:00:00Z"))
        #expect(CheckInSelector.selectOpenOrder(from: [older, newer])?.id == "new")
    }

    @Test("no orders at all yields nothing")
    func noOrders() {
        #expect(CheckInSelector.selectOpenOrder(from: []) == nil)
    }

    // MARK: - Fixtures

    private func date(_ iso: String) -> Date {
        CusanaDecoding.parseISO8601(iso)!
    }

    private func makeCheckIn(
        id: String = "checkin_1",
        customerId: String? = nil,
        status: CheckInStatus = .active,
        createdById: String? = nil,
        createdBy: String? = nil,
        checkedInAt: Date? = Date(timeIntervalSince1970: 1_786_000_000),
        createdDate: Date? = Date(timeIntervalSince1970: 1_786_000_000)
    ) -> CheckIn {
        CheckIn(
            id: id, guestName: nil, customerId: customerId, restaurantId: "rest_1",
            tableId: "table_1", allergyGroupId: nil, partySize: 2,
            checkedInAt: checkedInAt, status: status, stripePreauthId: nil,
            preauthAmount: nil, preauthStatus: nil, createdDate: createdDate,
            updatedDate: nil, createdById: createdById, createdBy: createdBy, isSample: false
        )
    }

    private func makeOrder(
        id: String = "order_1",
        status: OrderStatus = .open,
        createdDate: Date? = nil
    ) -> Order {
        Order(
            id: id, checkinId: "checkin_1", restaurantId: "rest_1", tableId: "table_1",
            subtotal: Amount(68), gratuityRate: 18, gratuityAmount: Amount(Decimal(string: "12.24")!),
            totalAmount: Amount(Decimal(string: "80.24")!), paymentCardUsed: "default",
            stripeChargeId: nil, status: status, createdDate: createdDate, updatedDate: nil,
            createdById: nil, createdBy: nil, isSample: false
        )
    }
}
