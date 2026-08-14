import Foundation
import CusanaKit

// Runs the watch app's real networking stack against the live Base44 backend,
// from the command line, on macOS.
//
// This is the Milestone 1 acceptance bar from the brief — prove the demo read
// path works end to end before trusting it on a wrist. Unlike a curl script it
// exercises the exact Swift the watch runs: same decoder, same date handling,
// same ownership rules, same error mapping. If this prints a total, the watch
// will render one.
//
//   export CUSANA_TOKEN='<jwt>'
//   swift run cusana-probe
//
// The token is read from the environment and never printed — only a
// fingerprint. Nothing here writes to the backend.

struct Probe {
    static func run() async -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let host = environment["CUSANA_API_HOST"] ?? "cusana-connect-core.base44.app"
        let appID = environment["CUSANA_APP_ID"] ?? "69fc9f3c47869d944ddbb02b"

        guard let token = environment["CUSANA_TOKEN"], !token.isEmpty else {
            print("""
            ✗ CUSANA_TOKEN is not set.

              export CUSANA_TOKEN='<the JWT from localStorage.base44_access_token>'
              swift run cusana-probe

            Or load it from the gitignored config:
              export CUSANA_TOKEN=$(grep '^CUSANA_TOKEN' ../Config/Secrets.xcconfig | cut -d= -f2- | xargs)
            """)
            return 2
        }

        let config: CusanaConfig
        do {
            config = try CusanaConfig(host: host, appID: appID, accessToken: token)
        } catch {
            print("✗ config: \((error as? CusanaError)?.diagnosticDescription ?? "\(error)")")
            return 2
        }

        section("CONFIG")
        print("  host       \(config.host)")
        print("  app id     \(config.appID)")
        print("  base URL   \(config.baseURL.absoluteString)")
        print("  token      \(CusanaLog.fingerprint(config.accessToken))")

        if let expiry = config.tokenExpiry {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
            let mark = expiry <= Date() ? "✗ EXPIRED" : days < 7 ? "⚠︎" : "✓"
            print("  expires    \(expiry.formatted(.iso8601)) — \(days) days left \(mark)")
        } else {
            print("  expires    unknown (token carries no readable exp claim)")
        }

        let api = LiveCusanaAPI(config: config)

        // ── Identity ────────────────────────────────────────────────────────
        section("AUTH — GET /auth/me")
        let user: CusanaUser
        do {
            user = try await api.currentUser()
            print("  ✓ \(user.id)  \(user.email ?? "no email")  role=\(user.role ?? "?")")
        } catch {
            fail("auth/me", error)
            print("\n  Everything else depends on this. Stop here.")
            return 1
        }

        // ── Profile ─────────────────────────────────────────────────────────
        section("PROFILE — GET /entities/CustomerProfile")
        var profileID: String?
        do {
            if let profile = try await api.customerProfile(forUser: user.id) {
                profileID = profile.id
                print("  ✓ \(profile.id)  visits=\(profile.visitCount ?? 0)  default tip=\(profile.defaultGratuity.map { "\($0)%" } ?? "—")")
            } else {
                print("  · no CustomerProfile for this user (not fatal)")
            }
        } catch {
            fail("CustomerProfile", error)
        }

        // ── Check-ins ───────────────────────────────────────────────────────
        section("CHECK-INS — GET /entities/CheckIn")
        let checkIns: [CheckIn]
        do {
            checkIns = try await api.checkIns(limit: 100)
            print("  ✓ \(checkIns.count) visible to this token")
            for checkIn in checkIns.prefix(10) {
                let started = checkIn.startedAt?.formatted(.iso8601) ?? "no timestamp"
                print("    · \(checkIn.id)  status=\(checkIn.status.rawValue)  customer_id=\(checkIn.customerId ?? "nil")  created_by=\(checkIn.createdBy ?? "nil")  \(started)")
            }
            if checkIns.count > 10 { print("    … \(checkIns.count - 10) more") }
        } catch {
            fail("CheckIn", error)
            return 1
        }

        // ── Ownership — the open question ───────────────────────────────────
        section("OWNERSHIP — which field links a check-in to this diner?")
        let identity = CheckInSelector.Identity(
            userID: user.id, email: user.email, customerProfileID: profileID
        )
        let open = checkIns.filter { !$0.status.isSettled }
        print("  \(open.count) open / \(checkIns.count) total")

        if open.isEmpty {
            print("""
              · Nothing open, so ownership stays unresolved. This is the blocker
                in M1-BUILD-SPEC §'THE ONE THING' — seed a live check-in, then
                re-run. The app will correctly show State A until then.
            """)
        }
        for checkIn in open {
            let link = CheckInSelector.ownershipLink(of: checkIn, for: identity)
            print("    · \(checkIn.id) → \(link?.rawValue ?? "✗ NO MATCH — none of the four links held")")
        }

        // ── The whole read path ─────────────────────────────────────────────
        section("DEMO PATH — what the watch will render")
        let service = CusanaService(api: api)
        do {
            if let snapshot = try await service.loadCurrentCheck() {
                print("  ✓ STATE B — seated")
                print("    restaurant   \(snapshot.restaurantName)")
                print("    table        \(snapshot.tableLabel ?? "—")")
                print("    subtotal     \(snapshot.order.subtotal?.formatted ?? "—")")
                print("    gratuity     \(snapshot.order.gratuityAmount?.formatted ?? "—")  (\(snapshot.order.gratuityRate.map { "\($0)%" } ?? "—"))")
                print("    TOTAL        \(snapshot.total.formatted)   ← the hero number")
                print("    matched via  \(snapshot.ownershipLink.rawValue)")
                print("\n    On the wrist: \"\(snapshot.spokenSummary)\"")
            } else {
                print("  · STATE A — no active check-in")
                print("    Correct if nothing is open. If a check-in IS open, the")
                print("    ownership section above says which link failed.")
            }
        } catch {
            fail("loadCurrentCheck", error)
            return 1
        }

        // ── What the server did with our filters ────────────────────────────
        section("SERVER-SIDE FILTERING (M1-BUILD-SPEC asks which we used)")
        let filters = await FilterCapabilityLog.shared.snapshot()
        if filters.isEmpty {
            print("  · no filtered requests were made")
        }
        for (key, result) in filters.sorted(by: { $0.key < $1.key }) {
            print("  · \(key) → \(result.rawValue)")
        }

        print("\n✓ Probe finished. No writes were made.\n")
        return 0
    }

    static func section(_ title: String) {
        print("\n── \(title) " + String(repeating: "─", count: max(0, 60 - title.count)))
    }

    static func fail(_ label: String, _ error: any Error) {
        let detail = (error as? CusanaError)?.diagnosticDescription ?? "\(error)"
        print("  ✗ \(label): \(detail)")
    }
}

exit(await Probe.run())
