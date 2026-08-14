# Cusana Base44 REST contract — captured from the live app

Captured 2026-08-14 by driving the real web app and intercepting `fetch`/XHR.
Everything here is observed, not documented — Base44 publishes no REST docs.

---

## 1. BASE URL + AUTH

```
BASE = https://cusana-connect-core.base44.app/api/apps/69fc9f3c47869d944ddbb02b
```

`69fc9f3c47869d944ddbb02b` is the Base44 app id (from `localStorage.base44_app_id`).

**Auth: `Authorization: Bearer <jwt>` on every request.**
Confirmed by experiment: identical requests return **200 with** the header and
**403 without** it. There is no cookie-based fallback — good news, a native
client works fine.

**Token lifetime: 90 days** (`iat`→`exp` = 2160 h). The current demo token
expires **2026-11-12**.

> This kills the earlier worry about a baked token dying mid-demo. A token
> minted now comfortably outlives the demo. Credential-login-on-launch is still
> the better long-term design, but for the MVP a config-injected token is safe
> and removes the whole watchOS login problem.
> ⚠️ Token goes in a **gitignored local config**. Never committed, never pasted.

---

## 2. ENTITY ENDPOINTS

Pattern: `GET {BASE}/entities/{Entity}?limit=N`
Also observed: `PUT {BASE}/entities/User/me`, `POST {BASE}/entities/CustomerProfile`

Access as a **normal logged-in diner** (this is the permissions answer):

| Entity | Read | Note |
|---|---|---|
| `CheckIn` | ✅ 200 | |
| `Order` | ✅ 200 | |
| `Table` | ✅ 200 | |
| `Restaurant` | ✅ 200 | |
| `MenuItem` | ✅ 200 | |
| `OrderItem` | ✅ 200 | the line items |
| `CustomerProfile` | ✅ 200 | |
| `AllergyGroup` | ✅ 200 | |
| `User` (list) | ❌ 403 | expected — use `/auth/me` |
| `/auth/me` | ✅ 200 | current user |

404 (do not exist): `LineItem`, `OrderLineItem`, `CheckInItem`, `PaymentCard`,
`PaymentMethod`, `Reward`, `MenuCategory`.

**Reads are fully open to a diner token. Writes on own records work** — the app
itself did `PUT /entities/User/me` and `POST /entities/CustomerProfile` as this
user during onboarding.

🔴 **Still unverified: can a diner token write `Table.status` → `available`?**
That is the last thing standing between us and milestone 2. Needs a live check-in.

---

## 3. SCHEMAS (observed field names + types)

### CheckIn
```
id, guest_name, customer_id, restaurant_id, table_id, allergy_group_id,
party_size (number), checked_in_at (ISO string), status (string),
stripe_preauth_id, preauth_amount, preauth_status,
created_date, updated_date, created_by_id, created_by, is_sample (bool)
```
Observed `status`: `"closed"`

### Order
```
id, checkin_id, restaurant_id, table_id,
subtotal (number), gratuity_rate (number, percent e.g. 18),
gratuity_amount (number), total_amount (number),
payment_card_used (string, e.g. "default"), stripe_charge_id,
status (string), created_date, updated_date, created_by_id, created_by, is_sample
```
Observed `status`: `"paid"`

### OrderItem
```
id, order_id, menu_item_id, item_name, quantity (number),
unit_price (number), notes, created_date, updated_date,
created_by_id, created_by, is_sample
```

### Table
```
id, restaurant_id, table_number (number), capacity (number),
status (string), position_x, position_y,
created_date, updated_date, created_by_id, created_by, is_sample
```
Observed `status`: `"available"`

### CustomerProfile
```
id, user_id, phone_number, visit_count, is_vip, marketing_opt_in,
default_gratuity (number), default_card_label, default_card_last4,
default_card_token, alt_card_label, alt_card_last4, alt_card_token, photo_url
```

---

## 4. THE MONEY MATH — CONFIRMED

Real record pulled from the live app, matching Scott's screenshots exactly:

```
subtotal        68.00
gratuity_rate   18        (%)
gratuity_amount 12.24     = 68.00 × 0.18
total_amount    80.24
```

**The watch displays `total_amount`, never `subtotal`.** That's the $80.24 Scott
quoted. `gratuity_rate` defaults from `CustomerProfile.default_gratuity`
(onboarding offers 15/16/17/18/19/20/22, default 18).

⚠️ Note `stripe_charge_id` is `null` on a settled order and `preauth_status` is
`null` on a closed check-in — consistent with Stripe test mode where nothing is
actually authorised.

---

## 5. WATCH READ SEQUENCE

To render State B the watch needs, in order:

1. `GET {BASE}/entities/CheckIn` → find the one for this user with an open status
2. `GET {BASE}/entities/Order?…` → the order whose `checkin_id` matches
3. `GET {BASE}/entities/Restaurant/{restaurant_id}` → name for "at Patsy's"
4. `GET {BASE}/entities/Table/{table_id}` → `table_number` if we show it

Render: **"you have a check for ${total_amount} at {restaurant.name}"**

`OrderItem` is not needed for the watch — the wrist shows a total, not a list.

---

## 6. SETTLE — WHAT WE STILL NEED

Not yet captured. Requires an active check-in with items, then pressing
**Settle Check (Default)** with the interceptor running.

Working hypothesis from the settled record: settle is a sequence of entity
writes, not one endpoint —
```
Order.status    → "paid"
CheckIn.status  → "closed"
Table.status    → "available"
```
If that's all it is, the Swift client can fire the same writes. If `Table` is
staff-restricted, we get a 403 and it becomes Scott's Base44 work.

**Capture procedure (interceptor must be installed BEFORE pressing settle):**
```js
window.__cap=[];const of=fetch;window.fetch=async(...a)=>{const r=await of(...a);
try{window.__cap.push({m:(a[1]?.method)||'GET',u:''+(a[0].url||a[0]),s:r.status,
b:a[1]?.body,res:await r.clone().text()})}catch(e){};return r};
```
Then after settling: `copy(JSON.stringify(window.__cap,null,2))`

---

## 7. STATUS

✅ base URL · ✅ auth scheme · ✅ token lifetime · ✅ all entity schemas ·
✅ read permissions · ✅ total/gratuity math · ✅ line-item entity
🔴 settle write payload · 🔴 diner write permission on `Table`

Enough to build the models, the API client protocol, and the whole UI against a
mock. Blocked only on the final settle call.
