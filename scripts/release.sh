#!/bin/bash
# scripts/release.sh — fully automated release for the native Xcode app.
#
# Usage: ./scripts/release.sh   (or: make release)
#
# Steps:
#   1. Pre-checks (on main, clean tree, fetch tags)
#   2. Read commits since last tag → auto-pick bump (major/minor/patch)
#   3. Bump MARKETING_VERSION + CURRENT_PROJECT_VERSION in the pbxproj
#      (app + AutoFill extension stay in lockstep — every config is rewritten)
#   4. Generate EN/VI release notes via Claude CLI (fallback templates)
#   5. Update CHANGELOG.md
#   6. Commit + annotated tag vX.Y.Z + push → GitHub Actions builds & ships TestFlight
#
# Override bump: BUMP_OVERRIDE=major|minor|patch ./scripts/release.sh
# Non-interactive: RELEASE_YES=1 ./scripts/release.sh

set -e

MANIFEST="Project.swift"
CHANGELOG="CHANGELOG.md"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}[release]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ── Pre-checks ──
log "Running pre-checks..."
BRANCH=$(git branch --show-current)
[ "$BRANCH" = "main" ] || error "Must be on main branch. Currently on: $BRANCH"
[ -z "$(git diff --cached --name-only)" ] || error "Staged changes found. Commit or unstage first."
[ -z "$(git diff --name-only)" ] || error "Unstaged changes found. Commit or stash first."
[ -f "$MANIFEST" ] || error "Cannot find $MANIFEST (run from repo root)."
git fetch --tags --quiet
success "Pre-checks passed"

# ── Last tag + commits ──
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$LAST_TAG" ]; then
  LAST_TAG="HEAD~50"
  log "No previous tag. Using recent commits."
else
  log "Last tag: $LAST_TAG"
fi

COMMITS=$(git log "$LAST_TAG"..HEAD --pretty=format:"%s" --no-merges 2>/dev/null || git log --pretty=format:"%s" --no-merges -50)
[ -n "$COMMITS" ] || error "No commits since last tag. Nothing to release."
COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
log "Found $COMMIT_COUNT commits since $LAST_TAG"

# ── Auto-detect bump type from conventional commits ──
HAS_BREAKING=false; HAS_FEAT=false; HAS_FIX=false
while IFS= read -r c; do
  echo "$c" | grep -qE '^(feat|fix|refactor|perf)(\(.+\))?!:' && HAS_BREAKING=true
  echo "$c" | grep -qiE 'BREAKING CHANGE' && HAS_BREAKING=true
  echo "$c" | grep -qE '^feat(\(.+\))?:' && HAS_FEAT=true
  echo "$c" | grep -qE '^(fix|perf)(\(.+\))?:' && HAS_FIX=true
done <<< "$COMMITS"

if [ -n "$BUMP_OVERRIDE" ]; then BUMP_TYPE="$BUMP_OVERRIDE"
elif [ "$HAS_BREAKING" = true ]; then BUMP_TYPE="major"
elif [ "$HAS_FEAT" = true ]; then BUMP_TYPE="minor"
elif [ "$HAS_FIX" = true ]; then BUMP_TYPE="patch"
else BUMP_TYPE="patch"; fi
log "Auto-detected bump: ${YELLOW}$BUMP_TYPE${NC}"

if [ -z "$BUMP_OVERRIDE" ] && [ "$RELEASE_YES" != "1" ] && [ -t 0 ]; then
  read -r -p "Bump type [$BUMP_TYPE] (major/minor/patch/skip): " OVERRIDE
  [ "$OVERRIDE" = "skip" ] && error "Release cancelled."
  [ -n "$OVERRIDE" ] && BUMP_TYPE="$OVERRIDE"
fi

# ── Current version from pbxproj ──
CURRENT_VERSION=$(grep -m1 '"MARKETING_VERSION":' "$MANIFEST" | sed -E 's/.*: "([^"]+)".*/\1/')
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

case "$BUMP_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) error "Unknown bump type: $BUMP_TYPE" ;;
esac
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

CURRENT_BUILD=$(grep -m1 '"CURRENT_PROJECT_VERSION":' "$MANIFEST" | sed -E 's/.*: "([0-9]+)".*/\1/')
NEW_BUILD=$(( CURRENT_BUILD + 1 ))
log "Version: $CURRENT_VERSION → ${GREEN}$NEW_VERSION${NC}  (build ${CURRENT_BUILD} → ${NEW_BUILD})"

# ── Categorize commits → raw changelog ──
FEAT=""; FIX=""; PERF=""; OTHER=""
while IFS= read -r c; do
  CLEAN=$(echo "$c" | sed -E 's/^[a-z]+(\([^)]*\))?!?: //')
  if   echo "$c" | grep -qE '^feat'; then FEAT="${FEAT}\n- ${CLEAN}"
  elif echo "$c" | grep -qE '^fix';  then FIX="${FIX}\n- ${CLEAN}"
  elif echo "$c" | grep -qE '^perf'; then PERF="${PERF}\n- ${CLEAN}"
  else OTHER="${OTHER}\n- ${CLEAN}"; fi
done <<< "$COMMITS"

TODAY=$(date +%Y-%m-%d)
RAW="## [$NEW_VERSION] - $TODAY\n"
[ -n "$FEAT" ]  && RAW="${RAW}\n### Added${FEAT}\n"
[ -n "$FIX" ]   && RAW="${RAW}\n### Fixed${FIX}\n"
[ -n "$PERF" ]  && RAW="${RAW}\n### Improved${PERF}\n"
[ -n "$OTHER" ] && RAW="${RAW}\n### Changed${OTHER}\n"
CHANGELOG_ENTRY=$(echo -e "$RAW")

# ── Generate store release notes (EN/VI) ──
log "Generating release notes..."
export RELEASE_VERSION="$NEW_VERSION"
export RELEASE_CHANGES="$CHANGELOG_ENTRY"
chmod +x scripts/generate-release-notes.sh
./scripts/generate-release-notes.sh notes || warn "Used fallback templates."

NOTES_EN=$(cat metadata/apple/en-US/release_notes.txt 2>/dev/null || echo "")
NOTES_VI=$(cat metadata/apple/vi/release_notes.txt 2>/dev/null || echo "")

echo ""
echo -e "${BLUE}═══ CHANGELOG ═══${NC}"; echo "$CHANGELOG_ENTRY"
echo ""; echo -e "${BLUE}═══ NOTES (EN) ═══${NC}"; echo "$NOTES_EN"
echo ""; echo -e "${BLUE}═══ NOTES (VI) ═══${NC}"; echo "$NOTES_VI"; echo ""

if [ "$RELEASE_YES" != "1" ] && [ -t 0 ]; then
  read -r -p "Accept release notes? [Y/n/edit]: " ACCEPT
  [ "$ACCEPT" = "n" ] && error "Release cancelled. Edit commits/notes and retry."
  if [ "$ACCEPT" = "edit" ]; then
    ${EDITOR:-vim} metadata/apple/en-US/release_notes.txt metadata/apple/vi/release_notes.txt
    NOTES_EN=$(cat metadata/apple/en-US/release_notes.txt 2>/dev/null || echo "")
    NOTES_VI=$(cat metadata/apple/vi/release_notes.txt 2>/dev/null || echo "")
  fi
fi

# ── Bump pbxproj (all configs: app + extension) ──
log "Bumping $MANIFEST..."
sed -i '' -E "s/(\"MARKETING_VERSION\": )\"[^\"]*\"/\1\"${NEW_VERSION}\"/" "$MANIFEST"
sed -i '' -E "s/(\"CURRENT_PROJECT_VERSION\": )\"[0-9]+\"/\1\"${NEW_BUILD}\"/" "$MANIFEST"
success "Project.swift → ${NEW_VERSION} (${NEW_BUILD})"

# ── Update CHANGELOG.md ──
if [ -f "$CHANGELOG" ]; then
  TMP=$(mktemp)
  { echo "# Changelog"; echo ""; echo "$CHANGELOG_ENTRY"; echo ""; tail -n +2 "$CHANGELOG"; } > "$TMP"
  mv "$TMP" "$CHANGELOG"
else
  { echo "# Changelog"; echo ""; echo "$CHANGELOG_ENTRY"; } > "$CHANGELOG"
fi
success "CHANGELOG.md updated"

# ── Commit + tag + push ──
log "Committing..."
git add "$MANIFEST" "$CHANGELOG" metadata/
git commit -m "chore(release): v${NEW_VERSION}

$CHANGELOG_ENTRY"

TAG_MESSAGE="v${NEW_VERSION}

${NOTES_EN}

${NOTES_VI}"
git tag -a "v${NEW_VERSION}" -m "$TAG_MESSAGE"
success "Tagged v${NEW_VERSION}"

log "Pushing commit + tag..."
git push origin main
git push origin "v${NEW_VERSION}"

# ── GitHub Release ──
if command -v gh >/dev/null 2>&1; then
  log "Creating GitHub Release..."
  RELEASE_BODY="## What's New

${CHANGELOG_ENTRY}

---

<details><summary>TestFlight release notes</summary>

**English**
${NOTES_EN}

**Tiếng Việt**
${NOTES_VI}

</details>"
  gh release create "v${NEW_VERSION}" --title "Vaultify v${NEW_VERSION}" --notes "$RELEASE_BODY" --latest || warn "gh release failed (continuing)."
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Release v${NEW_VERSION} shipped (build ${NEW_BUILD})${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo "  GitHub Actions → sign (match) → upload TestFlight"
echo "  https://github.com/bervion/Vaultify/actions"
echo ""
