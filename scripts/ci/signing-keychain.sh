#!/usr/bin/env bash
# Job-scoped keychain for the release signing lane.
#
#   signing-keychain.sh create   before the lane
#   signing-keychain.sh delete   after it, under `if: always()`
#
# A self-hosted runner shares one macOS user with the other runners and with every
# app on the machine, and the default keychain and search list belong to that user.
# fastlane's `setup_ci` points the default at a fixed-name keychain that locks on
# sleep, and never puts it back: apps then save credentials into it and stall on a
# SecurityAgent prompt once it locks. So this keychain:
#
# - never becomes the default. It joins the end of the search list, which is all
#   codesign and xcodebuild need to find the identity.
# - lives in the runner's own temp directory, so no two jobs share one and neither
#   can delete the other's.
#
# Written for the bash 3.2 that ships with macOS.
set -euo pipefail

# Editing the search list is read-modify-write on a per-user file, so concurrent
# jobs take turns. The kernel releases the lock if a holder is killed.
if [[ -z "${SIGNING_KEYCHAIN_LOCKED:-}" ]]; then
  SIGNING_KEYCHAIN_LOCKED=1 exec lockf -k -t 120 "$HOME/Library/Caches/signing-keychain.lock" "$0" "$@"
fi

keychain="$RUNNER_TEMP/signing.keychain-db"

case "${1:-}" in
  create)
    # Random, so once locked, a copy left behind by a hard-killed job stays closed.
    password="$(openssl rand -hex 32)"
    echo "::add-mask::$password"

    security create-keychain -p "$password" "$keychain"
    # Locks once idle past the default 6-hour job limit. No lock-on-sleep: that
    # would fail signing if the machine sleeps mid-build.
    security set-keychain-settings -u -t 21600 "$keychain"

    # A hard-killed job on this runner leaves its entry behind, and `delete-keychain`
    # removes only one entry per call, so never list the same path twice.
    search_list="$(security list-keychains -d user)"
    if [[ "$search_list" != *"\"$keychain\""* ]]; then
      printf '%s\n' "$search_list" | xargs -J % security list-keychains -d user -s % "$keychain"
    fi

    {
      echo "MATCH_KEYCHAIN_NAME=$keychain"
      echo "MATCH_KEYCHAIN_PASSWORD=$password"
    } >> "$GITHUB_ENV"
    ;;
  delete)
    if [[ -e "$keychain" ]]; then
      security delete-keychain "$keychain"
    fi
    echo "Default keychain and search list after cleanup:"
    security default-keychain -d user
    security list-keychains -d user
    ;;
  *)
    echo "usage: $0 create|delete" >&2
    exit 2
    ;;
esac
