# Phase 07 — Tests, review, dead-code cleanup

## Overview
Priority P1 (gate) · Status: pending · Depends: all phases.

## Steps
1. **Unit tests** (`VaultifyTests/SharedItemsProjectionTests.swift` + additions):
   - Projection: grant fixtures → VaultItem mapping (title fallback, TOTP placeholder,
     shared-value fields, id scheme round-trip).
   - Owned-surface purity: `repository.items` / export / backup codec contain no shared items;
     owned-item encode bytes unchanged by `sharedOrigin` addition.
   - Capability switch binding mapping (phase 5).
2. **Dead code delete**: `SharedItemView.swift`, SharedWithMeScreen zone-list remnants,
   `SharedZoneRoute` destinations if fully replaced (check universal-link/resume paths first),
   orphaned strings from `Localizable.xcstrings` (leave harmless ones).
3. **code-reviewer subagent** over the full V1.2 diff — explicit checks: owned-item regression,
   shared-item write-path impossibility (no edit affordance reachable), RequestCodeModel identity
   across refreshes, sync/backup purity, localization completeness, U-decision compliance (V1-V7).
4. Fix findings → re-run suite → both platforms compile.
5. **Docs**: codebase-summary sharing section (projection architecture), plan sync-back, memory.
6. **2-device QA runbook** (append to plan.md): share → auto-invite → accept from notification
   screen → item in list → detail request round-trip → rename on A visible on B → revoke →
   item disappears from B lists.

## Success criteria
Suite green (existing 168 + new), review findings resolved, custom shared screens deleted,
docs/plan/memory synced, QA runbook ready for the user.
