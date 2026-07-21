#!/usr/bin/env bash
set -euo pipefail

EXPECTED_XCODE_VERSION="26.5"
CANDIDATES=(
  "/Applications/Xcode_26.5.app"
  "/Applications/Xcode_26.5.0.app"
  "/Applications/Xcode.app"
)

SELECTED_DEVELOPER_DIR=""
for candidate in "${CANDIDATES[@]}"; do
  developer_dir="$candidate/Contents/Developer"
  [[ -x "$developer_dir/usr/bin/xcodebuild" ]] || continue
  actual_version="$($developer_dir/usr/bin/xcodebuild -version | sed -n '1s/^Xcode //p')"
  if [[ "$actual_version" == "$EXPECTED_XCODE_VERSION" ]]; then
    SELECTED_DEVELOPER_DIR="$developer_dir"
    break
  fi
done

if [[ -z "$SELECTED_DEVELOPER_DIR" ]]; then
  echo "Xcode $EXPECTED_XCODE_VERSION is required but was not found" >&2
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "DEVELOPER_DIR=$SELECTED_DEVELOPER_DIR" >> "$GITHUB_ENV"
fi

DEVELOPER_DIR="$SELECTED_DEVELOPER_DIR" xcodebuild -version
printf '%s\n' "$SELECTED_DEVELOPER_DIR"
