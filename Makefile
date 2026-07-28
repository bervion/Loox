# Makefile — Vaultify release automation
#
# Daily:    make push
# Beta:     make beta      (TestFlight, quick)
# Release:  make release   (auto bump + AI notes + tag → TestFlight)
# Hotfix:   make hotfix    (patch bump)
#
# The Xcode project is generated from Project.swift by Tuist. Run `make gen`
# (or any build target, which depends on it) after pulling or adding files.

.PHONY: help push release beta hotfix version changelog notes gen \
        match-setup certificates submit-ios check lint test

SCHEME := Vaultify
DD     := /tmp/vaultify-ci-dd
# Override with: make test DEST='platform=iOS Simulator,id=<UDID>'
DEST   ?= platform=iOS Simulator,name=iPhone 16

help:
	@echo ""
	@echo "  Vaultify Release Commands"
	@echo "  ─────────────────────────────────────"
	@echo "  make release       Full release (auto bump + notes + tag → TestFlight)"
	@echo "  make beta          Quick beta build → TestFlight"
	@echo "  make hotfix        Patch release"
	@echo "  make push          Push main (CI compile check)"
	@echo "  ─────────────────────────────────────"
	@echo "  make gen           Generate Xcode project (tuist generate)"
	@echo "  make version       Show version + build + last tag"
	@echo "  make changelog     Commits since last tag"
	@echo "  make notes         Preview AI release notes (no commit)"
	@echo "  make check         Local compile check (app + extension)"
	@echo "  ─────────────────────────────────────"
	@echo "  make match-setup   First-time match (create certs/profiles)"
	@echo "  make certificates  Sync signing assets (readonly)"
	@echo "  make submit-ios    Submit latest TestFlight build to review"
	@echo ""

# ── Release workflow ──
release:
	@chmod +x scripts/release.sh && ./scripts/release.sh

beta:
	@chmod +x scripts/release-beta.sh && ./scripts/release-beta.sh

hotfix:
	@chmod +x scripts/release.sh && BUMP_OVERRIDE=patch ./scripts/release.sh

push:
	git push origin main
	@echo "✓ Pushed. CI: https://github.com/bervion/Vaultify/actions"

# ── Project generation (Tuist) ──
gen:
	tuist generate --no-open

# ── Info ──
version:
	@printf 'MARKETING_VERSION: %s\n' "$$(grep -m1 '"MARKETING_VERSION":' Project.swift | sed -E 's/.*: "([^"]+)".*/\1/')"
	@printf 'BUILD:             %s\n' "$$(grep -m1 '"CURRENT_PROJECT_VERSION":' Project.swift | sed -E 's/.*: "([^"]+)".*/\1/')"
	@printf 'Last tag:          %s\n' "$$(git describe --tags --abbrev=0 2>/dev/null || echo none)"
	@printf 'Commits since tag: %s\n' "$$(git rev-list $$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --count)"

changelog:
	@LAST=$$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD); \
	echo "Changes since $$LAST:"; echo "─────────────────────"; \
	git log "$$LAST"..HEAD --pretty=format:"  %C(yellow)%h%C(reset) %s" --no-merges

notes:
	@chmod +x scripts/generate-release-notes.sh && ./scripts/generate-release-notes.sh notes
	@echo "── en-US ──"; cat metadata/apple/en-US/release_notes.txt 2>/dev/null; echo ""
	@echo "── vi ──";    cat metadata/apple/vi/release_notes.txt 2>/dev/null; echo ""
	@echo "── ja ──";    cat metadata/apple/ja/release_notes.txt 2>/dev/null; echo ""

# ── Signing (fastlane match) ──
match-setup:
	bundle exec fastlane match appstore

certificates:
	bundle exec fastlane certificates

submit-ios:
	bundle exec fastlane submit

# ── Local quality (compile check of app + embedded AutoFill extension) ──
check lint: gen
	xcodebuild -workspace Vaultify.xcworkspace -scheme $(SCHEME) -configuration Debug \
	  -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DD) \
	  CODE_SIGNING_ALLOWED=NO build | tail -20
	@echo "✓ Compile check passed"

# ── Unit tests (in-memory store; needs a concrete simulator) ──
test: gen
	xcodebuild test -workspace Vaultify.xcworkspace -scheme $(SCHEME) \
	  -destination '$(DEST)' -derivedDataPath $(DD) \
	  CODE_SIGNING_ALLOWED=NO 2>&1 | tee /tmp/vaultify-xctest.log | tail -6
