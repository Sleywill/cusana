import Foundation
import Testing
@testable import CusanaKit

/// Exercises the real `LiveCusanaAPI` against a stubbed transport.
///
/// This is where the wire contract is pinned down: that the bearer header is
/// actually sent, that a 403 becomes the one error with its own screen, and
/// that a filter the server ignores is still applied locally. None of that is
/// visible from the higher-level tests, and all of it is what breaks at a demo.
/// `.serialized` because `URLProtocol` subclasses are instantiated by
/// URLSession and can only be wired up through static state — parallel tests
/// would consume each other's stubs.
@Suite("The live HTTP client", .serialized)
struct LiveAPITests {

    // MARK: - Stub transport

    /// Answers requests from a queue of canned responses and records what was
    /// asked for.
    final class StubProtocol: URLProtocol, @unchecked Sendable {
        struct Stub: Sendable {
            var status: Int = 200
            var json: String = "[]"
            var error: URLError?
        }

        // URLProtocol is instantiated by URLSession, so the wiring has to be
        // static. Guarded by a lock because URLSession calls in on its own queue.
        nonisolated(unsafe) private static var stubs: [Stub] = []
        nonisolated(unsafe) private static var recorded: [URLRequest] = []
        private static let lock = NSLock()

        static func reset(with stubs: [Stub]) {
            lock.withLock {
                self.stubs = stubs
                self.recorded = []
            }
        }

        static var requests: [URLRequest] {
            lock.withLock { recorded }
        }

        private static func next(for request: URLRequest) -> Stub {
            lock.withLock {
                recorded.append(request)
                return stubs.isEmpty ? Stub() : stubs.removeFirst()
            }
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let stub = Self.next(for: request)

            if let error = stub.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: stub.status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(stub.json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeAPI(_ stubs: [StubProtocol.Stub]) throws -> LiveCusanaAPI {
        StubProtocol.reset(with: stubs)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return LiveCusanaAPI(
            config: try CusanaConfig(
                host: "cusana-connect-core.base44.app",
                appID: "69fc9f3c47869d944ddbb02b",
                accessToken: "test.token.value"
            ),
            session: URLSession(configuration: configuration)
        )
    }

    // MARK: - Auth

    @Test("every request carries the bearer token")
    func sendsBearerHeader() async throws {
        // The single most load-bearing fact in the captured contract: 200 with
        // the header, 403 without, and no cookie fallback.
        let api = try makeAPI([.init(json: #"{"id":"u1","email":"a@b.c"}"#)])

        _ = try await api.currentUser()

        let request = try #require(StubProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test.token.value")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("requests go to the path the contract documents")
    func buildsCorrectPath() async throws {
        let api = try makeAPI([.init(json: "[]")])

        _ = try await api.checkIns(limit: 100)

        let url = try #require(StubProtocol.requests.first?.url)
        #expect(url.path == "/api/apps/69fc9f3c47869d944ddbb02b/entities/CheckIn")
        #expect(url.query?.contains("limit=100") == true)
    }

    @Test("403 becomes .unauthorised, which has its own screen", arguments: [401, 403])
    func rejectionBecomesUnauthorised(status: Int) async throws {
        // Not folded into the generic .http case: a dead token is the failure
        // most likely to appear in this build and it needs its own message.
        let api = try makeAPI([.init(status: status)])

        await #expect(throws: CusanaError.unauthorised) {
            try await api.checkIns(limit: 10)
        }
    }

    @Test("a server error keeps its status code for the log")
    func serverErrorIsReported() async throws {
        let api = try makeAPI([.init(status: 500, json: #"{"detail":"boom"}"#)])

        await #expect(throws: CusanaError.self) {
            try await api.checkIns(limit: 10)
        }
    }

    @Test("a dropped connection is reported as offline, not as a generic failure")
    func offlineMapping() async throws {
        // The diner needs "check your iPhone or Wi-Fi", not "transport error".
        let api = try makeAPI([.init(error: URLError(.notConnectedToInternet))])

        await #expect(throws: CusanaError.offline) {
            try await api.checkIns(limit: 10)
        }
    }

    @Test("a timeout is reported as a timeout")
    func timeoutMapping() async throws {
        let api = try makeAPI([.init(error: URLError(.timedOut))])

        await #expect(throws: CusanaError.timedOut) {
            try await api.checkIns(limit: 10)
        }
    }

    // MARK: - Filtering

    @Test("a filter the server ignores is still applied on the client")
    func clientSideFilterFallback() async throws {
        // API-CONTRACT.md leaves server-side filtering untested. If Base44
        // ignores ?checkin_id=, the watch must not render another table's order.
        let api = try makeAPI([.init(json: """
        [
          {"id":"o1","checkin_id":"WANTED","total_amount":80.24,"status":"open"},
          {"id":"o2","checkin_id":"SOMEONE_ELSE","total_amount":12.00,"status":"open"}
        ]
        """)])

        let orders = try await api.orders(forCheckIn: "WANTED")

        #expect(orders.count == 1)
        #expect(orders.first?.id == "o1")
    }

    @Test("the filter is sent to the server as well as applied locally")
    func sendsFilterParameter() async throws {
        let api = try makeAPI([.init(json: "[]")])

        _ = try await api.orders(forCheckIn: "abc123")

        let query = try #require(StubProtocol.requests.first?.url?.query)
        #expect(query.contains("checkin_id=abc123"))
    }

    // MARK: - Resilience

    @Test("one unparseable record does not fail the whole request")
    func lenientDecoding() async throws {
        let api = try makeAPI([.init(json: """
        [
          {"id":"o1","checkin_id":"C","total_amount":80.24,"status":"open"},
          {"id":"o2","checkin_id":"C","status":"open"}
        ]
        """)])

        let orders = try await api.orders(forCheckIn: "C")

        #expect(orders.count == 1, "the good record survives its broken neighbour")
    }

    @Test("a by-id miss falls back to scanning the collection")
    func byIDFallsBackToList() async throws {
        // GET /entities/{Entity}/{id} was never confirmed against a 404, so a
        // miss degrades to a list scan rather than failing the screen.
        let api = try makeAPI([
            .init(status: 404, json: #"{"detail":"not found"}"#),
            .init(json: #"[{"id":"r1","name":"Patsy's"},{"id":"r2","name":"Other"}]"#),
        ])

        let restaurant = try await api.restaurant(id: "r1")

        #expect(restaurant?.name == "Patsy's")
        #expect(StubProtocol.requests.count == 2, "it tried by-id first, then the list")
    }

    @Test("a bad token does not trigger the list-scan fallback")
    func unauthorisedSkipsFallback() async throws {
        // Scanning after a 403 would just produce a second 403 and double the
        // time the diner spends looking at a spinner.
        let api = try makeAPI([.init(status: 403)])

        await #expect(throws: CusanaError.unauthorised) {
            try await api.restaurant(id: "r1")
        }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test("an expired token fails before any request leaves the watch")
    func expiredTokenShortCircuits() async throws {
        let expired = "eyJhbGciOiJIUzI1NiJ9." + Data(#"{"exp":1000000000}"#.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "") + ".sig"

        StubProtocol.reset(with: [.init(json: "[]")])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = LiveCusanaAPI(
            config: try CusanaConfig(host: "h.example", appID: "a", accessToken: expired),
            session: URLSession(configuration: configuration)
        )

        await #expect(throws: CusanaError.self) { try await api.checkIns(limit: 10) }
        #expect(StubProtocol.requests.isEmpty, "no point spending a round trip on a dead token")
    }
}
