import Foundation
import Observation

/// The watch state machine from the brief.
///
/// A/B/E are live in Milestone 1. C and D exist but are unreachable — the
/// settle call does not exist yet, and the brief is explicit that a fake
/// success state must not be shown. They are declared here so Milestone 2 adds
/// a transition rather than a new concept.
public enum WatchState: Equatable, Sendable {
    /// Before the first fetch resolves.
    case loading
    /// **A** — no open check-in for this diner.
    case notSeated
    /// **B** — seated, with a bill to settle.
    case seated(CheckSnapshot)
    /// **C** — settle in flight. Milestone 2.
    case processing
    /// **D** — settled. Milestone 2.
    case paid(Amount)
    /// **E** — not in the client's spec; built anyway, because "network down"
    /// and "backend said no" are exactly what a live demo finds.
    case failed(CusanaError)

    public var snapshot: CheckSnapshot? {
        if case .seated(let snapshot) = self { return snapshot }
        return nil
    }
}

/// Drives the screen.
///
/// Isolated to the main actor: every property here is read during SwiftUI body
/// evaluation, and `@Observable` state mutated off the main actor is a data
/// race, not a warning to be silenced.
@MainActor
@Observable
public final class CheckViewModel {
    public private(set) var state: WatchState = .loading
    /// True only for a refresh behind an already-drawn screen, so a poll never
    /// replaces a visible total with a spinner.
    public private(set) var isRefreshing = false
    public private(set) var lastUpdated: Date?

    private let service: CusanaService
    /// Modest, per the brief — battery and API rate limits both matter, and the
    /// demo total does not change mid-flow. Nil disables polling entirely.
    private let pollInterval: Duration?
    private var pollTask: Task<Void, Never>?

    public init(service: CusanaService, pollInterval: Duration? = .seconds(30)) {
        self.service = service
        self.pollInterval = pollInterval
    }

    /// Convenience for the app entry point: builds the live stack from the
    /// bundle, or lands in State E if the token was never configured.
    public static func live(bundle: Bundle = .main) -> CheckViewModel {
        do {
            let config = try CusanaConfig.fromBundle(bundle)
            CusanaLog.state.info(
                "config ok — host \(config.host), token \(CusanaLog.fingerprint(config.accessToken)), expires \(config.tokenExpiry?.formatted(.iso8601) ?? "unknown")"
            )
            return CheckViewModel(service: CusanaService(api: LiveCusanaAPI(config: config)))
        } catch let error as CusanaError {
            CusanaLog.state.error("config failed: \(error.diagnosticDescription)")
            return CheckViewModel(service: CusanaService(api: FailingAPI(error: error)))
        } catch {
            return CheckViewModel(service: CusanaService(api: FailingAPI(error: .notConfigured("\(error)"))))
        }
    }

    /// First load. Shows the spinner.
    public func load() async {
        state = .loading
        await fetch()
    }

    /// Re-fetch behind the current screen. Used by the poll timer and by pull
    /// to refresh; leaves State B on screen while it runs.
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch()
    }

    /// Retry from State E. Back to the spinner, because there is nothing behind it.
    public func retry() async {
        await load()
    }

    private func fetch() async {
        do {
            if let snapshot = try await service.loadCurrentCheck() {
                state = .seated(snapshot)
            } else {
                state = .notSeated
            }
            lastUpdated = Date()
        } catch let error as CusanaError {
            CusanaLog.state.error("fetch failed: \(error.diagnosticDescription)")
            state = .failed(error)
        } catch is CancellationError {
            // The view went away mid-flight. Not a failure, and showing State E
            // for it would flash an error as the user lowers their wrist.
            CusanaLog.state.debug("fetch cancelled")
        } catch {
            CusanaLog.state.error("fetch failed, unmapped: \(error)")
            state = .failed(.transport(error.localizedDescription))
        }
    }

    // MARK: - Polling

    /// Starts the modest refresh timer. Called when the screen appears.
    public func startPolling() {
        guard let pollInterval, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled, let self else { return }
                // Nothing to poll for on a failed or configuration-broken
                // screen — that is what the Retry button is for.
                guard self.state != .loading, !self.isFailed else { continue }
                await self.refresh()
            }
        }
    }

    /// Stops the timer. Called when the screen goes away — a watch screen that
    /// keeps polling in the dark is a battery complaint waiting to happen.
    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }
}

/// An API that fails identically on every call.
///
/// Used when configuration itself failed, so the missing-token case travels
/// through the same State E path as a network failure instead of needing a
/// separate branch in the view.
struct FailingAPI: CusanaAPI {
    let error: CusanaError

    func currentUser() async throws -> CusanaUser { throw error }
    func customerProfile(forUser userID: String) async throws -> CustomerProfile? { throw error }
    func checkIns(limit: Int) async throws -> [CheckIn] { throw error }
    func orders(forCheckIn checkInID: String) async throws -> [Order] { throw error }
    func restaurant(id: String) async throws -> Restaurant? { throw error }
    func table(id: String) async throws -> Table? { throw error }
}
