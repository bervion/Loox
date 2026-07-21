#!/usr/bin/env bash
set -euo pipefail

EXPECTED_TUIST_VERSION="4.200.1"
ACTUAL_TUIST_VERSION="$(tuist version)"

if [[ "$ACTUAL_TUIST_VERSION" != "$EXPECTED_TUIST_VERSION" ]]; then
  echo "Expected Tuist $EXPECTED_TUIST_VERSION, found $ACTUAL_TUIST_VERSION" >&2
  exit 1
fi

# Tuist 4.200 does not recognize a linked Git worktree's `.git` file as a
# project root. An empty manifest directory is sufficient and is removed only
# when this script created it.
CREATED_TUIST_DIRECTORY=0
if [[ ! -d Tuist ]]; then
  mkdir Tuist
  CREATED_TUIST_DIRECTORY=1
fi

tuist generate --no-open

if [[ "$CREATED_TUIST_DIRECTORY" == "1" ]]; then
  rmdir Tuist
fi

