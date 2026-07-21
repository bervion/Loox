#!/usr/bin/env bash
set -euo pipefail

MAESTRO_VERSION="2.4.0"
MAESTRO_SHA256="aea22ce67ab6718997ec990c58652ede0c2be8f10ac4799039ca3dce3390d634"
MAESTRO_URL="https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$MAESTRO_VERSION/maestro.zip"
TOOLS_ROOT="${RUNNER_TEMP:-/tmp}/vaultify-tools"
INSTALL_ROOT="$TOOLS_ROOT/maestro-$MAESTRO_VERSION"
MAESTRO_BINARY="$INSTALL_ROOT/bin/maestro"

if [[ ! -x "$MAESTRO_BINARY" ]]; then
  STAGING_ROOT="$(mktemp -d "${RUNNER_TEMP:-/tmp}/vaultify-maestro.XXXXXX")"
  curl --fail --location --retry 3 --output "$STAGING_ROOT/maestro.zip" "$MAESTRO_URL"
  printf '%s  %s\n' "$MAESTRO_SHA256" "$STAGING_ROOT/maestro.zip" | shasum -a 256 -c -
  unzip -q "$STAGING_ROOT/maestro.zip" -d "$STAGING_ROOT/unpacked"
  mkdir -p "$TOOLS_ROOT"
  mv "$STAGING_ROOT/unpacked/maestro" "$INSTALL_ROOT"
fi

ACTUAL_VERSION="$(
  MAESTRO_CLI_NO_ANALYTICS=1 \
  MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true \
  "$MAESTRO_BINARY" --version 2>/dev/null | tail -1
)"
if [[ "$ACTUAL_VERSION" != "$MAESTRO_VERSION" ]]; then
  echo "Expected Maestro $MAESTRO_VERSION, found $ACTUAL_VERSION" >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "MAESTRO_BIN=$MAESTRO_BINARY" >> "$GITHUB_ENV"
fi

printf '%s\n' "$MAESTRO_BINARY"

