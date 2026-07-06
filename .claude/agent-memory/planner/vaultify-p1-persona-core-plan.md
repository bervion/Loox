---
name: vaultify-p1-persona-core-plan
description: Location + shape of the P1 Persona Core plan (PersonaRecord first-class, seed/migrate, rebind P0 seams)
metadata:
  type: project
---

P1 — Persona Core plan lives at `plans/260706-1238-persona-spaces-relay-proposal-v3/p1-plan.md` + `p1-phase-P1.1/P1.2/P1.3.md`.

**Fact:** 3 sequential phases — P1.1 model/store/CloudKit sync (new `PersonaRecord` @Model + `VaultPersona` CK type, mirror `FolderRecord`/`VaultFolder`); P1.2 repo seed/migrate + invariants + `activePersona` resolver + rebind `primarySpaceId`; P1.3 switcher UI + rebind `PersonaID.placeholder` call sites.

**Why:** builds on [[vaultify-p0-space-hardening-plan]] seams. Canonical decisions in `proposal-v3-locked-decisions.md` (D12 single-pointer `primarySpaceID`; D7 selection local-not-synced; INV-R03 isolationPolicy stored P1 / consumed P2).

**How to apply — key design calls (autonomous defaults, may need user ack):**
- **default persona** = synced converged plaintext `isDefault` flag (mirror `isDefaultIdentity`/`normalizeDefaultIdentity`); **active persona** = device-local `SettingsStore.activePersonaID` (mirror `selectedPaymentCardId`), NOT synced. Resolver: active ?? default.
- **Fixed bootstrap id** `Persona.bootstrapPersonalID` for the auto-seeded Personal persona → multi-device seeds collide on ONE record id (LWW merge), so NO duplicate-merge pass needed (unlike folders' `mergeDuplicateSeedFolders`).
- Seed runs in `reload()` via `ensurePersonaExists()` (covers new + existing installs; `OnboardingFlow` untouched, DRY).
- `isDefaultIdentity` stays (AutoFill reads it); persona `primaryProfileItemID` = soft link.
- `Folder.personaId` threaded + writer added but NOT auto-populated in P1 (avoid re-seal churn; `primarySpaceID` is the authoritative link).
- Deferred to P2 (YAGNI): avatars, edit/delete UI + delete guard, isolationPolicy editor + consumption (`allSpacesSearchAllowed` gating).
- Inject `SettingsStore` into `VaultRepository` (was store+session only) — 2 constructor call sites.
