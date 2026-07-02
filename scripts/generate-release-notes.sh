#!/bin/bash
# scripts/generate-release-notes.sh — App Store / TestFlight release notes via Claude CLI.
#
# Usage: ./scripts/generate-release-notes.sh [notes]
#
# Env (optional):
#   RELEASE_VERSION  — version string (default: MARKETING_VERSION from pbxproj)
#   RELEASE_CHANGES  — raw changelog (default: commits since last tag)
#
# Writes metadata/apple/<locale>/release_notes.txt for each app locale (en-US, vi).
# Falls back to localized templates if the Claude CLI is unavailable.

set -e

PBXPROJ="Vaultify.xcodeproj/project.pbxproj"
METADATA_DIR="metadata/apple"
# App locales (knownRegions: en, vi) → Apple App Store locale codes.
LOCALES=("en:en-US" "vi:vi")

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${BLUE}[notes]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }

get_version() {
  if [ -n "$RELEASE_VERSION" ]; then echo "$RELEASE_VERSION"
  else grep -m1 'MARKETING_VERSION = ' "$PBXPROJ" | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' "'; fi
}

get_changes() {
  if [ -n "$RELEASE_CHANGES" ]; then echo "$RELEASE_CHANGES"
  else
    local LAST_TAG; LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -z "$LAST_TAG" ]; then git log --pretty=format:"%s" --no-merges -20
    else git log "$LAST_TAG"..HEAD --pretty=format:"%s" --no-merges; fi
  fi
}

fallback_notes() {
  local VERSION="$1"
  warn "Using fallback templates..."
  for PAIR in "${LOCALES[@]}"; do
    local APPLE="${PAIR#*:}"
    mkdir -p "${METADATA_DIR}/${APPLE}"
    case "${PAIR%%:*}" in
      vi) echo "Phiên bản ${VERSION}: Cải thiện hiệu suất và sửa lỗi." > "${METADATA_DIR}/${APPLE}/release_notes.txt" ;;
      *)  echo "Version ${VERSION}: Performance improvements and bug fixes." > "${METADATA_DIR}/${APPLE}/release_notes.txt" ;;
    esac
  done
  success "Fallback release notes saved"
}

generate_via_claude() {
  local VERSION="$1" CHANGES="$2"
  local PROMPT="You are a professional App Store copywriter for Loox Password (display name: Loox), a private password manager.

App context:
- Loox stores passwords and passkeys fully on-device. Zero backend, no account, no tracking.
- Vault is encrypted with Argon2id; Face ID unlock; iOS AutoFill for passwords and passkeys.
- Audience: privacy-conscious users. Markets: Vietnam primary, global secondary.

Write release notes for version ${VERSION} based on the changes below.
Generate one version each for English and Vietnamese.

Rules:
- Professional tone. No emoji. No technical jargon. No security claims that overpromise.
- Focus on user benefits, not implementation details.
- Max 400 chars per language.
- Vietnamese must read natively, not like a translation.
- If only bug fixes: one short sentence per language.
- No competitor names, no trademarks, no prices, no ALL CAPS.

Changes:
${CHANGES}

Respond with ONLY a JSON object (no markdown, no code fences):
{\"en\": \"...\", \"vi\": \"...\"}"

  local RESPONSE
  RESPONSE=$(echo "$PROMPT" | claude --print --model sonnet --output-format text 2>/dev/null || echo "")
  [ -n "$RESPONSE" ] || return 1
  RESPONSE=$(echo "$RESPONSE" | sed 's/^```json//' | sed 's/^```//' | sed 's/```$//')
  echo "$RESPONSE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || return 1
  echo "$RESPONSE"
}

save_from_json() {
  echo "$1" | python3 -c "
import json, sys, os
LOCALE_MAP = {'en': 'en-US', 'vi': 'vi'}
data = json.load(sys.stdin)
for locale, note in data.items():
    apple = LOCALE_MAP.get(locale)
    if not apple or not isinstance(note, str) or not note.strip():
        continue
    d = os.path.join('${METADATA_DIR}', apple)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'release_notes.txt'), 'w') as f:
        f.write(note.strip()[:4000])
print(f'Saved notes for {len(data)} locales')
"
}

VERSION=$(get_version)
CHANGES=$(get_changes)
log "Version: ${VERSION}"

if command -v claude >/dev/null 2>&1 && JSON=$(generate_via_claude "$VERSION" "$CHANGES"); then
  save_from_json "$JSON"
  success "Release notes generated"
else
  fallback_notes "$VERSION"
fi
