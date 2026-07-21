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

RUN_SUFFIX="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${RANDOM}"
SIMULATOR_NAME="Vaultify Quality $RUN_SUFFIX"
SIMULATOR_UDID="$(xcrun simctl create "$SIMULATOR_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")"

xcrun simctl boot "$SIMULATOR_UDID"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SIMULATOR_UDID=$SIMULATOR_UDID"
    echo "SIMULATOR_NAME=$SIMULATOR_NAME"
    echo "SIMULATOR_RUNTIME=$RUNTIME_ID"
  } >> "$GITHUB_ENV"
fi

printf '%s\n' "$SIMULATOR_UDID"
