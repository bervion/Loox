#!/usr/bin/env bash
set -euo pipefail

EXPECTED_TUIST_VERSION="4.200.1"
ACTUAL_TUIST_VERSION="$(tuist version)"

if [[ "$ACTUAL_TUIST_VERSION" != "$EXPECTED_TUIST_VERSION" ]]; then
  echo "Expected Tuist $EXPECTED_TUIST_VERSION, found $ACTUAL_TUIST_VERSION" >&2
  exit 1
fi

# The app icon is an Icon Composer `.icon` bundle. Tuist (to keep it as a
# resource) and actool (to compile it) both resolve that type through Launch
# Services, and only Icon Composer.app, nested in Xcode, declares it. An Xcode
# installed or replaced from the command line can leave it unregistered, so
# register the selected Xcode's copy. Registering is idempotent.
ICON_COMPOSER="$(dirname "${DEVELOPER_DIR:-$(xcode-select -p)}")/Applications/Icon Composer.app"
if [[ -d "$ICON_COMPOSER" ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$ICON_COMPOSER" ||
    echo "Could not register $ICON_COMPOSER with Launch Services" >&2
fi

# Tuist 4.200 does not recognize a linked Git worktree's `.git` file as a
# project root. An empty manifest directory is sufficient and is removed only
# when this script created it.
CREATED_TUIST_DIRECTORY=0
if [[ ! -d Tuist ]]; then
  mkdir Tuist
  CREATED_TUIST_DIRECTORY=1
fi

GENERATE_LOG="$(mktemp)"
trap 'rm -f "$GENERATE_LOG"' EXIT
# NO_COLOR keeps warnings as plain inline lines even when the caller's shell
# exports CLICOLOR_FORCE, which would move them into an end-of-run box.
NO_COLOR=1 tuist generate --no-open 2>&1 | tee "$GENERATE_LOG"

if [[ "$CREATED_TUIST_DIRECTORY" == "1" ]]; then
  rmdir Tuist
fi

# Tuist drops a declared path it cannot resolve with nothing but a warning, and
# the build then fails far from the cause: a dropped `vaultify.icon` surfaces as
# actool's "no icon stack named vaultify". Fail here, where the path is named.
# The phrases are Tuist 4.200.1's own; re-check them when bumping the pin.
if grep -E "is a directory, try using:|No files found at: |folder reference paths need to point to directories| does not exist$" "$GENERATE_LOG" >&2; then
  echo "Tuist dropped a path declared in Project.swift (listed above). A missing path" >&2
  echo "needs fixing there; a dropped .icon means Launch Services does not know the" >&2
  echo "Icon Composer type on this machine (see the registration step in this script)." >&2
  exit 1
fi
