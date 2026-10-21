#!/bin/bash
# scripts/release-beta.sh — quick beta to TestFlight (no semver bump).
#
# Usage: ./scripts/release-beta.sh   (or: make beta)
#
# Keeps the current MARKETING_VERSION, bumps CURRENT_PROJECT_VERSION (+1) in
# Project.swift so the upload is unique/increasing, commits, then tags
# vX.Y.Z-beta.N → CI generates the project and ships it.

set -e

MANIFEST="Project.swift"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
log()     { echo -e "${BLUE}[beta]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

BRANCH=$(git branch --show-current)
[ "$BRANCH" = "main" ] || error "Must be on main. Currently: $BRANCH"
[ -z "$(git diff --name-only)" ] || error "Unstaged changes found. Commit or stash first."
git fetch --tags --quiet

VERSION=$(grep -m1 '"MARKETING_VERSION":' "$MANIFEST" | sed -E 's/.*: "([^"]+)".*/\1/')

LATEST_BETA=$(git tag -l "v${VERSION}-beta.*" | sort -V | tail -1)
if [ -z "$LATEST_BETA" ]; then BETA_NUM=1
else BETA_NUM=$(( $(echo "$LATEST_BETA" | sed "s/v${VERSION}-beta.//") + 1 )); fi
TAG="v${VERSION}-beta.${BETA_NUM}"

CURRENT_BUILD=$(grep -m1 '"CURRENT_PROJECT_VERSION":' "$MANIFEST" | sed -E 's/.*: "([0-9]+)".*/\1/')
NEW_BUILD=$(( CURRENT_BUILD + 1 ))
log "Creating $TAG (build ${CURRENT_BUILD} → ${NEW_BUILD})"

sed -i '' -E "s/(\"CURRENT_PROJECT_VERSION\": )\"[0-9]+\"/\1\"${NEW_BUILD}\"/" "$MANIFEST"

LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~20")
COMMITS=$(git log "$LAST_TAG"..HEAD --pretty=format:"• %s" --no-merges | head -20)

git add "$MANIFEST"
git commit -m "chore(beta): ${TAG} (build ${NEW_BUILD})"
git tag -a "$TAG" -m "$TAG (Beta, build ${NEW_BUILD})

Changes:
$COMMITS"

git push origin main
git push origin "$TAG"

success "Beta $TAG pushed!"
echo "  GitHub Actions → TestFlight: https://github.com/bervion/Loox/actions"
