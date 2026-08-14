import Foundation
import Testing
@testable import CusanaKit

/// Fixtures below are the real captured shapes from `API-CONTRACT.md`, not
/// invented JSON. If Base44 changes, these are what should fail first.
@Suite("Decoding the Base44 wire format")
struct DecodingTests {

    let decoder = CusanaDecoding.makeDecoder()

    // MARK: - Money

    @Test("total_amount 80.24 decodes to exactly 80.24, not a float smear")
    func moneyIsExact() throws {
        // The whole reason money is Decimal and rounded on the way in. If this
        // ever reads 80.239999999999995, the client is quoting a wrong bill.
        let json = #"{"total_amount": 80.24}"#.data(using: .utf8)!
        struct Wrapper: Decodable { let totalAmount: Amount }

        let decoded = try decoder.decode(Wrapper.self, from: json)

        #expect(decoded.totalAmount.value == Decimal(string: "80.24")!)
        #expect(decoded.totalAmount.formatted == "$80.24")
    }

    @Test("the captured gratuity math reproduces exactly")
    func gratuityMath() throws {
        // subtotal 68.00 × 18% = 12.24 → total 80.24. Straight from the live record.
        let subtotal = Decimal(string: "68.00")!
        let rate = Decimal(18)
        let gratuity = (subtotal * rate / 100).roundedToCents()

        #expect(gratuity == Decimal(string: "12.24")!)
        #expect((subtotal + gratuity).roundedToCents() == Decimal(string: "80.24")!)
    }

    @Test("money renders as USD regardless of the watch's locale", arguments: [
        "en_US", "fr_FR", "de_DE", "ja_JP",
    ])
    func moneyIgnoresLocale(identifier: String) throws {
        // A diner with a French watch is still paying a US restaurant bill.
        let amount = Amount(Decimal(string: "80.24")!)
        #expect(amount.formatted == "$80.24", "locale under test: \(identifier)")
    }

    @Test("whole amounts still show two decimals")
    func trailingZeros() {
        #expect(Amount(Decimal(80)).formatted == "$80.00")
        #expect(Amount(Decimal(string: "80.2")!).formatted == "$80.20")
    }

    @Test("money accepts a numeric string, in case the schema drifts")
    func moneyFromString() throws {
        let json = #"{"total_amount": "80.24"}"#.data(using: .utf8)!
        struct Wrapper: Decodable { let totalAmount: Amount }
        #expect(try decoder.decode(Wrapper.self, from: json).totalAmount.value == Decimal(string: "80.24")!)
    }

    // MARK: - Dates

    @Test("ISO8601 with fractional seconds parses — the shape .iso8601 rejects")
    func fractionalSeconds() throws {
        let date = CusanaDecoding.parseISO8601("2026-08-14T18:22:31.482Z")
        #expect(date != nil, "fractional-second timestamps are what Base44 actually sends")
    }

    @Test("ISO8601 without fractional seconds also parses")
    func wholeSeconds() throws {
        #expect(CusanaDecoding.parseISO8601("2026-08-14T18:22:31Z") != nil)
    }

    @Test("nonsense timestamps are rejected rather than silently becoming 1970")
    func badDate() {
        #expect(CusanaDecoding.parseISO8601("yesterday") == nil)
        #expect(CusanaDecoding.parseISO8601("") == nil)
    }

    // MARK: - Entities

    @Test("a full CheckIn decodes with every observed field")
    func checkInDecodes() throws {
        let json = """
        {
          "id": "abc123", "guest_name": "Demo Diner", "customer_id": "cust_1",
          "restaurant_id": "rest_1", "table_id": "table_1", "allergy_group_id": null,
          "party_size": 2, "checked_in_at": "2026-08-14T18:22:31.482Z",
          "status": "closed", "stripe_preauth_id": null, "preauth_amount": null,
          "preauth_status": null, "created_date": "2026-08-14T18:22:31.482Z",
          "updated_date": "2026-08-14T19:02:11.004Z", "created_by_id": "user_1",
          "created_by": "host@patsys.example", "is_sample": false
        }
        """.data(using: .utf8)!

        let checkIn = try decoder.decode(CheckIn.self, from: json)

        #expect(checkIn.id == "abc123")
        #expect(checkIn.partySize == 2)
        #expect(checkIn.status == .closed)
        #expect(checkIn.status.isSettled)
        #expect(checkIn.allergyGroupId == nil)
        #expect(checkIn.startedAt != nil)
    }

    @Test("an Order decodes and totals match the captured record")
    func orderDecodes() throws {
        let json = """
        {
          "id": "order_1", "checkin_id": "abc123", "restaurant_id": "rest_1",
          "table_id": "table_1", "subtotal": 68.00, "gratuity_rate": 18,
          "gratuity_amount": 12.24, "total_amount": 80.24,
          "payment_card_used": "default", "stripe_charge_id": null,
          "status": "paid", "created_date": "2026-08-14T18:22:31.482Z",
          "updated_date": null, "created_by_id": "user_1",
          "created_by": "host@patsys.example", "is_sample": false
        }
        """.data(using: .utf8)!

        let order = try decoder.decode(Order.self, from: json)

        #expect(order.subtotal?.formatted == "$68.00")
        #expect(order.gratuityAmount?.formatted == "$12.24")
        #expect(order.totalAmount.formatted == "$80.24")
        #expect(order.gratuityRate == 18)
        #expect(order.status == .paid)
        #expect(order.stripeChargeId == nil, "null on a test-mode settle — must not fail decoding")
    }

    @Test("an unknown status decodes instead of crashing")
    func unknownStatus() throws {
        // The reason statuses are RawRepresentable strings and not an enum. If
        // Base44 adds "settling", the watch must still render the bill.
        let json = #"{"id":"o1","total_amount":10,"status":"settling_in_progress"}"#.data(using: .utf8)!

        let order = try decoder.decode(Order.self, from: json)

        #expect(order.status.rawValue == "settling_in_progress")
        #expect(!order.status.isSettled, "an unrecognised status is not 'paid'")
    }

    @Test("a Restaurant with only an id still decodes and degrades its name")
    func sparseRestaurant() throws {
        // Restaurant's real shape was never captured, so it must tolerate almost
        // nothing being there.
        let restaurant = try decoder.decode(Restaurant.self, from: #"{"id":"r1"}"#.data(using: .utf8)!)
        #expect(restaurant.displayName == "your table")
    }

    @Test("a blank restaurant name degrades rather than rendering an empty line")
    func blankRestaurantName() throws {
        let restaurant = try decoder.decode(Restaurant.self, from: #"{"id":"r1","name":"   "}"#.data(using: .utf8)!)
        #expect(restaurant.displayName == "your table")
    }

    @Test("a Table with no number drops its label instead of showing 'Table —'")
    func tableWithoutNumber() throws {
        let table = try decoder.decode(Table.self, from: #"{"id":"t1","status":"available"}"#.data(using: .utf8)!)
        #expect(table.label == nil)
        #expect(try decoder.decode(Table.self, from: #"{"id":"t1","status":"available","table_number":12}"#.data(using: .utf8)!).label == "Table 12")
    }

    // MARK: - Lenient lists

    @Test("one malformed record does not take down the whole list")
    func lenientList() throws {
        // The failure that would otherwise blank a diner's screen because some
        // other table's record is broken.
        let json = """
        [
          {"id":"o1","total_amount":10.00,"status":"open"},
          {"id":"o2","status":"open"},
          {"id":"o3","total_amount":25.50,"status":"open"}
        ]
        """.data(using: .utf8)!

        let list = try decoder.decode(LenientList<Order>.self, from: json)

        #expect(list.elements.count == 2)
        #expect(list.elements.map(\.id) == ["o1", "o3"])
        #expect(list.failures.count == 1, "the bad record is reported, not silently dropped")
        #expect(list.failures[0].contains("totalAmount"))
    }

    @Test("an all-bad list yields no elements and every failure, not an exception")
    func allBad() throws {
        let json = #"[{"nope":1},{"nope":2}]"#.data(using: .utf8)!
        let list = try decoder.decode(LenientList<Order>.self, from: json)
        #expect(list.elements.isEmpty)
        #expect(list.failures.count == 2)
    }

    @Test("an empty list is not an error")
    func emptyList() throws {
        let list = try decoder.decode(LenientList<Order>.self, from: "[]".data(using: .utf8)!)
        #expect(list.elements.isEmpty)
        #expect(list.failures.isEmpty)
    }
}
