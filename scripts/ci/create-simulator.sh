#!/usr/bin/env bash
set -euo pipefail

EXPECTED_IOS_RUNTIME_VERSION="26.5"
EXPECTED_DEVICE_TYPE="iPhone 17 Pro"

RUNTIMES_JSON="$(xcrun simctl list runtimes --json)"
DEVICE_TYPES_JSON="$(xcrun simctl list devicetypes --json)"

RUNTIME_ID="$(
  RUNTIMES_JSON="$RUNTIMES_JSON" \
  EXPECTED_IOS_RUNTIME_VERSION="$EXPECTED_IOS_RUNTIME_VERSION" \
  /usr/bin/python3 - <<'PY'
import json
import os

runtimes = json.loads(os.environ["RUNTIMES_JSON"])["runtimes"]
expected = os.environ["EXPECTED_IOS_RUNTIME_VERSION"]
runtime = next(
    (
        item for item in runtimes
        if item.get("platform") == "iOS"
        and item.get("isAvailable")
        and item.get("version") == expected
    ),
    None,
)
if runtime is None:
    raise SystemExit(f"Required iOS simulator runtime {expected} is unavailable")
print(runtime["identifier"])
PY
)"

DEVICE_TYPE_ID="$(
  DEVICE_TYPES_JSON="$DEVICE_TYPES_JSON" \
  EXPECTED_DEVICE_TYPE="$EXPECTED_DEVICE_TYPE" \
  /usr/bin/python3 - <<'PY'
import json
import os

device_types = json.loads(os.environ["DEVICE_TYPES_JSON"])["devicetypes"]
expected = os.environ["EXPECTED_DEVICE_TYPE"]
device = next((item for item in device_types if item.get("name") == expected), None)
if device is None:
    raise SystemExit(f"Required simulator device type {expected} is unavailable")
print(device["identifier"])
PY
)"

# Persistent-runner hygiene: per-run simulators from earlier cancelled or
# crashed jobs would otherwise accumulate forever on a self-hosted host.
# Select by name via JSON in EVERY state — `simctl list devices <term>`
# filters by device name/UDID, not state, so a "Shutdown" term matches
# nothing; cancelled jobs also leave sims Booted, which a state filter
# would miss anyway. The runner processes one job at a time, so any
# "Vaultify Quality" device visible here is an orphan.
while read -r orphan_udid; do
  [[ -n "$orphan_udid" ]] || continue
  xcrun simctl shutdown "$orphan_udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$orphan_udid" >/dev/null 2>&1 || true
done < <(
  xcrun simctl list devices --json | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
for devices in data.get("devices", {}).values():
    for device in devices:
        if device.get("name", "").startswith("Vaultify Quality"):
            print(device["udid"])
'
)

RUN_SUFFIX="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${RANDOM}"
SIMULATOR_NAME="Vaultify Quality $RUN_SUFFIX"
SIMULATOR_UDID="$(xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")"

# The device now exists — from here on, every failure path must leave a
# trail the workflow's delete step can follow, or clean up itself.
cleanup_on_failure() {
  xcrun simctl delete "$SIMULATOR_UDID" >/dev/null 2>&1 || true
}
trap cleanup_on_failure ERR

# Export BEFORE boot: a cancellation or boot failure in the window below
# would otherwise leave a Booted device the delete step cannot name.
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SIMULATOR_UDID=$SIMULATOR_UDID"
    echo "SIMULATOR_NAME=$SIMULATOR_NAME"
    echo "SIMULATOR_RUNTIME=$RUNTIME_ID"
  } >> "$GITHUB_ENV"
fi

xcrun simctl boot "$SIMULATOR_UDID"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

trap - ERR

printf '%s\n' "$SIMULATOR_UDID"
