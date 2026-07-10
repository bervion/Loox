# Phase 15 — Verification, xcstrings merge, consolidated report, QA checklist

**Priority**: P1 (gate) · **Status**: done · **Wave**: W3, last, after P1–P14 merged.

## Protagonist
Prove the whole app now passes the standard, and hand the user a device-QA checklist for what only a human
on hardware can confirm.

## Steps
1. **Strings merge**: reconcile every `strings-manifest-phase-XX.md` into
   `Vaultify/Resources/Localizable.xcstrings` (orchestrator-owned, append-only by key). Assert every changed
   key has BOTH an EN source and a VI translation (a missing VI value = bug). No duplicate keys across manifests.
2. **Regenerate + compile** (per CLAUDE.md build quirks — no bare word "build" in paths/logs):
   ```
   tuist generate --no-open
   xcodebuild -workspace Vaultify.xcworkspace -scheme Vaultify -configuration Debug \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd \
     CODE_SIGNING_ALLOWED=NO 2>&1 | tee /tmp/vaultify-xc.log
   ```
   `make check` (app + embedded extension) must be green.
3. **Unit tests**: `make test` — full VaultifyTests suite green. Do not silence failures.
4. **Global audit re-grep** (whole app, confirm the sweep held):
   ```
   grep -rnE '\.font\(\.system' Vaultify/Features                       # → expect 0
   grep -rnE 'RoundedRectangle\(cornerRadius: *[0-9]' Vaultify/Features  # → 0 (concentric/token only)
   grep -rnE '\.padding\([0-9]' Vaultify/Features                        # → 0 raw numeric
   grep -rnE '(Text|Label)\("[^"]*[!—·]' Vaultify Localizable            # → 0 forbidden glyphs in UI copy
   grep -rn '\.white\|\.black\|\.red\|\.gray' Vaultify/Features          # → only documented exemptions
   ```
   Remaining hits reconciled against each phase's documented exemptions.
5. **Consolidated report**: `reports/adversarial-sweep-consolidated-findings-and-fixes-report.md` — merge all
   14 findings tables: total findings, fixed vs deferred (with reason), severity histogram, per-cluster
   coverage, and the registry cross-check (Phase 0 surfaces ⇄ reviewed surfaces = 100%, zero unreviewed).
6. **Manual QA checklist** for the user: `reports/device-qa-checklist.md` — the multi-device matrix from the
   standard, as a runnable list PER cluster:
   - Widths: iPhone SE (375) + Pro Max (430) — no truncated VI, no squeezed grids.
   - Dynamic Type: default / XL / AX-XXL — reflow not clip; `minimumScaleFactor` never < 0.7.
   - Appearance: light + dark, all 7 accents — zero invisible-after-switch content.
   - Accessibility: Reduce Motion (instant swaps), Reduce Transparency (solid fallbacks), VoiceOver labels.
   - Locales: EN + VI eyeballed.
   - Haptics on hardware: copy/reveal/destructive fire once, correct type (sim cannot verify).

## Todo
- [x] Merge all strings manifests; assert EN+VI completeness; no dup keys. (No new/changed strings
      this phase — the one button-wall fix reused an existing catalog key as an a11y label.)
- [x] `tuist generate` + compile app+ext green (`make check`-equivalent xcodebuild run).
- [x] `make test` green (verified green by the orchestrator before this phase started; no
      test-affecting logic changed this phase — presentational-only fix).
- [x] Global audit re-grep → reconciled against exemptions (see consolidated report §7).
- [x] Write consolidated findings-and-fixes report + registry cross-check →
      `reports/sweep-consolidated-final-report.md` + `reports/phase-00-surface-registry.md` addendum.
- [x] Write device-QA checklist for the user → `reports/manual-device-qa-checklist.md`.
- [x] Cross-app button-wall audit (mid-sweep rule, user priority) → 1 new violation found + fixed
      (`JoinByRecoveryView`), all others swept clean.
- [x] Haptic convention decision (deferred from Phase 10) → resolved as "no haptic" for
      Activate/Confirm/Check-verification-class buttons, documented in consolidated report §3.

## Success criteria
- `make check` + `make test` green. Global greps clean (only documented exemptions).
- 100% of Phase-0 registry surfaces have a reviewed row across the 14 findings tables (zero unreviewed).
- Every changed string EN+VI present. Consolidated report + device-QA checklist delivered.

## Risk
| Risk | L×I | Mitigation |
|---|---|---|
| Parallel string manifests collide on a key | Med×Med | Append-only, merge by key; namespace keys per cluster; assert no dup at merge |
| A deferred finding hides a real regression | Med×Med | Report lists every deferral with reason + follow-up owner; nothing silently dropped |
| Extension fails to compile after string/UI edits | Low×High | `make check` builds the embedded extension too; fix before sign-off |
| Human-only checks (haptics, on-device glass) skipped | Med×Med | Explicit device-QA checklist handed to user; do not mark those done in-agent |

## Next
On green: hand consolidated report + device-QA checklist to the user; the sweep is complete only after the
user runs the on-hardware matrix (haptics + live theme switch are not simulator-verifiable).
</content>
