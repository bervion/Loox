---
name: vaultify-p2-persona-autofill-plan
description: P2 Persona Context + AutoFill plan (INV-R03 isolation consumption) — 4 phases, key architectural constraint on the AutoFill extension
metadata:
  type: project
---

P2 plan created 2026-07-06 at `plans/260706-1238-persona-spaces-relay-proposal-v3/p2-plan.md` (+ p2-phase-P2.1..P2.4). Consumes P1's `PersonaIsolationPolicy`. See [[vaultify-persona-relay-proposal-v3]].

**Why:** INV-R03 — a strictAnonymous active persona must HARD-EXCLUDE (not down-rank) cross-persona identity data from search, ranking, and AutoFill prefill.

**How to apply / load-bearing constraints discovered while planning:**
- The AutoFill extension **cannot see the active persona**: `activePersonaID` is in `UserDefaults.standard`, NOT the App Group. P2.3 adds a thin App-Group mirror of `{policy raw, primaryProfileItemID opaque}` (never a plaintext email) so the extension resolves the persona-correct prefill under the Vault Key, fail-closed under strictAnonymous.
- Subtle leak: `SearchScreen.seedScope` defaults to `.allSpaces` when no current Space — gating the chip is not enough; P2.2 centralizes a fail-closed `defaultSearchScope`.
- In-app editor has NO username prefill today → adding suggestions is greenfield (no regression); the real prefill leak is the extension's `CreateLoginView` via `VaultReader.defaultIdentityUsername`.
- Items are NOT persona-partitioned in P1 (`FolderSecret.personaId` nil) → isolation = suggestion/search-widening exclusion, not a full data partition (P3+). QuickType per-item suppression deferred (documented acceptance).
- Phase order: P2.1 pure engine → P2.2 in-app → (P2.3 extension ∥ P2.4 management), but serialize `Localizable.xcstrings` edits.
</content>
