#!/usr/bin/env bash
#
# Boots a watch simulator, installs the app and launches it.
#
# Takes an optional device type so the layout can be checked at both sizes the
# brief calls for — 41mm and 45mm:
#
#   ./scripts/run-simulator.sh                       # 41mm (the tight one)
#   ./scripts/run-simulator.sh "Apple Watch Series 10 (46mm)"

set -euo pipefail

DEVICE_TYPE="${1:-Apple Watch Series 9 (41mm)}"
BUILD_ROOT="${HOME}/Library/Developer/CusanaWatch"
BUNDLE_ID="xyz.sleywil.cusanawatch"
SIM_NAME="Cusana Demo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

# The watchOS runtime is a separate multi-GB download from the Xcode install,
# and its absence is the most likely reason this script cannot run.
if ! xcrun simctl list runtimes | grep -qi watchos; then
  echo "✗ No watchOS simulator runtime installed."
  echo "  Install one with:  xcodebuild -downloadPlatform watchOS"
  exit 2
fi

RUNTIME_ID="$(xcrun simctl list runtimes --json \
  | python3 -c 'import json,sys; rs=[r for r in json.load(sys.stdin)["runtimes"] if "watchOS" in r["name"] and r.get("isAvailable")]; print(rs[-1]["identifier"] if rs else "")')"

DEVICE_TYPE_ID="$(xcrun simctl list devicetypes --json \
  | python3 -c "import json,sys; ds=[d for d in json.load(sys.stdin)['devicetypes'] if d['name']=='''${DEVICE_TYPE}''']; print(ds[0]['identifier'] if ds else '')")"

if [[ -z "$DEVICE_TYPE_ID" ]]; then
  echo "✗ Unknown device type: ${DEVICE_TYPE}"
  echo "  Available:"
  xcrun simctl list devicetypes | grep -i watch | sed 's/^/    /'
  exit 2
fi

# Reuse the same named device across runs so the app icon keeps its place on
# the home screen and screenshots stay comparable.
UDID="$(xcrun simctl list devices --json \
  | python3 -c "import json,sys; ds=json.load(sys.stdin)['devices']; print(next((d['udid'] for v in ds.values() for d in v if d['name']=='${SIM_NAME}'), ''))")"

if [[ -z "$UDID" ]]; then
  echo "→ Creating simulator '${SIM_NAME}' (${DEVICE_TYPE})"
  UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")"
fi

echo "→ Booting ${UDID}"
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

echo "→ Building"
xcodebuild -project CusanaWatch.xcodeproj -scheme CusanaWatch \
  -sdk watchsimulator -destination "id=${UDID}" \
  -derivedDataPath "${BUILD_ROOT}/dd" build -quiet

APP_PATH="$(find "${BUILD_ROOT}/dd/Build/Products" -name 'Cusana.app' -maxdepth 3 | head -1)"
if [[ -z "$APP_PATH" ]]; then
  echo "✗ Could not find Cusana.app under ${BUILD_ROOT}/dd/Build/Products"
  exit 1
fi

echo "→ Installing ${APP_PATH}"
xcrun simctl install "$UDID" "$APP_PATH"

echo "→ Launching"
xcrun simctl launch "$UDID" "$BUNDLE_ID" || true

open -a Simulator
echo "✓ Running on ${DEVICE_TYPE}"
echo "  Screenshot:  xcrun simctl io ${UDID} screenshot shot.png"
echo "  Record:      xcrun simctl io ${UDID} recordVideo demo.mp4"
