#!/usr/bin/env bash
# Waits for the background boot that `SIMULATOR_BOOT_ASYNC=1
# create-simulator.sh` started, and fails with its log if the boot failed or
# did not finish within the limit (default 10 minutes).
#
# Env: SIMULATOR_BOOT_STATUS_FILE, SIMULATOR_BOOT_LOG_FILE (exported by
#      create-simulator.sh), optional SIMULATOR_BOOT_TIMEOUT_SECONDS
set -euo pipefail

: "${SIMULATOR_BOOT_STATUS_FILE:?create-simulator.sh did not start an async boot}"
TIMEOUT_SECONDS="${SIMULATOR_BOOT_TIMEOUT_SECONDS:-600}"

started=$SECONDS
while [[ ! -s "$SIMULATOR_BOOT_STATUS_FILE" ]]; do
  if (( SECONDS - started >= TIMEOUT_SECONDS )); then
    echo "Simulator did not finish booting within ${TIMEOUT_SECONDS}s:" >&2
    cat "${SIMULATOR_BOOT_LOG_FILE:-/dev/null}" >&2 || true
    exit 1
  fi
  sleep 2
done

status="$(cat "$SIMULATOR_BOOT_STATUS_FILE")"
if [[ "$status" != "0" ]]; then
  echo "Simulator boot failed (exit $status):" >&2
  cat "${SIMULATOR_BOOT_LOG_FILE:-/dev/null}" >&2 || true
  exit 1
fi
echo "Simulator ready after waiting $(( SECONDS - started ))s"
