#!/usr/bin/env bash
# Single source of truth for the toolchain floor. Sourced by select-xcode.sh
# and create-simulator.sh so the Xcode pin and the simulator-runtime pin cannot
# drift apart — the previous scripts each carried their own "26.5" string, and
# a patch bump on one machine was enough to make a tag fail before signing.
#
# Policy: a documented MINIMUM, not an exact match, plus a printed inventory on
# every failure. Three machines (maintainer, vaultify-ci, vaultify-release)
# update independently, so an exact pin means nobody can say whether a tag will
# build until it already failed.
#
# The runtime is additionally capped at the selected Xcode's major version:
# Xcode 26.x cannot drive an iOS 27 runtime, so "newest available" is not a
# safe rule. Bumping MINIMUM_XCODE_VERSION past a major therefore also unlocks
# the matching runtime major automatically.

# Oldest Xcode allowed to produce a Vaultify test run or release build.
MINIMUM_XCODE_VERSION="26.5"

# Oldest iOS simulator runtime allowed to host the test suites.
MINIMUM_IOS_RUNTIME_VERSION="26.0"

# Device type the suites are recorded and replayed on. Snapshot references are
# scale-pinned in code, so this only fixes screen geometry, not raster scale.
SIMULATOR_DEVICE_TYPE="iPhone 17 Pro"

# True when $1 (a dotted version) is >= $2.
version_at_least() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

# Major component of a dotted version.
version_major() {
  printf '%s\n' "${1%%.*}"
}
