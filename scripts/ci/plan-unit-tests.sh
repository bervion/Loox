#!/usr/bin/env bash
# Decides whether ci.yml needs the macOS unit suite for this event, and writes
# `unit=true|false` to $GITHUB_OUTPUT. macOS minutes are the expensive part of
# CI, so the suite is skipped only when it cannot learn anything new:
#   - a draft pull request (it runs once the PR is marked ready for review)
#   - a change that touches only paths the unit suite never compiles or reads
#   - a push to main that merges a pull request whose head had the same tree
#     and passed the suite
# Release commits always run: release-ios.yml requires this run's unit job.
# Anything unexpected (unknown event, API failure, truncated file list) runs.
#
# Env: EVENT_NAME, REPOSITORY, GH_TOKEN, PR_NUMBER, PR_DRAFT, HEAD_SHA,
#      BEFORE_SHA, HEAD_MESSAGE
set -euo pipefail

decide() {
  echo "Unit suite: $1 ($2)"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "unit=$1" >> "$GITHUB_OUTPUT"
  fi
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "Unit suite: **$1**, $2" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
}

# Reads changed paths on stdin. Exits 0 (printing the first relevant path)
# when at least one path can affect VaultifyTests, and 3 when none can; an
# empty list counts as relevant. VaultifyTests only compiles and reads the app,
# core, extension and test sources (the #filePath readers are
# AccessibilityDNAGuardTests, PrivacyClaimHonestyTests, IconCatalogTests and
# OnboardingSyncConsentTests), so documentation, design references, store
# metadata and release tooling cannot change its result. Update this list if a
# test starts reading one of these paths.
touches_unit_suite() {
  /usr/bin/env python3 -c '
import sys

IGNORED_PREFIXES = (
    "docs/", "App Store Screenshots/", "Design System/", "metadata/", "specs/",
    "fastlane/", "quality/maestro/", ".github/ISSUE_TEMPLATE/",
)
IGNORED_FILES = {
    "LICENSE", ".gitignore", "Gemfile", "Gemfile.lock",
    ".github/workflows/release-ios.yml", ".github/actionlint.yaml",
}

paths = [line.rstrip("\n") for line in sys.stdin if line.strip()]
if not paths:
    print("(no changed files listed)")
    sys.exit(0)
for path in paths:
    if not (path.endswith(".md") or path in IGNORED_FILES or path.startswith(IGNORED_PREFIXES)):
        print(path)
        sys.exit(0)
sys.exit(3)
'
}

check_paths() {
  local files="$1" first status=0
  first="$(printf '%s\n' "$files" | touches_unit_suite)" || status=$?
  case "$status" in
    0) decide true "changes $first" ;;
    3) decide false "only documentation, design or release-tooling paths changed" ;;
    *) decide true "path classifier failed (exit $status)" ;;
  esac
}

case "${EVENT_NAME:-}" in
  workflow_dispatch)
    decide true "manual run"
    ;;

  pull_request)
    if [[ "${PR_DRAFT:-false}" == "true" ]]; then
      decide false "draft pull request; it runs when marked ready for review"
    fi
    files="$(gh api --paginate "repos/$REPOSITORY/pulls/$PR_NUMBER/files" --jq '.[].filename')" ||
      decide true "could not list the pull request's files"
    check_paths "$files"
    ;;

  push)
    case "${HEAD_MESSAGE:-}" in
      "chore(release):"*|"chore(beta):"*)
        decide true "release commit; release-ios.yml requires this run"
        ;;
    esac

    # A merge is skipped only when main now holds exactly the tree the PR's
    # head had and the unit suite passed on that head. A PR merged red, or
    # whose base moved on, yields a tree nobody tested, so it falls through.
    merged="$(gh api "repos/$REPOSITORY/commits/$HEAD_SHA/pulls" \
      --jq "[.[] | select(.merged_at != null and .merge_commit_sha == \"$HEAD_SHA\") | \"\(.number) \(.head.sha)\"][0] // empty")" ||
      decide true "could not look up the pull request for $HEAD_SHA"
    if [[ -n "$merged" ]]; then
      merged_pr="${merged%% *}"
      pr_head="${merged##* }"
      head_tree="$(gh api "repos/$REPOSITORY/git/commits/$HEAD_SHA" --jq .tree.sha)" || head_tree=""
      pr_tree="$(gh api "repos/$REPOSITORY/git/commits/$pr_head" --jq .tree.sha)" || pr_tree=""
      passed="$(gh api "repos/$REPOSITORY/commits/$pr_head/check-runs?check_name=Unit%20tests" \
        --jq '[.check_runs[] | select(.conclusion == "success")] | length')" || passed=0
      if [[ -n "$head_tree" && "$head_tree" == "$pr_tree" && "$passed" != "0" ]]; then
        decide false "merge of pull request #$merged_pr: same tree as $pr_head, where the suite passed"
      fi
    fi

    if [[ -z "${BEFORE_SHA:-}" || "$BEFORE_SHA" =~ ^0+$ ]]; then
      decide true "no previous commit to compare against"
    fi
    # The compare API lists at most 300 files; a longer list may hide code.
    compare="$(gh api "repos/$REPOSITORY/compare/$BEFORE_SHA...$HEAD_SHA" \
      --jq 'if ((.files // []) | length) >= 300 then "TRUNCATED" else (.files // [])[].filename end')" ||
      decide true "could not compare $BEFORE_SHA...$HEAD_SHA"
    if [[ "$compare" == "TRUNCATED" ]]; then
      decide true "too many changed files to classify"
    fi
    check_paths "$compare"
    ;;

  *)
    decide true "unhandled event ${EVENT_NAME:-unknown}"
    ;;
esac
