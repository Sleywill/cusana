# Cusana Watch — Milestone 1 build spec (for Claude Code)

Goal: a standalone watchOS app that renders the diner's real live check-in and
balance from Base44. Ship today. $300 milestone.

Read `API-CONTRACT.md` in this folder first — it has the base URL, auth scheme
and every entity schema, all captured from the live app.

---

## SCOPE OF M1 (do not exceed)

✅ watchOS-only Xcode project, no iOS target, no WatchConnectivity
✅ `CusanaAPI` protocol + live URLSession implementation + mock implementation
✅ Codable models: CheckIn, Order, Restaurant, Table
✅ Bearer-token auth from a gitignored config
✅ State machine A/B/C/D/E — with A and B fully live
✅ Runs in the watchOS simulator against the real backend

❌ NOT in M1: the settle call (that's M2), QR/check-in, TestFlight upload

---

## PROJECT SETUP

- Xcode → watchOS → App. **Uncheck** any iOS companion.
- Deployment target watchOS 10.
- Bundle id: `xyz.sleywil.cusanawatch` (placeholder — must match whatever
  App Store Connect record we create for TestFlight later).
- Add `Secrets.xcconfig` to `.gitignore` **before the first commit.**

```
// Secrets.xcconfig  — GITIGNORED, never committed
CUSANA_TOKEN = <the 744-char JWT from localStorage.base44_access_token>
```

Read it via Info.plist substitution, not a hardcoded string literal in Swift.

---

## LAYER 1 — MODELS

Base44 sends snake_case. Use `.convertFromSnakeCase` on the decoder rather than
writing CodingKeys by hand.

Dates (`created_date`, `updated_date`, `checked_in_at`) are ISO8601 **with
fractional seconds** — `.iso8601` alone will fail. Use a custom
`DateDecodingStrategy` with `ISO8601DateFormatter` and
`.withInternetDateTime.union(.withFractionalSeconds)`.

Money fields (`subtotal`, `gratuity_amount`, `total_amount`) arrive as JSON
numbers. Decode as `Decimal`, not `Double` — this is a bill.

Nullable in real data, so all optional: `stripe_charge_id`, `stripe_preauth_id`,
`preauth_amount`, `preauth_status`, `allergy_group_id`, `position_x`, `position_y`.

`status` fields: decode as `String`, not an enum. We have only seen `closed`,
`paid`, `available` — an enum will crash on the first unseen value, and we
cannot enumerate them yet. Map to a Swift enum with an `.unknown(String)` case
if you want type safety.

---

## LAYER 2 — API CLIENT

```swift
protocol CusanaAPI {
    func activeCheckIn() async throws -> CheckIn?
    func order(forCheckIn id: String) async throws -> Order?
    func restaurant(id: String) async throws -> Restaurant
    func table(id: String) async throws -> Table
}
```

Two conformers: `LiveCusanaAPI` (URLSession) and `MockCusanaAPI` (canned
Patsy's / $80.24 — so previews and the whole UI work with no network).

Live implementation:
- base URL and app id from the contract doc
- every request: `Authorization: Bearer <token>`
- 401/403 → a distinct `CusanaError.unauthorised`, because that is the error
  most likely to appear and it needs its own message on screen
- request timeout 10s

**Filtering:** entity endpoints take `?limit=N`. Whether they support server-side
filters is untested — try `?checkin_id=<id>` first and if the response ignores
it, fetch and filter client-side. Log which one you ended up using; it matters
for M2.

"Active check-in" = the most recent CheckIn for this user whose `status` is not
`closed`. Sort by `checked_in_at` descending.

---

## LAYER 3 — STATE MACHINE

```swift
enum WatchState {
    case loading
    case notSeated                       // A
    case seated(Order, Restaurant)       // B
    case processing                      // C  (M2)
    case paid                            // D  (M2)
    case failed(String)                  // E
}
```

- **A** — "No active check-in." Small, calm, centred.
- **B** — restaurant name, then the total as the hero element, then a full-width
  high-contrast **Settle Check** button. In M1 the button is present but
  disabled with a "coming in v2" tooltip, or wired to a no-op. Do not fake a
  success state.
- **E** — plain message plus a Retry that re-runs the fetch. Never a spinner
  with no exit.

Copy on B must match Scott's words exactly:
> "you have a check for $80.24 at Patsy's"

Format money with a currency `FormatStyle`, USD, always two decimals.

Refresh: on `.task` and on `.onAppear`. No aggressive polling — battery and
rate limits both matter, and the demo total does not change mid-flow.

---

## LAYER 4 — LAYOUT

Test at **41mm and 45mm**. The total is the biggest thing on screen. The button
must be tappable without precision — full width, minimum 44pt tall. Assume it
gets pressed by someone at a restaurant table who is not looking carefully.

---

## DELIVERABLE FOR THE MILESTONE

1. Simulator screen recording: app launches → fetches → shows real restaurant
   name and real total from Scott's backend.
2. Short written note: what is live, what is stubbed, what M2 covers.
3. Repo pushed (Secrets.xcconfig excluded — verify with `git status` before the
   first commit).

---

## THE ONE THING THAT CAN BLOCK THIS TODAY

The demo account's check-in is `closed` and its order is `paid`, so State B has
no live data to render. Either:

**(a)** seed a fresh CheckIn + Order via the API — this also answers whether a
diner token can write these entities, which is the M2 blocker; or

**(b)** run the real flow in the browser: customer app on the phone showing the
QR, `/host` on the Mac scanning it, then add two menu items.

Do (a) first. If it 403s, we have learned the thing that decides M2 and we fall
back to (b).
