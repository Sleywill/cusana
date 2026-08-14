#!/usr/bin/env bash
#
# Milestone 1 acceptance bar, per CLAUDE.md §8: prove the demo read path works
# with plain curl before trusting any Swift. If this cannot read a check, the
# watch cannot either — and that gets discovered on day one, not day four.
#
# Read-only. Nothing here writes to Scott's live product.
#
# Usage:
#   export CUSANA_TOKEN='<jwt>'   # or leave it in Config/Secrets.xcconfig
#   ./scripts/probe.sh
#
# The token is never printed — only a fingerprint.

set -uo pipefail

HOST="${CUSANA_API_HOST:-cusana-connect-core.base44.app}"
APP_ID="${CUSANA_APP_ID:-69fc9f3c47869d944ddbb02b}"
BASE="https://${HOST}/api/apps/${APP_ID}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS="${SCRIPT_DIR}/../Config/Secrets.xcconfig"

# Fall back to the gitignored xcconfig so there is one place to keep the token.
if [[ -z "${CUSANA_TOKEN:-}" && -f "$SECRETS" ]]; then
  CUSANA_TOKEN="$(grep -E '^[[:space:]]*CUSANA_TOKEN[[:space:]]*=' "$SECRETS" \
                  | head -1 | cut -d= -f2- | xargs)"
fi

if [[ -z "${CUSANA_TOKEN:-}" || "$CUSANA_TOKEN" == "PASTE_THE_JWT_HERE" ]]; then
  cat <<'EOF'
✗ No token.

  Either export it:
      export CUSANA_TOKEN='<the JWT from localStorage.base44_access_token>'

  or put it in Config/Secrets.xcconfig (gitignored):
      cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
EOF
  exit 2
fi

AUTH="Authorization: Bearer ${CUSANA_TOKEN}"
PASS=0; FAIL=0

fingerprint="${CUSANA_TOKEN:0:6}…${CUSANA_TOKEN: -4} (${#CUSANA_TOKEN} chars)"

echo "── CONFIG ──────────────────────────────────────────────────────"
echo "  base   $BASE"
echo "  token  $fingerprint"

# Decode the JWT's exp claim so an expired token is obvious immediately rather
# than showing up as a mystery 403 on demo morning.
payload="$(cut -d. -f2 <<<"$CUSANA_TOKEN" | tr '_-' '/+')"
case $(( ${#payload} % 4 )) in 2) payload="${payload}==";; 3) payload="${payload}=";; esac
exp="$(base64 -d <<<"$payload" 2>/dev/null | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')"
if [[ -n "$exp" ]]; then
  now=$(date +%s)
  days=$(( (exp - now) / 86400 ))
  when="$(date -r "$exp" '+%Y-%m-%d' 2>/dev/null || echo "$exp")"
  if (( exp <= now )); then
    echo "  expiry $when — ✗ EXPIRED. Everything below will 403."
  else
    echo "  expiry $when — $days days left"
  fi
fi

# GET an endpoint, print its status, keep the body in $BODY.
probe() {
  local label="$1" path="$2"
  local response status
  response="$(curl -sS -m 15 -w $'\n%{http_code}' -H "$AUTH" -H 'Accept: application/json' "${BASE}${path}" 2>&1)"
  status="$(tail -1 <<<"$response")"
  BODY="$(sed '$d' <<<"$response")"

  if [[ "$status" == 2* ]]; then
    printf '  ✓ %-42s %s\n' "$label" "$status"
    PASS=$((PASS + 1))
  else
    printf '  ✗ %-42s %s  %s\n' "$label" "$status" "$(head -c 120 <<<"$BODY")"
    FAIL=$((FAIL + 1))
  fi
}

echo
echo "── AUTH ────────────────────────────────────────────────────────"
probe "GET /auth/me" "/auth/me"
ME="$BODY"
if command -v python3 >/dev/null 2>&1 && [[ "$ME" == \{* ]]; then
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("    id=%s  email=%s  role=%s" % (d.get("id"), d.get("email"), d.get("role")))' <<<"$ME" 2>/dev/null
fi

echo
echo "── AUTH IS ACTUALLY REQUIRED (contract claim: 200 with, 403 without) ──"
no_auth="$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "${BASE}/entities/CheckIn?limit=1")"
if [[ "$no_auth" == "403" || "$no_auth" == "401" ]]; then
  echo "  ✓ without the header: $no_auth — no cookie fallback, as captured"
  PASS=$((PASS + 1))
else
  echo "  ⚠︎ without the header: $no_auth — expected 401/403. Re-check the contract."
fi

echo
echo "── ENTITY READS (the watch needs all of these) ─────────────────"
for entity in CheckIn Order Restaurant Table OrderItem CustomerProfile; do
  probe "GET /entities/$entity?limit=5" "/entities/${entity}?limit=5"
done

echo
echo "── OPEN CHECK-INS (is there anything to render?) ───────────────"
probe "GET /entities/CheckIn?limit=100" "/entities/CheckIn?limit=100"
if command -v python3 >/dev/null 2>&1 && [[ "$BODY" == \[* ]]; then
  python3 <<'PY' <<<"$BODY"
import json, sys
rows = json.load(sys.stdin)
open_rows = [r for r in rows if r.get("status") != "closed"]
print(f"    {len(rows)} check-in(s) visible, {len(open_rows)} not closed")
for r in open_rows[:5]:
    print(f"      · {r.get('id')}  status={r.get('status')}  customer_id={r.get('customer_id')}  created_by={r.get('created_by')}")
if not open_rows:
    print("    · Nothing open — the watch will correctly show State A.")
    print("      To demo State B, seed a live check-in (M1-BUILD-SPEC, last section).")
PY
fi

echo
echo "── SERVER-SIDE FILTERING (untested in the contract) ────────────"
# Whether ?checkin_id= is honoured decides how M2 addresses the settle call.
probe "GET /entities/Order?checkin_id=__nonexistent__" "/entities/Order?checkin_id=__nonexistent__"
if [[ "$BODY" == "[]" ]]; then
  echo "    → server-side filtering appears HONOURED (empty for a bogus id)"
else
  echo "    → filter appears IGNORED; the client filters locally (it already does)"
fi

echo
echo "────────────────────────────────────────────────────────────────"
echo "  $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "  ✓ The demo read path works over plain HTTP." \
                  || echo "  ✗ Fix the failures above before trusting the Swift client."
exit $(( FAIL > 0 ))
