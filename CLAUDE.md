# Cusana Watch MVP — Claude Code project brief

Handoff file for Claude Code. Everything below is either agreed with the client in writing or
explicitly marked as an open question. **Do not invent scope.** If something isn't here, ask
Aleksei before building it.

> **Revision note (Aug 9):** the architecture changed. The original plan was
> Watch → WatchConnectivity → iPhone → backend. **There is no iPhone app.** Cusana is a Base44
> web app. The Watch now talks to the Base44 REST API directly. Any WatchConnectivity code or
> plan predating this note is obsolete.

---

## 1. WHAT THIS IS

Client: Scott Allen (Upwork, NYC). Product: **Cusana** — a restaurant check-in / order /
settle-the-bill product built entirely on **Base44** (AI web-app builder). It is a
**responsive web app**. No native iOS app exists and none is being built here.

The job: a **standalone Apple Watch app** so a diner can settle their bill with one tap on the
wrist.

**This is an MVP for a live demo to an evaluator.** Not going to the App Store, not handling real
money. Scott's words: "keep it as simple as possible."

Contract: $900 fixed, 3 milestones, Upwork. ~4–5 working days.

### The demo script (the ONLY path that must work flawlessly)

1. Diner is checked in — done outside the Watch for this MVP. Watch-based check-in is a possible
   *next* project.
2. Scott manually enters a couple of items onto the order.
3. Evaluator is told "time to check out" → taps one button on the Watch → paid.

Anything outside that path can be a stub. Scott handles "but what if…" questions verbally during
the demo.

---

## 2. ARCHITECTURE

Standalone watchOS app. No phone in the loop at the app layer.

```
watchOS app  --(URLSession + bearer token)-->  Base44 REST API
             <--(CheckIn / Order / Table JSON)--
             --(POST settle)-->
             <--(success / failure)--
```

- **watchOS app only.** SwiftUI + WatchKit. No iOS target, no companion app, no WCSession.
- **Networking:** plain `URLSession` against the Base44 public REST API, OAuth2 / bearer token
  auth — the same auth the web app uses.
- **Reads:** `GET` current `CheckIn` and `Order` state (and `Table`).
- **Write:** settle the check — either a direct REST update of order status, or by invoking the
  existing `settleCheck` backend logic. **Which of these is actually possible is an open
  question — see §8.**

### Network reachability
watchOS routes network requests through the paired iPhone at the OS level, with no companion app
required. So the Watch has connectivity over Bluetooth/WiFi via any paired phone — an LTE watch
and venue WiFi are both nice-to-have, not required. This materially de-risks the live demo.

### Getting the app onto Scott's watch — CRITICAL PATH

**Confirmed (Aug 14):** Aleksei owns an Apple Watch → real-hardware testing and
demo videos are possible immediately, no simulator needed.

**🔴 BLOCKER: Aleksei has a FREE Apple account.** A free account builds to your
own devices only (7-day provisioning profiles). **TestFlight and App Store
Connect require the paid Apple Developer Program, $99/yr.** So today there is
*no route* from Tbilisi to Scott's watch in New York.

Two options, raised with Scott Aug 14:

1. **Scott enrolls** ($99/yr) and adds Aleksei to his team. Preferred: the app
   ends up under client-owned accounts, and he needs one anyway if Cusana goes
   past the demo. Slower — he is non-technical.
2. **Aleksei enrolls** and adds Scott's Apple ID as an **internal** App Store
   Connect tester. Internal builds skip Beta App Review and land in minutes.
   Faster and fully controllable. Costs $99 against a $900 contract; reusable
   asset for future iOS work. Downside: app lives under Aleksei's account.

⏱ Apple enrollment takes 24–48h to verify, sometimes longer. **Which option
matters less than starting one today.**

Note: the watch must be paired to an iPhone for initial setup — Apple platform
requirement, unrelated to our app.

### Auth — SOLVED (Aug 14, verified against the live API)

watchOS has no usable keyboard and cannot present an OAuth2 login page, so
interactive sign-in on the wrist is not an option.

**Resolution: config-injected bearer token. The earlier worry was wrong.**
The live token's lifetime is **90 days** (`iat`→`exp` = 2160h; current one
expires 2026-11-12). It comfortably outlives the demo, so the "token dies on
demo morning" failure mode does not apply here.

- `Authorization: Bearer <jwt>` on every request. **Verified:** identical
  requests return 200 with the header, 403 without. No cookie fallback.
- Token lives in a **gitignored** `Secrets.xcconfig`. Never committed, never
  pasted into chat, never in the Upwork thread.
- Credential-login-on-launch remains the better design for a real product, but
  it is unnecessary complexity for a demo with a 90-day token.

**For the real product later:** a small native iOS app handles login and hands
the token to the Watch over WatchConnectivity — the architecture we originally
planned, once an iOS app actually exists.

See `API-CONTRACT.md` in this folder for the full captured wire format.

### Why no Apple Pay
Payments are **simulated in Stripe test mode**. No PassKit, no
`PKPaymentAuthorizationController`, **no Apple Merchant Identifier needed**. Confirmed by the
client. (The Upwork offer description still says otherwise — it's the stale May job post. Scott
has agreed to update it.)

---

## 3. WATCH STATE MACHINE

| State | Screen |
|---|---|
| **A — Not seated** | "No active check-in." |
| **B — Seated** | Table label + current balance + a big high-contrast `Pay $[total]` button |
| **C — Processing** | Spinner / activity ring |
| **D — Paid** | Checkmark + "Paid!", auto-returns to A after a beat |
| **E — Failed** | ⚠️ **Not in the client's spec. Build it anyway.** See §4. |

Data the Watch needs from the API:

- `checkInId` — which session to settle
- `totalAmount` — current balance
- `tableLabel` — confirms to the diner where they're sitting

Since there's no `updateApplicationContext` push any more, State B refreshes by polling on
appear + a modest timer while the screen is active. Don't poll aggressively — watch battery and
API rate limits both matter.

---

## 4. THE THREE THINGS THE CLIENT'S SPEC MISSES

Raised with Scott in writing. His answer on #1 was that it can't happen in this demo.

**1. Stale total on the wrist — DESCOPED BY CLIENT.**
Scott confirmed nothing gets added to the check mid-demo, so **don't build a re-pull flow**. Cheap
insurance that stays: re-fetch the order immediately before settling and send `expectedTotal` with
the settle request. Log a mismatch, don't block on it. A few lines.

**2. Failure state — BUILD IT.**
The spec has A/B/C/D and no path for "network down" or "backend said no". That is exactly the
state a live demo finds. Required:
- request timeout, plus our own deadline guard
- State E with a plain message and a way back to State B
- never leave a spinner running forever

**3. Idempotency — BUILD IT.**
Generate a UUID per checkout attempt and send it with the settle request. If the response is lost
in flight the Watch has no idea whether it settled — the diner taps again and the table gets
charged twice. Harmless in test mode, but Scott is rebuilding this for real later, so the seam
belongs in now. **Note:** whether the Base44 side can honour an idempotency key is unconfirmed —
if not, do the dedupe client-side (remember the last attempt id + its outcome) and flag the gap.

---

## 5. SCOPE

**In:**
- Standalone watchOS app (SwiftUI + WatchKit)
- Base44 REST client: auth, `CheckIn` / `Order` / `Table` models, settle call
- ⚠️ **QR code on the Watch — SCOPE CONFLICT, resolve before building.** The Aug 5 quote put
  QR-on-the-wrist in Part 1, but Scott's Aug 7 demo script says watch check-in is "hopefully our
  next project." Those disagree. If check-in is out, Part 1 is smaller than quoted — say so
  rather than quietly keeping the money. If it's in, note that a QR on a 41mm screen needs a
  **short payload**; a long token renders as dense mush no camera will read at watch brightness.
  Asked.
- The 4+1 state machine above
- Failure states, timeouts, idempotency key
- Short handoff doc at the end

**Out — do not build, do not scope-creep into:**
- Any native iOS app
- Apple Pay / PassKit / merchant identifier
- Base44 backend function authoring — Aleksei is **app-side only**, by agreement. If
  `settleCheck` needs exposing as an endpoint, that's Scott's Base44 work, not this contract.
- BLE beacon check-in (Scott's *next* project — see §7)
- Editing the check, price adjustment, bill splitting, gratuity UI
- App Store submission
- Anything not watchOS

---

## 6. MILESTONES

| # | $ | Real content |
|---|---|---|
| 1 | 300 | Watch app scaffold, Base44 REST client, auth working, live `CheckIn`/`Order` state rendering on the wrist + QR |
| 2 | 400 | Settle flow: tap → API call → result, full state machine |
| 3 | 200 | Failure paths, idempotency, demo hardening, handoff doc |

Milestone 2 is still titled "Apple Pay integration" in the Upwork offer — rename requested, Scott
agreed. Only M1 is funded at time of writing. **Confirm each milestone is funded in escrow before
starting that milestone's work.**

---

## 7. FUTURE WORK (mentioned by client, not contracted)

- **Watch-based check-in** — BLE beacon, or a QR/code shown on the watch. Scott: "hopefully our
  next project."
  - Already flagged to Scott: **beacon monitoring and ranging APIs don't exist on watchOS.**
    Detection has to run on an iPhone (region monitoring wakes the app even from terminated) and
    relay to the Watch — which means a native iOS app becomes a prerequisite. Also needs Always
    location permission, with App Store review implications.
- **Full rebuild off Base44** — Scott has said the whole product gets coded properly if the demo
  lands. That's the real prize; this MVP is the audition.

---

## 8. OPEN QUESTIONS — RESOLVE BEFORE WRITING CODE

**🔴 BLOCKER — entity access rules, NOT endpoint existence.**
The earlier framing ("is `settleCheck` reachable over HTTP?") was aimed at the wrong risk. If
settle logic is frontend-only, it is just a sequence of entity writes — `Order` → paid,
`CheckIn` → closed, `Table` → available — and the Swift client can fire those same writes itself.

What actually kills the contract is **permissions**. Service role bypasses entity access rules;
a logged-in diner user does not. If flipping a `Table` to `available` is restricted to
staff/admin roles, the Watch gets a 403 no matter how correct the Swift is — and the fix is a
Base44 backend function, which is explicitly **out of scope** for this contract (§5). That would
gate milestone 2 on Scott's Base44 work.

**Check this first, before writing any Swift.** In Base44 → Data/Entities, open the access rules
and field-level security on `CheckIn`, `Order` and `Table`. Highest-value five minutes in the
project.

**Then: capture a network trace, don't interview the AI.**
Open the app preview logged in as the demo user, Chrome DevTools → Network, and perform a full
check-in → add items → settle. Export the HAR. That single trace yields the base URL, auth header
format, token shape, every request/response body, and the exact call sequence the settle flow
fires. None of that is in the public docs — the JS SDK is the only documented client and we're
writing Swift, so the wire format has to come from observation.
⚠️ **The HAR contains a live auth token.** Never paste it into a chat, never commit it.
⚠️ Running a real settle creates records in Scott's live product — tell him first.

Then read `SettleCheckModal` in the code view to confirm what the trace showed.

**Milestone 1 acceptance bar:** a shell script of `curl` calls that performs the whole demo path
end to end as the demo user. **No Swift until that works.** If curl can't settle a check, nothing
in Swift will either — and that gets discovered on day one instead of day four.

**Ask the AI only what the trace can't answer:**
- Is email/password login enabled on this app, or Google SSO only?
- Access token lifetime and refresh flow.
- Can a demo account be seeded with a check-in plus a couple of order items?
- `Order` / `CheckIn` / `Table` JSON schemas — Scott offered these, accept them.

*(Stripe test mode is already confirmed by Scott — don't re-ask.)*

**Access:** Scott is inviting Aleksei to the Base44 project by email. Sequence agreed: Scott
updates the offer description → Aleksei accepts → email shared inside the live contract → invite
sent. (Upwork prohibits sharing contact details pre-contract.)

---

## 9. WORKING RULES (Aleksei's, apply to this project)

- **Plan first, code after explicit go.** Nothing committed or pushed without Aleksei's word.
- **App-side only.** Backend needs get flagged as explicit handoffs, never reached across into.
- **Don't overclaim.** If something only reproduces on Scott's device, say so rather than
  promising a fix.
- Every milestone ends with something Scott can run himself on his own devices — not a status
  update.
- No secrets in commits, chat, or docs. **The demo access token is a secret** — it goes in a local
  config that is gitignored, never in a committed file and never pasted into the Upwork thread.

---

## 10. CLIENT COMMUNICATION NOTES

- Scott is **non-technical** and relays Base44's AI output verbatim. Those specs are reasonable
  but incomplete and occasionally over-confident (it asserted Xcode access was unnecessary while
  describing a job that needs an entire Xcode project built from scratch). Treat them as a
  starting point, not gospel.
- **He does not read long messages.** The first proposal was ~700 words; his reply was "a lot to
  take in!!!" followed by seven weeks of silence. Keep updates to a few short lines.
- He is call-oriented and forgets scheduled calls. Written updates in the Upwork thread work
  better and leave a record.
- Tone: warm, informal, patient. Never make him feel dumb about Base44.
