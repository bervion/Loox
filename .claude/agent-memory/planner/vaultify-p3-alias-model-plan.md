---
name: vaultify-p3-alias-model-plan
description: P3 Local Email Alias Model plan — sealed EmailAlias mirroring Persona, relay feature-flag OFF gates active state, no backend
metadata:
  type: project
---

P3 (branch feat/persona-p3-alias-model) plan at `plans/260706-1238-persona-spaces-relay-proposal-v3/p3-plan.md` (+ p3-phase-01..04).

**Fact:** P3 is LOCAL ONLY — model + manage email aliases before the relay exists, without creating addresses that look like they work.
**Why:** shipping a fake-working address = App Review reject + user-trust breach (canonical D14 + framing).
**How to apply:** `EmailAlias`/`EmailAliasSecret`/`EmailAliasRecord` mirror `Persona`/`PersonaSecret`/`PersonaRecord` VERBATIM (seal, LWW-by-updatedAt, CK type `VaultEmailAlias`, push/pull). New flag `RelayFeature.activeAliasesEnabled = false` (mirrors [[vaultify-p2-persona-autofill-plan]]'s WallpaperFeature pattern) blocks any transition to `.active`; UI only shows draft/reserved. `AliasAddress.display` emits `@domain` ONLY when flag on + status .active. Two tiers: persona alias (≤1/persona) + per-site alias (random localPart, anti-correlation, bound to boundItemId). Phases 1-3 critical path; phase 4 (login-editor suggestion) DEFERRED (YAGNI — writing dead alias into live login is the exact failure the flag prevents).

Reused verified anchors: persona sync block VaultStore.swift:216-277, CloudSyncService.swift:230-269, reload VaultRepository.swift:75-78, seal path +Personas.swift:16-43. Sealed-schema growth needs custom Decodable + decodeIfPresent (P1 lesson, Persona.swift:98-109). Erase Vault: add EmailAliasRecord to store.eraseAll (D4 offline-block NOT needed in P3 — nothing can be .active).
