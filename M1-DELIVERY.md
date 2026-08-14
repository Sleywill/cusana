# Milestone 1 — delivery record

Built 2026-08-14. $300 milestone: watch app scaffold, Base44 REST client, auth,
live `CheckIn`/`Order` rendering on the wrist.

---

## FOR SCOTT — the Upwork message

> Milestone 1 is done.
>
> The watch app is built and talking to your Base44 backend. It reads the
> diner's open check and shows the total on the wrist — the real number from
> your data, not a mockup.
>
> Video attached: [30s simulator recording]
>
> The Settle button is on screen but switched off — that's Milestone 2, and I
> didn't want to fake a "Paid!" that isn't real yet.
>
> One thing I need from you when you have a minute: a live check-in on the demo
> account with a couple of items on it, so I can film the real total instead of
> a test one.

*(Kept to a few lines on purpose — see CLAUDE.md §10.)*

---

## WHAT IS ACTUALLY LIVE

| Piece | Status |
|---|---|
| Standalone watchOS app, no iOS target, no WatchConnectivity | ✅ built |
| Base44 REST client, `Authorization: Bearer` on every request | ✅ built |
| Codable models — CheckIn, Order, Restaurant, Table, CustomerProfile, User | ✅ built |
| Token from gitignored `Secrets.xcconfig`, never a Swift literal | ✅ built |
| State A (not seated) | ✅ live |
| State B (seated, total, venue, table) | ✅ live |
| State E (failure + Retry) | ✅ live |
| States C / D (processing, paid) | 🔸 declared, unreachable — M2 |
| Settle call | ❌ M2, deliberately absent |
| QR / check-in on the wrist | ❌ descoped |
| TestFlight upload | ❌ M3, blocked on Apple enrolment |

**76 unit tests, all passing.** Watch app builds clean with zero warnings.

---

## WHAT I BUILT BEYOND THE SPEC, AND WHY

Three things that cost a few lines each and prevent the failure modes a live
demo actually finds:

1. **Token expiry is read from the JWT itself.** If the token dies, the watch
   says "Session expired" instead of spinning and then showing a bare 403. The
   current token has 90 days, so this should never fire — but demo mornings are
   exactly when it would.
2. **A malformed record doesn't blank the screen.** Lists decode
   record-by-record; one bad row belonging to another diner gets dropped and
   logged rather than taking down the person standing at the till.
3. **A deadline guard on top of URLSession's timeouts.** The brief's rule is
   "never leave a spinner running forever" — this enforces it even if a request
   trickles bytes without ever finishing.

---

## THE OPEN QUESTION I COULD NOT CLOSE WITHOUT LIVE DATA

**Which field links a `CheckIn` to the diner wearing the watch?**

In Cusana the *host* scans the QR at the till, so the check-in is plausibly
created by restaurant staff — which makes `created_by` an unreliable owner.
`customer_id` is the real link, but the captured contract does not say whether
it holds a `User.id` or a `CustomerProfile.id`.

Rather than guess, `CheckInSelector` accepts all four plausible links and
**reports which one matched**. One live check-in closes this for good:

```
make probe          # prints, per check-in, which link held
```

Until then the app is correct either way, and it will never show another
diner's bill — that case is explicitly tested.

**Why it stayed open:** the demo account's only check-in is `closed` and its
order is `paid`, so there is no open record to match against. This is the
blocker `M1-BUILD-SPEC.md` flagged in its last section.

---

## STILL OPEN FOR M2 / M3

- 🔴 **Can a diner token write `Table.status` → `available`?** Untested, needs a
  live check-in. If it 403s, settle becomes Scott's Base44 work, not ours
  (§5 — app-side only).
- 🔴 **The settle request itself** — not yet captured. Recipe in
  `API-CONTRACT.md` §6.
- 🟠 **Delivery to Scott's watch.** Free Apple account → no TestFlight. Someone
  must enrol ($99/yr). Not an M1 blocker; it is an M3 blocker, and enrolment
  takes 24–48h, so the conversation should start now.

---

## HOW TO RUN IT

```bash
cd CusanaWatch
make secrets        # creates Config/Secrets.xcconfig — paste the JWT into it
make test           # 76 tests, ~1s, no simulator needed
make curl           # plain-curl acceptance check against the live backend
make probe          # same path through the real Swift client
make run            # boot a watch simulator and install
```

`make run "Apple Watch Series 10 (46mm)"` for the larger screen.

---

## NOTES FOR WHOEVER PICKS THIS UP

- **Build output is deliberately outside the repo** (`~/Library/Developer/CusanaWatch`).
  This folder is in iCloud Drive, which stamps extended attributes on build
  products and breaks codesigning with *"resource fork, Finder information, or
  similar detritus not allowed"*.
- **Logic lives in `CusanaKit`, a Swift package**, so it tests on macOS in about
  a second with no watchOS simulator and no test host. Only SwiftUI is in the
  app target.
- **`project.yml` is the source of truth.** Edit build settings there, not in
  Xcode's inspector — `xcodegen generate` overwrites the project.
- **The token is a live credential.** `Config/Secrets.xcconfig` is gitignored
  and verified: `git check-ignore` confirms it, and no JWT-shaped string exists
  anywhere in tracked files.

---

## ONE SECURITY CAVEAT, STATED PLAINLY

A config-injected token ends up **in the built app's Info.plist in plaintext**.
Anyone holding the `.app` or `.ipa` can read it out in seconds. That is inherent
to the approach — it is not a bug in this build, and it was the right trade for
a demo (watchOS has no keyboard and cannot present an OAuth2 login).

It is fine for: the simulator, Aleksei's watch, and an internal TestFlight
build going to Scott.

It is **not** fine for: public TestFlight, the App Store, or any build handed to
someone outside the project. Before Cusana ships for real, login moves to a
small native iOS app that authenticates and hands the token to the watch over
WatchConnectivity — the architecture in `CLAUDE.md` §2, viable once an iOS app
actually exists.

Worth saying out loud to Scott before M3, not after.
