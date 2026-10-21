#!/usr/bin/env bash
# Creates and boots a throwaway simulator for one test run, and prints its UDID.
#
# The runtime is resolved against the same policy file as the Xcode pin
# (toolchain-pin.sh) so the two can never drift apart, and every failure path
# prints the runtime inventory instead of a bare "unavailable".
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/toolchain-pin.sh
. "$SCRIPT_DIR/toolchain-pin.sh"

# The runtime must be one the selected Xcode can actually drive: a runtime
# whose major exceeds the toolchain's is installed but unusable.
XCODE_VERSION="$(xcodebuild -version | sed -n '1s/^Xcode //p')"
if [[ -z "$XCODE_VERSION" ]]; then
  echo "Unable to read the active Xcode version; run scripts/ci/select-xcode.sh first" >&2
  exit 1
fi
MAX_RUNTIME_MAJOR="$(version_major "$XCODE_VERSION")"

RUNTIME_ID="$(
  xcrun simctl list runtimes --json |
  EXPECTED_MINIMUM="$MINIMUM_IOS_RUNTIME_VERSION" \
  MAX_MAJOR="$MAX_RUNTIME_MAJOR" \
  XCODE_VERSION="$XCODE_VERSION" \
  /usr/bin/python3 -c '
import json, os, sys

minimum = tuple(int(part) for part in os.environ["EXPECTED_MINIMUM"].split("."))
max_major = int(os.environ["MAX_MAJOR"])
xcode = os.environ["XCODE_VERSION"]

def parsed(value):
    parts = []
    for part in value.split("."):
        try:
            parts.append(int(part))
        except ValueError:
            break
    return tuple(parts) or (0,)

runtimes = json.load(sys.stdin)["runtimes"]
ios = [item for item in runtimes if item.get("platform") == "iOS"]

eligible = []
rejected = []
for item in ios:
    version = parsed(item.get("version", "0"))
    if not item.get("isAvailable"):
        rejected.append((item, "not available"))
    elif version < minimum:
        rejected.append((item, "below minimum %s" % os.environ["EXPECTED_MINIMUM"]))
    elif version[0] > max_major:
        rejected.append((item, "newer than Xcode %s can drive" % xcode))
    else:
        eligible.append((version, item))

if not eligible:
    print("No installed iOS simulator runtime satisfies the policy "
          "(minimum %s, major <= %s for Xcode %s)."
          % (os.environ["EXPECTED_MINIMUM"], max_major, xcode), file=sys.stderr)
    print("iOS runtime inventory:", file=sys.stderr)
    if not ios:
        print("  (none installed)", file=sys.stderr)
    for item, reason in rejected:
        print("  %s\t%s\t%s" % (item.get("name"), item.get("version"), reason), file=sys.stderr)
    raise SystemExit(1)

# Lowest qualifying runtime, matching select-xcode.sh: a newly downloaded
# runtime must not silently move what the suites are recorded against.
eligible.sort(key=lambda pair: pair[0])
chosen = eligible[0][1]
print("Selected iOS runtime %s for Xcode %s" % (chosen.get("version"), xcode), file=sys.stderr)
print(chosen["identifier"])
'
)"

DEVICE_TYPE_ID="$(
  xcrun simctl list devicetypes --json |
  EXPECTED_DEVICE_TYPE="$SIMULATOR_DEVICE_TYPE" \
  /usr/bin/python3 -c '
import json, os, sys

device_types = json.load(sys.stdin)["devicetypes"]
expected = os.environ["EXPECTED_DEVICE_TYPE"]
device = next((item for item in device_types if item.get("name") == expected), None)
if device is None:
    print("Required simulator device type %s is unavailable." % expected, file=sys.stderr)
    print("Installed device types:", file=sys.stderr)
    for item in device_types:
        print("  %s" % item.get("name"), file=sys.stderr)
    raise SystemExit(1)
print(device["identifier"])
'
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

# SIMULATOR_BOOT_ASYNC=1 (CI) boots in the background and returns at once, so
# the first boot's data migration (several minutes on a fresh hosted runner)
# overlaps project generation, which mostly waits on the network. The boot
# must still finish before compilation starts: a device that settles while the
# suite compiles makes the test app's first launch take minutes on a 3-core
# runner. wait-for-simulator.sh blocks on the status file written here.
# Boot chatter goes to stderr so stdout stays exactly one line: the UDID a
# caller (Makefile, workflow step) substitutes straight into -destination.
if [[ "${SIMULATOR_BOOT_ASYNC:-0}" == "1" ]]; then
  BOOT_STATUS_FILE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vaultify-simulator-boot.status"
  BOOT_LOG_FILE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vaultify-simulator-boot.log"
  rm -f "$BOOT_STATUS_FILE"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      echo "SIMULATOR_BOOT_STATUS_FILE=$BOOT_STATUS_FILE"
      echo "SIMULATOR_BOOT_LOG_FILE=$BOOT_LOG_FILE"
    } >> "$GITHUB_ENV"
  fi
  nohup /bin/bash -c '
    status=0
    xcrun simctl boot "$1" && xcrun simctl bootstatus "$1" -b || status=$?
    echo "$status" > "$2"
  ' boot "$SIMULATOR_UDID" "$BOOT_STATUS_FILE" > "$BOOT_LOG_FILE" 2>&1 &
else
  xcrun simctl boot "$SIMULATOR_UDID" >&2
  xcrun simctl bootstatus "$SIMULATOR_UDID" -b >&2
fi

trap - ERR

printf '%s\n' "$SIMULATOR_UDID"
