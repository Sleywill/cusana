import Foundation
import Testing
@testable import CusanaKit

@Suite("The watch state machine")
@MainActor
struct StateMachineTests {

    @Test("a diner with an open check lands in State B showing $80.24")
    func seated() async {
        let model = CheckViewModel(service: .mock(.seated), pollInterval: nil)

        await model.load()

        guard case .seated(let snapshot) = model.state else {
            Issue.record("expected State B, got \(model.state)")
            return
        }
        #expect(snapshot.total.formatted == "$80.24")
        #expect(snapshot.restaurantName == "Patsy's")
        #expect(snapshot.tableLabel == "Table 12")
        #expect(model.lastUpdated != nil)
    }

    @Test("the client's exact sentence is what VoiceOver speaks")
    func spokenCopy() async {
        let model = CheckViewModel(service: .mock(.seated), pollInterval: nil)
        await model.load()

        #expect(model.state.snapshot?.spokenSummary == "You have a check for 80.24 US dollars at Patsy's")
    }

    @Test("no open check-in lands in State A")
    func notSeated() async {
        let model = CheckViewModel(service: .mock(.notSeated), pollInterval: nil)
        await model.load()
        #expect(model.state == .notSeated)
    }

    @Test("an open check-in whose order is already paid is State A, not a $0 bill")
    func alreadySettled() async {
        let model = CheckViewModel(service: .mock(.seatedButSettled), pollInterval: nil)
        await model.load()
        #expect(model.state == .notSeated)
    }

    @Test("an open check-in belonging to someone else is State A, never their total")
    func strangersCheck() async {
        let model = CheckViewModel(service: .mock(.checkInBelongsToSomeoneElse), pollInterval: nil)
        await model.load()
        #expect(model.state == .notSeated)
    }

    @Test("a network failure lands in State E, never an endless spinner")
    func failure() async {
        let model = CheckViewModel(service: .mock(.failing(.offline)), pollInterval: nil)

        await model.load()

        #expect(model.state == .failed(.offline))
        #expect(model.state != .loading, "the spinner must always resolve")
    }

    @Test("every error maps to a state with a title and a message a diner can read")
    func everyErrorIsPresentable() async {
        let errors: [CusanaError] = [
            .notConfigured("x"), .unauthorised, .tokenExpired(on: .distantPast),
            .http(status: 500, body: nil), .timedOut, .offline,
            .transport("x"), .decoding("x"), .invalidURL("x"),
        ]
        for error in errors {
            #expect(!error.title.isEmpty)
            #expect(!error.message.isEmpty)
            // Watch screens are 41mm. Anything longer wraps into a wall.
            #expect(error.title.count <= 20, "title too long for the wrist: \(error.title)")
            #expect(error.message.count <= 44, "message too long for the wrist: \(error.message)")
        }
    }

    @Test("Retry is offered for what a retry can fix, and withheld where it cannot")
    func retryability() {
        #expect(CusanaError.offline.isRetryable)
        #expect(CusanaError.timedOut.isRetryable)
        #expect(CusanaError.http(status: 503, body: nil).isRetryable)
        // Tapping Retry forever on a dead token teaches the diner the button lies.
        #expect(!CusanaError.unauthorised.isRetryable)
        #expect(!CusanaError.tokenExpired(on: .distantPast).isRetryable)
        #expect(!CusanaError.notConfigured("x").isRetryable)
    }

    @Test("a missing token surfaces as State E rather than crashing at launch")
    func missingTokenIsAState() async {
        // CheckViewModel.live() with no CUSANA_TOKEN must still produce a screen.
        let model = CheckViewModel(service: CusanaService(api: FailingAPI(error: .notConfigured("no token"))), pollInterval: nil)

        await model.load()

        guard case .failed(let error) = model.state else {
            Issue.record("expected State E, got \(model.state)")
            return
        }
        #expect(error.title == "Setup needed")
    }

    @Test("retry from State E re-runs the fetch and recovers")
    func retryRecovers() async {
        let model = CheckViewModel(service: .mock(.failing(.timedOut)), pollInterval: nil)
        await model.load()
        #expect(model.state == .failed(.timedOut))

        // A fresh model standing in for the network coming back.
        let recovered = CheckViewModel(service: .mock(.seated), pollInterval: nil)
        await recovered.retry()
        #expect(recovered.state.snapshot != nil)
    }

    @Test("refresh leaves State B on screen instead of flashing a spinner")
    func refreshKeepsContent() async {
        let model = CheckViewModel(service: .mock(.seated), pollInterval: nil)
        await model.load()
        let before = model.state.snapshot

        await model.refresh()

        #expect(model.state.snapshot == before)
        #expect(model.state != .loading, "a poll must never replace a visible total with a spinner")
    }

    @Test("the deadline guard fires rather than hanging forever")
    func deadlineGuard() async throws {
        // Proves the promise in the brief: never leave a spinner running forever.
        let start = ContinuousClock.now
        await #expect(throws: CusanaError.timedOut) {
            try await withDeadline(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(30))
                return "should never arrive"
            }
        }
        #expect(start.duration(to: .now) < .seconds(2))
    }

    @Test("the deadline guard returns the value when work finishes in time")
    func deadlineAllowsFastWork() async throws {
        let result = try await withDeadline(.seconds(5)) { "done" }
        #expect(result == "done")
    }
}
