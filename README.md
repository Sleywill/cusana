# Cusana Watch MVP — start here

Everything a fresh Claude Code session needs to build this. Read in this order.

| File | What it is |
|---|---|
| `README.md` | this — status, next actions |
| `CLAUDE.md` | project brief: scope, architecture, client, what's agreed and what isn't |
| `API-CONTRACT.md` | the Base44 wire format, captured from the live app. Base URL, auth, every entity schema |
| `M1-BUILD-SPEC.md` | exactly what to build for milestone 1 |
| `M1-DELIVERY.md` | **what was actually built**, what's live vs stubbed, the draft note to Scott |
| `CusanaWatch/` | the Xcode project. `cd CusanaWatch && make help` |

---

## THE JOB IN ONE PARAGRAPH

Client: Scott Allen (Upwork, NYC). Product: **Cusana** — pay-your-restaurant-bill-
from-your-phone. It is a **Base44 web app**, not a native app: diners use it in
mobile Safari, the restaurant runs `/host` on an iPad as the till. The job is a
**standalone Apple Watch app** that does exactly one thing — show the diner their
open check and settle it with one tap. There is no iPhone app anywhere, so the
watch talks to the Base44 REST API directly over HTTPS.

$900 fixed, 3 milestones. M1 ($300) is **funded and active**.

---

## STATUS (as of Aug 14 2026)

**Solved**
- Architecture: standalone watchOS app → Base44 REST. No WatchConnectivity.
- Auth: `Authorization: Bearer <jwt>`. Verified 200 with / 403 without.
- Token lifetime **90 days**, current expires 2026-11-12 → a config-injected
  token is safe for this demo. No login UI on the wrist.
- Every entity schema captured from live data (see `API-CONTRACT.md`).
- Read permissions: a plain diner token reads everything the watch needs.
- The money math: `subtotal 68.00` → `gratuity_rate 18` → `gratuity_amount 12.24`
  → **`total_amount 80.24`**. The watch displays `total_amount`.
- Scope locked with client: settle only. No QR, no check-in, no tip editing.

**Open**
- 🔴 Can a diner token WRITE `Table.status` → `available`? Decides whether M2 is
  Swift work or Scott's Base44 work. Untested.
- 🔴 The settle request itself — not yet captured. Needs a live check-in, then
  press Settle Check with the fetch interceptor running (recipe in
  `API-CONTRACT.md` §6).
- 🟠 Delivery to Scott's watch: Aleksei has a **free** Apple account → no
  TestFlight. Someone must enroll in the paid program ($99/yr). Not an M1
  blocker; is an M3 blocker. Raised with Scott.

---

## NEXT ACTIONS, IN ORDER

1. ~~**Build M1**~~ ✅ **done** — see `M1-DELIVERY.md`. Watch app builds clean,
   76 unit tests green, States A/B/E live against the real Base44 API.
2. **Paste the token** into `CusanaWatch/Config/Secrets.xcconfig` (gitignored),
   then `cd CusanaWatch && make curl && make probe` to confirm the live path.
3. **Ask Scott to seed a live check-in** with a couple of items — the demo
   account's only check-in is `closed`, so State B has no real data to render
   yet. This is the one thing blocking the video.
4. **Record 30s** of the simulator showing real data on the wrist.
5. **Request the $300** on Upwork.
6. Only then: capture the settle call, and start the Apple Developer enrolment
   conversation.

---

## HARD RULES

- **The token is a secret.** It goes in `Secrets.xcconfig`, which is gitignored
  before the first commit. Never in a Swift literal, never committed, never
  pasted into the Upwork thread. Run `git status` before the first commit.
- **App-side only.** If something needs a Base44 backend function, that is
  Scott's work, not this contract. Flag it, don't build it.
- **Do not fake a success state.** If the settle isn't wired yet, the button is
  disabled — not a fake "Paid!".
- **Plan first, code after Aleksei says go.** Nothing pushed without his word.
- Scott is non-technical and does not read long messages. A few short lines.
