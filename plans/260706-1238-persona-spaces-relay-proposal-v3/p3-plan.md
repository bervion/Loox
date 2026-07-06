---
title: "P3 — Local Email Alias Model"
description: "Local-only EmailAlias domain model + sealed record + sync + minimal UI, with active state gated OFF behind a relay feature flag."
status: done
priority: P2
effort: 8h
branch: feat/persona-p3-alias-model
tags: [persona, email-alias, cloudkit, sealed-record, feature-flag]
created: 2026-07-06
---

# P3 — Local Email Alias Model

**Canonical:** `proposal-v3-locked-decisions.md` §P3 + D14 + INV-R03/R04/R05.
**Framing:** LOCAL ONLY. No Cloudflare, no relay, no networking, no mail. Model + manage
aliases *before* the relay exists WITHOUT creating addresses that look like they work.
The `active` (live-forwarding) state is gated behind a feature flag that is **OFF** — only
`draft`/`reserved` are user-reachable, so nothing implies a working address.

## Core decisions (autonomous — see phase files)
- **DRY the persona pattern verbatim.** `EmailAlias`/`EmailAliasSecret`/`EmailAliasRecord`
  mirror `Persona`/`PersonaSecret`/`PersonaRecord` (seal, LWW-by-`updatedAt`, CK record type,
  push/pull). No new sync mechanism.
- **Feature flag `RelayFeature.activeAliasesEnabled = false`** (mirrors `WallpaperFeature`).
  Repo blocks any transition to `.active` while off; UI never surfaces `.active`.
- **Address never rendered as `@domain` pre-relay.** `AliasAddress.display(...)` emits the
  full `localPart@relay…` string ONLY when the flag is on AND status `.active`; otherwise the
  bare `localPart` + a "reserved / not active yet" treatment (unit-tested: no `@`).
- **Two tiers:** persona alias (≤1 per persona, stable) + per-site alias (many, random
  localPart for anti-correlation), bound to a login item (`boundItemId`) / `boundDomain`.
- **D14 warning** shown on every alias surface: *"Replies from your destination inbox may
  reveal your real email address."* Localized EN+VI.

## Phases

| # | Phase | Depends | Effort | Status |
|---|-------|---------|--------|--------|
| 1 | [Alias domain model + sealed record + flag + pure helpers](p3-phase-01-model-and-flag.md) | — | 2.5h | pending |
| 2 | [Store + CloudKit sync + repository CRUD/resolvers](p3-phase-02-store-sync-repo.md) | P1 | 3h | pending |
| 3 | [Minimal UI — aliases screen, editor, Settings entry, l10n](p3-phase-03-ui-localization.md) | P2 | 2.5h | pending |
| 4 | [OPTIONAL/DEFERRED — login-editor alias suggestion (flag-gated)](p3-phase-04-optional-editor-suggestion.md) | P2,P3 | 1.5h | deferred |

Critical path: P1 → P2 → P3. Phase 4 is deferred (YAGNI — binding already lives in the
alias editor; reverse-direction prefill adds isolation surface for near-zero pre-relay value).

## Key invariants carried into every phase
- **INV-R03**: an alias/localPart of persona A MUST NOT surface under persona B (fail-closed;
  strictAnonymous excludes, never down-ranks).
- **No live-looking address pre-relay** (flag OFF → no `.active`, no `@domain` rendering).
- **Sealed-schema growth** (P1 lesson): custom `Decodable` with `decodeIfPresent` for
  status/tier/optional bindings — a non-optional-with-default is NOT decode-optional under
  synthesized `Codable`.
- **LWW discipline**: every alias mutation re-seals + bumps `updatedAt`; delete = tombstone.
- **Erase Vault** deletes `EmailAliasRecord` too (D4 offline-block is P4A-only: no alias can
  be `.active` in P3, so erase is never blocked here).

## Top 3 risks
1. Shipping an address that *looks* like it works → App Review reject + trust breach.
2. CloudKit record-type field mismatch → pull silently drops aliases (guard-let no-op).
3. Sealed-schema decode throw on legacy/partial blobs → aliases vanish on unseal.

Mitigations detailed per phase.
