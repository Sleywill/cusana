# Cusana Watch — project analysis
_Aug 14 2026. Written for Aleksei, not for the client._

---

## 1. VERDICT UP FRONT

**Take it, finish it fast, and treat it as an audition.** The engineering is
genuinely small. The money is thin. The strategic value is the reason to care.

Two things must be closed in the next 48 hours or they will bite: the
`Table.status` write permission, and somebody's paid Apple Developer account.
Neither is a coding problem, which is exactly why they're easy to let slide.

---

## 2. COMMERCIAL

| | |
|---|---|
| Contract | $900 fixed, 3 milestones, M1 funded |
| Estimate | 4–5 working days |
| Effective rate | ~$180–225/day |
| Profile rate | $37/hr → a 5-day build "should" be ~$1,480 |

**So it's underpriced by roughly a third.** Worth being clear-eyed about that
rather than pretending otherwise.

Three things make it defensible anyway:

1. **The rebuild.** Scott said in writing: *"If everything goes well we'll need
   to code this whole thing again without Base 44."* A POS product — diner app,
   host app, payments, backend — is realistically a $15–40k engagement, and
   plausibly ongoing. This $900 is the interview for it, and interviews are
   normally unpaid.
2. **Portfolio gap.** There is no watchOS work anywhere in the current
   portfolio. This adds a category, and watch work is rare enough on Upwork to
   be a differentiator rather than another iOS entry.
3. **Review quality.** A US client, 5 stars, on a delivered demo. Worth more
   than the margin lost.

**Client quality signals are good.** He funded M1 immediately, said *"don't
worry about the money part, if we end up a little over it's ok"*, and has been
patient through an architecture pivot that changed the whole job. That is not a
client who fights invoices.

**Client risk is timeline, not payment.** He vanished for seven weeks once,
missed a call he scheduled himself, and set a reminder an hour late. Assume every
question you ask has a 1–5 day answer latency and front-load anything blocking.

---

## 3. TECHNICAL FEASIBILITY

The app is: one authenticated GET, decode JSON, render a number and a button,
one write on tap.

- `URLSession` on watchOS: fully supported, no caveats
- Standalone watch apps with no iOS companion: supported since watchOS 6
- No background execution needed — the restricted part of watchOS is irrelevant
  here, because the user opens the app deliberately
- Network reaches the internet via the paired iPhone at OS level, so no LTE
  watch and no venue wifi required

**Difficulty: low.** The unknowns are all in the backend's permission model, not
in Swift.

---

## 4. RISK REGISTER

Ordered by expected damage, not by likelihood.

### 🔴 R1 — Diner token cannot write `Table.status`
**Impact: kills milestone 2 as scoped. Probability: genuinely unknown.**
Service role is unavailable to external clients, so the watch acts as a normal
logged-in diner. If flipping a table back to `available` is staff-restricted,
we get a 403 and the fix is a Base44 backend function — explicitly out of
contract scope.
**Mitigation:** test today, before writing settle code. If it fails, tell Scott
immediately and frame it as *his* Base44 task, not a renegotiation.
**Fallback:** M2 delivers Order + CheckIn writes, Scott's function handles Table.

### 🟠 R2 — Nobody has a paid Apple Developer account
**Impact: the build cannot reach Scott's wrist. Probability: certain unless acted on.**
Free account = own devices only. TestFlight requires the $99/yr program, and
enrolment takes 24–48h+ to verify.
**Mitigation:** started today. Either party can enroll; starting matters more
than who.
**Note:** this does NOT block M1. Simulator or your own watch is a valid M1
deliverable.

### 🟠 R3 — Scott mutates the Base44 app underneath you
**Impact: silent breakage between build and demo. Probability: moderate and rising.**
This one nobody has raised. Scott edits his live product by prompting an AI. If
he asks it to "tidy up" or add a field, entity shapes can change without warning
and without a changelog. The watch app decodes those shapes.
**Mitigation:** decode defensively — optionals everywhere, `status` as String not
enum, and a decode test per entity that fails loudly rather than silently
producing a blank screen. Then ask Scott directly to freeze Base44 changes in
the days before the demo.

### 🟡 R4 — The demo fails for reasons outside your code
Base44 downtime, venue wifi, a flat watch. Reputational, not contractual.
**Mitigation:** the failure states already in scope, plus one full rehearsal with
Scott before the real thing. Offer that rehearsal — it costs an hour and it's
the difference between "his app broke" and "Aleksei's app broke" in his memory.

### 🟡 R5 — Token in git
Low probability, catastrophic if it happens: a live 90-day credential to a
client's production system, in history, forever.
**Mitigation:** `.gitignore` before first commit, `git status` check. Already
handled — keep it handled.

### 🟢 R6 — Apple review
Not applicable. This never goes to the App Store. For a future real product:
Stripe is the *required* path for restaurant bills (physical goods and
real-world services must not use IAP), so payments are fine. The real future
constraints are that a watch-only app can't be logged into by a reviewer, and
that a single-screen app risks a minimum-functionality rejection. Both are
arguments for the iOS companion app in the rebuild — worth raising then, not now.

---

## 5. WHAT'S ALREADY DE-RISKED

Worth noting how much has moved from unknown to known in two weeks:

- Architecture pivoted cleanly when the iPhone app turned out not to exist
- Auth solved and verified — 90-day token, bearer header, 200/403 proven
- Every entity schema captured from live data, not from documentation
- Read permissions confirmed open to a diner token
- The gratuity math confirmed against a real settled record
- Scope locked in writing: settle only, no QR, no tip editing
- The client's exact wording for the watch screen, in his own message

That is a lot of certainty for a project that was "the AI says it'll be easy"
ten days ago.

---

## 6. THE HONEST WEAKNESS

The estimate assumes the settle is a handful of entity writes. **It hasn't been
observed yet.** If settle turns out to invoke a Base44 backend function with
server-side Stripe logic that a diner token can't call, milestone 2 is not a
Swift task at all, and the 4–5 day estimate is wrong.

That single unknown carries more schedule risk than everything else combined,
and it costs one browser session to eliminate. It should be the next thing done
after M1 ships — arguably before.

---

## 7. RECOMMENDED SEQUENCE

1. **Today** — build M1, record it, request the $300. Momentum and cash.
2. **Today** — one message to Scott on the Apple Developer account. Start the clock.
3. **Next** — test the `Table.status` write. This is the schedule-defining unknown.
4. **Then** — capture the settle trace, build M2 against what you observed.
5. **Before the demo** — ask Scott to freeze Base44 edits, and do one rehearsal.
6. **After it lands** — raise the rebuild while the demo is fresh and he's happy.
   That conversation is the actual prize, and the right moment is the week of the
   demo, not a month later.
