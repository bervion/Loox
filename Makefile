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
# Test targets, each on its OWN throwaway simulator — the same one-target,
# one-device shape CI uses (scripts/ci/run-xcode-suite.sh pins the
# Vaultify-Quality scheme, which is what actually carries the tests; the
# auto-generated "Vaultify" scheme builds the app only).
#
# Separate devices are not paranoia. The suites share one bundle id, so a unit
# test that writes the app's own UserDefaults leaves that value behind for the
# UI tests to launch into. Run a subset with:
#   make test TEST_TARGETS=VaultifySnapshotTests
TEST_TARGETS ?= VaultifyTests VaultifySnapshotTests VaultifyUITests

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
	@echo "  make test          Unit + snapshot + UI suites on a throwaway simulator"
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
	@echo "✓ Pushed. CI: https://github.com/bervion/Loox/actions"

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
# A generic destination is valid HERE and only here: nothing is executed.
check lint: gen
	@set -e; set -o pipefail; \
	export DEVELOPER_DIR="$$(scripts/ci/select-xcode.sh | tail -n 1)"; \
	xcodebuild -workspace Vaultify.xcworkspace -scheme $(SCHEME) -configuration Debug \
	  -destination 'generic/platform=iOS Simulator' -derivedDataPath $(DD) \
	  CODE_SIGNING_ALLOWED=NO | tail -20
	@echo "✓ Compile check passed"

# ── Test suites: one target, one throwaway simulator, same as CI ──
test: gen
	@set -u; \
	export DEVELOPER_DIR="$$(scripts/ci/select-xcode.sh | tail -n 1)"; \
	overall=0; \
	for target in $(TEST_TARGETS); do \
	  echo "── $$target ──"; \
	  simlog="/tmp/vaultify-sim-$$target.log"; \
	  udid="$$(scripts/ci/create-simulator.sh 2>"$$simlog" | tail -n 1)"; \
	  if [ -z "$$udid" ]; then cat "$$simlog"; exit 1; fi; \
	  log="/tmp/vaultify-xctest-$$target.log"; \
	  scripts/ci/run-xcode-suite.sh "$$target" "$$udid" "$(DD)" \
	    "/tmp/vaultify-$$target.xcresult" > "$$log" 2>&1 || overall=1; \
	  summary="/tmp/vaultify-$$target.xcresult.summary.json"; \
	  if [ -f "$$summary" ]; then \
	    /usr/bin/python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("   %s: %s passed, %s failed, %s skipped of %s" % (d.get("result"), d.get("passedTests"), d.get("failedTests"), d.get("skippedTests"), d.get("totalTestCount")))' "$$summary"; \
	  else \
	    tail -3 "$$log"; \
	  fi; \
	  echo "   log: $$log"; \
	  xcrun simctl shutdown "$$udid" >/dev/null 2>&1 || true; \
	  xcrun simctl delete "$$udid" >/dev/null 2>&1 || true; \
	done; \
	exit $$overall
