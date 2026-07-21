#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" != "3" ]]; then
  echo "usage: $0 <simulator-udid> <derived-data> <output-directory>" >&2
  exit 64
fi

SIMULATOR_UDID="$1"
DERIVED_DATA="$2"
OUTPUT_DIRECTORY="$3"
MAESTRO_BINARY="${MAESTRO_BIN:-$(scripts/ci/install-maestro.sh)}"
APP_PATH="$(find "$DERIVED_DATA" -type d -path '*/Products/Debug-iphonesimulator/Vaultify.app' -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "Vaultify simulator app was not found below $DERIVED_DATA" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIRECTORY"
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"

MAESTRO_CLI_NO_ANALYTICS=1 \
MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true \
"$MAESTRO_BINARY" test \
  --udid "$SIMULATOR_UDID" \
  --format JUNIT \
  --output "$OUTPUT_DIRECTORY/maestro.xml" \
  --debug-output "$OUTPUT_DIRECTORY/debug" \
  --test-output-dir "$OUTPUT_DIRECTORY/artifacts" \
  --flatten-debug-output \
  --no-ansi \
  quality/maestro/vault-edit-save-relock.yaml

