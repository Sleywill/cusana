import Foundation

/// The real Base44 client.
///
/// Wire format is per `API-CONTRACT.md`: every request carries
/// `Authorization: Bearer <jwt>`, entity lists live at
/// `{base}/entities/{Entity}`, and identity at `{base}/auth/me`. Verified by
/// experiment: identical requests are 200 with the header and 403 without, and
/// there is no cookie fallback — which is precisely why a native client works.
public struct LiveCusanaAPI: CusanaAPI {
    public let config: CusanaConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    /// Our own guard on top of URLSession's. See `withDeadline`.
    private let deadline: Duration

    public init(
        config: CusanaConfig,
        session: URLSession? = nil,
        deadline: Duration = .seconds(12)
    ) {
        self.config = config
        self.session = session ?? Self.makeSession()
        self.decoder = CusanaDecoding.makeDecoder()
        self.deadline = deadline
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        // The bill must be current. A cached total is worse than no total.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - CusanaAPI

    public func currentUser() async throws -> CusanaUser {
        try await get(CusanaUser.self, path: "auth/me")
    }

    public func customerProfile(forUser userID: String) async throws -> CustomerProfile? {
        let profiles: [CustomerProfile] = try await getList(
            CustomerProfile.self,
            entity: "CustomerProfile",
            filter: ("user_id", userID),
            matches: { $0.userId == userID }
        )
        return profiles.first
    }

    public func checkIns(limit: Int = 100) async throws -> [CheckIn] {
        try await getList(
            CheckIn.self,
            entity: "CheckIn",
            filter: nil,
            matches: { _ in true },
            limit: limit
        )
    }

    public func orders(forCheckIn checkInID: String) async throws -> [Order] {
        try await getList(
            Order.self,
            entity: "Order",
            filter: ("checkin_id", checkInID),
            matches: { $0.checkinId == checkInID }
        )
    }

    public func restaurant(id: String) async throws -> Restaurant? {
        try await entity(Restaurant.self, named: "Restaurant", id: id)
    }

    public func table(id: String) async throws -> Table? {
        try await entity(Table.self, named: "Table", id: id)
    }

    // MARK: - Entity fetch strategies

    /// Fetches one record by id, falling back to a list scan.
    ///
    /// `GET /entities/{Entity}/{id}` is used in the web app but was never
    /// confirmed against a 404, so a miss degrades to fetching the collection
    /// and finding the record rather than failing the screen.
    private func entity<T: Decodable & Sendable & Identifiable>(
        _ type: T.Type,
        named entityName: String,
        id: String
    ) async throws -> T? where T.ID == String {
        do {
            return try await get(T.self, path: "entities/\(entityName)/\(id)")
        } catch let error as CusanaError {
            // A bad token is fatal everywhere; do not paper over it with a scan.
            if case .unauthorised = error { throw error }

            CusanaLog.network.notice(
                "\(entityName)/\(id) by-id fetch failed (\(error.diagnosticDescription)); falling back to list scan"
            )
            let all: [T] = try await getList(
                T.self, entity: entityName, filter: nil, matches: { _ in true }
            )
            return all.first { $0.id == id }
        }
    }

    /// Fetches a collection, sending the server-side filter *and* re-applying
    /// it locally, then recording which of the two actually did the work.
    private func getList<T: Decodable & Sendable>(
        _ type: T.Type,
        entity entityName: String,
        filter: (name: String, value: String)?,
        matches: (T) -> Bool,
        limit: Int = 100
    ) async throws -> [T] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let filter {
            query.append(URLQueryItem(name: filter.name, value: filter.value))
        }

        let list = try await getLenientList(T.self, path: "entities/\(entityName)", query: query)

        if !list.failures.isEmpty {
            // Loud on purpose: a dropped record is the difference between
            // "no check-in" and "your check-in did not parse".
            CusanaLog.decoding.error(
                "\(entityName): dropped \(list.failures.count) undecodable record(s): \(list.failures.joined(separator: "; "))"
            )
        }

        let matching = list.elements.filter(matches)

        if let filter {
            let result: FilterCapabilityLog.Result =
                list.elements.isEmpty ? .inconclusive
                : matching.count == list.elements.count ? .serverSideHonoured
                : .ignoredByServer
            await FilterCapabilityLog.shared.record(
                entity: entityName, parameter: filter.name, result: result
            )
        }

        return matching
    }

    // MARK: - Transport

    private func get<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await data(path: path, query: query)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let detail = "\(T.self) from \(path): \(error)"
            CusanaLog.decoding.error("\(detail)")
            throw CusanaError.decoding(detail)
        }
    }

    private func getLenientList<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        query: [URLQueryItem]
    ) async throws -> LenientList<T> {
        let data = try await data(path: path, query: query)
        do {
            return try decoder.decode(LenientList<T>.self, from: data)
        } catch {
            let detail = "[\(T.self)] from \(path): \(error)"
            CusanaLog.decoding.error("\(detail)")
            throw CusanaError.decoding(detail)
        }
    }

    private func data(path: String, query: [URLQueryItem]) async throws -> Data {
        try config.validateTokenFreshness()

        guard var components = URLComponents(
            url: config.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw CusanaError.invalidURL(path)
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw CusanaError.invalidURL(path) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        CusanaLog.network.debug("GET \(url.path)\(url.query.map { "?\($0)" } ?? "")")

        // Bound to a `let` so the escaping deadline closure captures an
        // immutable value rather than the mutable `request` var.
        let outgoing = request
        let session = session

        let (data, response) = try await withDeadline(deadline, operation: {
            do {
                return try await session.data(for: outgoing)
            } catch let error as URLError {
                throw CusanaError.from(urlError: error)
            } catch {
                throw CusanaError.transport(error.localizedDescription)
            }
        })

        guard let http = response as? HTTPURLResponse else {
            throw CusanaError.transport("Response was not HTTP.")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            CusanaLog.network.error(
                "\(http.statusCode) on \(url.path) — token \(CusanaLog.fingerprint(config.accessToken)) rejected"
            )
            throw CusanaError.unauthorised
        default:
            let body = String(data: data.prefix(512), encoding: .utf8)
            CusanaLog.network.error("\(http.statusCode) on \(url.path): \(body ?? "<no body>")")
            throw CusanaError.http(status: http.statusCode, body: body)
        }
    }
}

/// Races an operation against a wall-clock deadline.
///
/// URLSession's own timeouts cover a stalled *request*, but not a request that
/// technically keeps trickling bytes, and not our own retry/decode work. The
/// requirement from the brief is blunt: never leave a spinner running forever.
func withDeadline<T: Sendable>(
    _ duration: Duration,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw CusanaError.timedOut
        }
        // Whichever finishes first wins; the loser is cancelled on the way out.
        guard let result = try await group.next() else {
            throw CusanaError.timedOut
        }
        group.cancelAll()
        return result
    }
}
