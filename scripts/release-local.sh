#!/usr/bin/env bash
#
# Sign and upload a TestFlight build from THIS Mac.
#
# The normal path is `make release`, which tags and lets GitHub Actions build on
# the self-hosted runner. This script exists for when that runner cannot do the
# job — it ran out of disk once and blocked a shipped-bug fix for a day — and it
# deliberately mirrors `.github/workflows/release-ios.yml` step for step so the
# artifact is the same one CI would have produced.
#
# It is NOT a shortcut around the release gates. The workflow refuses to sign
# without a green test run for the exact commit; so does this, using a local run
# (--skip-tests exists, and says so out loud).
#
# Usage:
#   scripts/release-local.sh              # verify, build, upload
#   scripts/release-local.sh --dry-run    # everything except the upload
#   scripts/release-local.sh --skip-tests # only when CI is already green for this commit
#
# Secrets: put them in `fastlane/.env.release` (gitignored) or export them.
#   MATCH_PASSWORD
#   MATCH_GIT_BASIC_AUTHORIZATION
#   APP_STORE_CONNECT_API_KEY_KEY_ID
#   APP_STORE_CONNECT_API_KEY_ISSUER_ID
#   APP_STORE_CONNECT_API_KEY_KEY        # the .p8 contents, newlines included
#   TUIST_LOOX_LINK_PROD_TOKEN           # baked into Info.plist as LooxLinkAppToken
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; NC=$'\033[0m'
log()     { echo "${YELLOW}[·]${NC} $1"; }
success() { echo "${GREEN}[✓]${NC} $1"; }
error()   { echo "${RED}[✗]${NC} $1" >&2; exit 1; }

DRY_RUN=0
SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    *) error "Unknown argument: $arg" ;;
  esac
done

# `setup_ci` builds a throwaway keychain — right on a shared runner, wrong on a
# developer Mac that already holds the signing identity. Unset before any lane runs.
unset CI

# ── Secrets ──
ENV_FILE="fastlane/.env.release"
if [ -f "$ENV_FILE" ]; then
  log "Loading secrets from $ENV_FILE"
  set -a; . "$ENV_FILE"; set +a
fi

# The .p8 is multi-line. Pasted into an env file unquoted it does not just fail
# to load — `source` runs its continuation lines as commands and echoes key
# material into the terminal. Reading the file directly removes the hazard, so
# the env var is the fallback rather than the requirement.
if [ -z "${APP_STORE_CONNECT_API_KEY_KEY:-}" ]; then
  p8=$(ls fastlane/AuthKey_*.p8 2>/dev/null | head -1 || true)
  if [ -n "$p8" ]; then
    APP_STORE_CONNECT_API_KEY_KEY=$(cat "$p8"); export APP_STORE_CONNECT_API_KEY_KEY
    : "${APP_STORE_CONNECT_API_KEY_KEY_ID:=$(basename "$p8" .p8 | sed 's/^AuthKey_//')}"
    export APP_STORE_CONNECT_API_KEY_KEY_ID
    log "Loaded the App Store Connect key from $p8"
  fi
fi
case "${APP_STORE_CONNECT_API_KEY_KEY:-}" in
  *"BEGIN PRIVATE KEY"*) ;;
  "") ;;
  *) error "APP_STORE_CONNECT_API_KEY_KEY is set but is not a PEM key — it was probably truncated by an unquoted multi-line value in $ENV_FILE" ;;
esac

# match expects a full HTTP Basic credential: base64("user:token"). Handed a raw
# PAT it builds a malformed header, the clone fails, and fastlane prints the
# whole git command — token included — into the terminal and any CI log. Check
# the shape here so a wrong value never reaches fastlane.
if [ -n "${MATCH_GIT_BASIC_AUTHORIZATION:-}" ]; then
  if ! printf '%s' "$MATCH_GIT_BASIC_AUTHORIZATION" | base64 -d 2>/dev/null | grep -q ':'; then
    error "MATCH_GIT_BASIC_AUTHORIZATION is not base64 of \"user:token\".
    It looks like a raw token, which fastlane will echo in full when the clone fails.
    Build it with:  printf '%s' 'YOUR_GH_USER:YOUR_PAT' | base64"
  fi
fi

missing=()
for var in MATCH_PASSWORD MATCH_GIT_BASIC_AUTHORIZATION \
           APP_STORE_CONNECT_API_KEY_KEY_ID APP_STORE_CONNECT_API_KEY_ISSUER_ID \
           APP_STORE_CONNECT_API_KEY_KEY TUIST_LOOX_LINK_PROD_TOKEN; do
  [ -n "${!var:-}" ] || missing+=("$var")
done
[ ${#missing[@]} -eq 0 ] || error "Missing secrets: ${missing[*]} (set them in $ENV_FILE or export them)"
success "All required secrets present"

# ── Repository state ──
BRANCH=$(git branch --show-current)
[ "$BRANCH" = "main" ] || error "Must be on main. Currently on: $BRANCH"
# Scoped to what ends up in the binary. A dirty README, a docs edit or an
# in-progress screenshot deck cannot change the build, and refusing on them only
# forces a stash dance that risks losing someone's work mid-release.
APP_PATHS=(Vaultify VaultifyCore VaultifyAutoFill VaultifyAutoFillMac VaultifySafari Project.swift)
DIRTY=$(git status --porcelain -- "${APP_PATHS[@]}")
[ -z "$DIRTY" ] || error "Uncommitted changes in app sources — the build would not match any commit:
$(printf '      %s\n' "$DIRTY")"

VERSION=$(grep -m1 '"MARKETING_VERSION":' Project.swift | sed -E 's/.*"MARKETING_VERSION": "([^"]+)".*/\1/')
NUMBER=$(grep -m1 '"CURRENT_PROJECT_VERSION":' Project.swift | sed -E 's/.*"CURRENT_PROJECT_VERSION": "([0-9]+)".*/\1/')
[ -n "$VERSION" ] && [ -n "$NUMBER" ] || error "Could not read the version out of Project.swift"
log "Releasing $VERSION ($NUMBER) from $(git rev-parse --short HEAD)"

# The workflow ships only a tagged commit; keep that true here so a build that
# reaches TestFlight is always reproducible from a tag.
TAG="v$VERSION"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  error "No tag $TAG for this version. Run 'make release' (it bumps, tags and pushes), then re-run this."
fi
TAG_SHA=$(git rev-list -n1 "$TAG")
HEAD_SHA=$(git rev-parse HEAD)
# What has to match the tag is the SOURCE that goes into the binary, not the
# whole tree — tooling commits landing on main after a tag do not change what
# ships. Insisting on an identical HEAD only forced a version bump to fix a bug
# in this very script.
if [ "$TAG_SHA" != "$HEAD_SHA" ]; then
  git merge-base --is-ancestor "$TAG_SHA" "$HEAD_SHA" \
    || error "HEAD does not descend from $TAG. Check out the tag first."
  DRIFT=$(git diff --name-only "$TAG_SHA" "$HEAD_SHA" -- Vaultify VaultifyCore VaultifyAutoFill VaultifyAutoFillMac VaultifySafari Project.swift)
  [ -z "$DRIFT" ] || error "App sources changed since $TAG, so the build would not match the tag:
$(printf '      %s\n' $DRIFT)"
  success "HEAD is ahead of $TAG, but every app source matches it"
else
  success "HEAD is $TAG"
fi

# ── Evidence ──
if [ "$SKIP_TESTS" -eq 1 ]; then
  echo "${YELLOW}[!]${NC} Skipping tests. Only do this when ci.yml is already green for $TAG_SHA."
else
  log "Running the unit suite (the same target CI gates on)"
  # Pin the same toolchain CI resolves. A beta Xcode double-frees during the
  # back-deployed `@MainActor` deinit and aborts the test host ~75 times a run,
  # so the suite fails with zero assertion failures — a red herring that cost a
  # day of chasing a bug that was never in the code.
  DEVELOPER_DIR=$(scripts/ci/select-xcode.sh 2>/dev/null | tail -n 1)
  export DEVELOPER_DIR
  log "Toolchain: $DEVELOPER_DIR"
  SIM_UDID=$(xcrun simctl list devices available --json \
    | /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
for runtime, devices in sorted(d.items()):
    if "iOS" not in runtime: continue
    for dev in devices:
        if dev.get("isAvailable") and "iPhone" in dev.get("name",""):
            print(dev["udid"]); raise SystemExit
raise SystemExit("no available iPhone simulator")')
  [ -n "$SIM_UDID" ] || error "No available iPhone simulator to test on"
  xcodebuild test -workspace Vaultify.xcworkspace -scheme Vaultify \
    -destination "id=$SIM_UDID" -derivedDataPath "$ROOT/.release-dd" \
    -only-testing:VaultifyTests \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES 2>&1 | tee /tmp/loox-release-tests.log | tail -5
  grep -q "TEST SUCCEEDED" /tmp/loox-release-tests.log \
    || error "Unit tests did not pass. Full log: /tmp/loox-release-tests.log"
  success "Unit suite green"
fi

# ── Project generation (Release configuration, prod token baked in) ──
log "Generating the project with the release configuration"
scripts/ci/prepare-project.sh
success "Project generated"

# ── Signing preflight ──
# Manual signing embeds the entitlements file as-is, but codesign still refuses
# any entitlement the provisioning profile does not grant. App Attest is the one
# that bites: the app declares `appattest-environment`, and a profile minted
# before that capability existed fails the build halfway through an archive.
# Catch it here, in seconds, instead of after a ten-minute build.
log "Syncing signing assets (match, readonly)"
bundle exec fastlane certificates

# Xcode 16 moved the install location; older toolchains still use the second.
PROFILE_DIRS=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)
preflight_profile() {
  local bundle_id="$1" dir f plist name found=""
  for dir in "${PROFILE_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.mobileprovision; do
      [ -f "$f" ] || continue
      plist=$(security cms -D -i "$f" 2>/dev/null) || continue
      name=$(printf '%s' "$plist" | plutil -extract Name raw - 2>/dev/null) || continue
      [ "$name" = "match AppStore $bundle_id" ] || continue
      found="$f"
      if printf '%s' "$plist" | plutil -extract Entitlements xml1 -o - - 2>/dev/null \
         | grep -q "com.apple.developer.devicecheck.appattest-environment"; then
        success "Profile for $bundle_id grants App Attest"
      else
        # Measured, not assumed: codesign rejects the build outright —
        #   "Provisioning profile … doesn't include the App Attest capability"
        # — about ten minutes into the archive. Fail here instead.
        error "Profile 'match AppStore $bundle_id' does not grant App Attest.
    codesign will reject the archive. App Attest is NOT settable through the App
    Store Connect API (it rejects capabilityType APP_ATTEST), so this is a manual
    step, once:
      1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers
      2. open $bundle_id → tick App Attest → Save
      3. bundle exec fastlane match appstore --force"
      fi
      break 2
    done
  done
  [ -n "$found" ] || error "No 'match AppStore $bundle_id' profile found after match ran"
}
preflight_profile "com.bervion.vaultify"
success "Signing preflight passed"

# ── Sign and upload ──
if [ "$DRY_RUN" -eq 1 ]; then
  echo "${YELLOW}[!]${NC} --dry-run: stopping before the archive. Nothing was signed or uploaded."
  exit 0
fi

log "Signing with match and uploading to TestFlight"
bundle exec fastlane build_and_upload

success "Uploaded $VERSION ($NUMBER) to TestFlight"
echo "    App Store Connect: https://appstoreconnect.apple.com/apps"
