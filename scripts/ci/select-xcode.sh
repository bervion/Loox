#!/usr/bin/env bash
# Runner preflight: resolve the Xcode this run will use, or fail with the full
# inventory of what is installed and why each entry was rejected.
#
# Prints ONLY the selected developer directory on stdout (callers use
# `| tail -n 1`); the inventory and the selection go to stderr so they land in
# the job log without polluting that contract.
#
# Written for the bash 3.2 that ships with macOS — no associative arrays.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/ci/toolchain-pin.sh
. "$SCRIPT_DIR/toolchain-pin.sh"

TAB="$(printf '\t')"

# Every install worth considering: the /Applications convention plus whatever
# `xcode-select` currently points at, which on a developer machine is often a
# path the glob misses.
CANDIDATE_APPS=""
for app in /Applications/Xcode*.app; do
  [[ -d "$app" ]] && CANDIDATE_APPS="$CANDIDATE_APPS$app"$'\n'
done
if active_dir="$(xcode-select -p 2>/dev/null)"; then
  active_app="${active_dir%/Contents/Developer}"
  [[ -d "$active_app" ]] && CANDIDATE_APPS="$CANDIDATE_APPS$active_app"$'\n'
fi
CANDIDATE_APPS="$(printf '%s' "$CANDIDATE_APPS" | sort -u)"

INVENTORY=""
QUALIFIED=""

while IFS= read -r app; do
  [[ -n "$app" ]] || continue

  developer_dir="$app/Contents/Developer"
  if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
    INVENTORY="$INVENTORY  $app$TAB-${TAB}no xcodebuild"$'\n'
    continue
  fi

  # A half-installed Xcode answers `-version` with an error, and the previous
  # script's pipeline swallowed it into an empty version string. Every command
  # that followed in the job would have failed the same way, so reject the
  # candidate and say why.
  if ! version_output="$("$developer_dir/usr/bin/xcodebuild" -version 2>&1)"; then
    reason="$(printf '%s' "$version_output" | head -n 1)"
    INVENTORY="$INVENTORY  $app$TAB-${TAB}unusable: ${reason:-xcodebuild failed}"$'\n'
    continue
  fi

  actual_version="$(printf '%s\n' "$version_output" | sed -n '1s/^Xcode //p')"
  if [[ -z "$actual_version" ]]; then
    INVENTORY="$INVENTORY  $app$TAB-${TAB}unusable: unrecognised xcodebuild -version output"$'\n'
    continue
  fi

  # `-version` still answers on an install whose license has never been
  # accepted; `-showsdks` is the cheapest command that does not. Without this
  # probe the preflight happily selects an Xcode that fails on its first real
  # invocation, which reads as an infrastructure outage rather than a setup step.
  if ! sdk_output="$("$developer_dir/usr/bin/xcodebuild" -showsdks 2>&1)"; then
    reason="$(printf '%s' "$sdk_output" | head -n 1)"
    INVENTORY="$INVENTORY  $app$TAB$actual_version${TAB}unusable: ${reason:-xcodebuild -showsdks failed}"$'\n'
    continue
  fi

  if version_at_least "$actual_version" "$MINIMUM_XCODE_VERSION"; then
    INVENTORY="$INVENTORY  $app$TAB$actual_version${TAB}eligible"$'\n'
    QUALIFIED="$QUALIFIED$actual_version$TAB$developer_dir"$'\n'
  else
    INVENTORY="$INVENTORY  $app$TAB$actual_version${TAB}below minimum $MINIMUM_XCODE_VERSION"$'\n'
  fi
done <<EOF
$CANDIDATE_APPS
EOF

print_inventory() {
  printf 'Xcode inventory on %s (minimum %s):\n' "$(hostname -s)" "$MINIMUM_XCODE_VERSION" >&2
  if [[ -z "$INVENTORY" ]]; then
    printf '  (no Xcode installs found)\n' >&2
  else
    printf '%s' "$INVENTORY" >&2
  fi
}

if [[ -z "$QUALIFIED" ]]; then
  printf 'No installed Xcode satisfies the minimum %s\n' "$MINIMUM_XCODE_VERSION" >&2
  print_inventory
  exit 1
fi

# Lowest qualifying version wins. The app's deployment floor is iOS 17.3 and
# the release runner is meant to stay on a stable Xcode, so drifting onto the
# newest install (a beta, typically) must never happen silently.
SELECTED="$(printf '%s' "$QUALIFIED" | sort -V | head -n 1)"
SELECTED_XCODE_VERSION="${SELECTED%%$TAB*}"
SELECTED_DEVELOPER_DIR="${SELECTED#*$TAB}"

print_inventory
printf 'Selected Xcode %s at %s\n' "$SELECTED_XCODE_VERSION" "$SELECTED_DEVELOPER_DIR" >&2

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "DEVELOPER_DIR=$SELECTED_DEVELOPER_DIR"
    echo "SELECTED_XCODE_VERSION=$SELECTED_XCODE_VERSION"
  } >> "$GITHUB_ENV"
fi

printf '%s\n' "$SELECTED_DEVELOPER_DIR"
