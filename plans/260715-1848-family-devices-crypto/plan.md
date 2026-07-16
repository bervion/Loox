# Family full-group sharing + Devices key-rotation revoke — execution plan

Status: **Planned, execution-ready (v2, post-review).** Two security-critical crypto/transport projects that finish the Profile refactor's deferred features. Neither is verifiable headlessly (2-account / 2-device flows), so each ships **phase-by-phase behind a flag, gated on a device/account test matrix** — the F2 red-team (PR #106) proved a blind one-shot produces architecturally wrong crypto.

Grounding: this plan's two detailed docs + the crypto-surface scout `plans/reports/scout-260715-1955-crypto-surface-map.md` (all crypto claims verified there, file:line) + the design docs under `plans/260715-1630-profile-refactor/`.

## The two projects
| # | Project | Detailed plan | Core change | Can I verify? |
|---|---------|---------------|-------------|---------------|
| A | **Family full-group** (share a Space, manage, revoke) | `family-group-transport.md` | Namespace grant/display/field records **per `grant.id` within a zone** (N logins, one ceremony); v3 HPKE binding; live-membership reconciler; field-instance safelist | Compile + unit; **end-to-end needs 2 iCloud accounts** |
| B | **Devices revoke** (real key rotation) | `devices-key-rotation.md` | Rotate the 32-byte Vault Key: **epoch authority + old-epoch write rejection**, re-seal the **full ciphertext inventory** (incl. device-local surfaces), dual-key window + compact journal, re-wrap KEKs, possession-proof device re-provision, regenerate Emergency Kit | Local re-seal + kernel is **unit-testable**; **multi-device + crash paths need 2 devices** |

## What the review + scout changed (v1 → v2)
- **Execution order: no interleaving.** v1 ran B1 → A → B2-B4, leaving the crown-jewel crypto half-built while context-switched. v2: **finish one epic fully (contract-freeze → all phases → security review) before the other.** Recommended **A first, then B** — A reuses proven HPKE (no new key primitive, under-share fails safe), so completing it end-to-end proves the phased flag-gated testing loop on lower stakes before the highest-risk B rotation. *(B-first is acceptable if device-revoke is more urgent — confirm.)*
- **Each epic gains a contract-freeze phase (A0 / B0)** — freeze identities, schemas, transcripts, state machine, and inventory before any code, so the 2-party/2-device work builds on frozen contracts.
- **B's scope corrected (the big one):** rotation is not "re-encrypt ItemRecords." It must (1) change the authoritative **write epoch** and **reject old-epoch mutations** from a removed device, and (2) re-seal **12+ non-ItemRecord surfaces**, several **device-local** (attachments, passkeys, shared caches, UI-state) → rotation runs on **every kept device**, not server-side. Full inventory + insertion point (`CloudSyncService.pull()` `:156-168`) are in the B doc.
- **A/B are crypto-decoupled** (scout note 4): published sharing grants carry no VK-derived material, so a VK rotation does not invalidate shares. The two epics don't entangle.

## Execution model (the "best" way for unverifiable crypto)
Each project runs as ordered phases. **Every phase that touches transport or the key ships behind a compile/runtime flag, with a written test checklist you run before the flag flips on.** I implement a phase → `make check` + unit/KAT tests → you run its device/account checklist → I fix from your logs → next phase. No phase merges to the default path until its checklist passes. `main` stays stable throughout (additive + flagged); existing per-item sharing and the single-key vault keep working untouched.

**Order (v2):** A0 → A1–A4 (with your 2 accounts) → `/ak:security` review of A → B0 → B1 (unit/KAT, headless) → B2–B5 (with your 2 devices + crash injection) → `/ak:security` review of B.

## Cross-cutting invariants (must hold every phase)
**Family (A):**
- **INV-FAM-01** — cleanup by authenticated grant metadata, never recordName prefixes.
- **INV-FAM-02** — every field envelope bound (v3) to zone, persona, owner key, recipient, grant, item, field, field kind, capability, device key.
- **INV-FAM-03** — a Space share is live-membership, not snapshot; V1 does not mix.
- **INV-R03** — persona isolation: a zone binds `ownerPersonaId`.
- **INV-08** — hand-over irreversible → field-instance safelist; cached plaintext not revocable (UI states it).

**Rotation (B):**
- **INV-ROT-01** — old-epoch writes rejected after new-epoch commit (E stays read-only for migration fallback).
- **INV-ROT-02** — previous key is decrypt-only; new writes seal under current.
- **INV-ROT-03** — device adoption requires proof of possession of the new key, signed by the pinned device key.
- **INV-ROT-04** — at most one rotation active.
- **INV-ROT-05** — raw Vault Keys never sync; only device-targeted, public-key-sealed envelopes transport.
- **INV-ROT-06** — rotation revokes future/current-vault access; it does not erase historically cached plaintext or old ciphertext.

**Both:** localized EN+VI; design-system tokens; `make check` green each phase.

## Open decisions (confirm before A0 / B0)
1. **Execution order** — A-first (recommended) or B-first?
2. **Space-share semantics** — live-membership (recommended; needs the reconciler) or snapshot (cheaper; share exactly what exists at ceremony time)? Drives A's scope (DEC-FAM-01).

## Definition of done
- **A**: an owner shares a Space to a member in one ceremony; the recipient projects **all** logins; owner revokes per-member and per-item; two-account matrix passes; `/ak:security` clean.
- **B**: an owner rotates the key from Devices → a revoked device can no longer decrypt future ciphertext **and** its old-epoch writes are rejected; kept devices re-adopt (possession-proof) without data loss across the full inventory; crash/offline/race matrix passes; Emergency Kit regenerated; `/ak:security` clean.

## Risks / honesty
- Both are large and touch the crown-jewel crypto. Estimated multi-session even with the loop; B is the highest-risk work in the app.
- I cannot sign off correctness without your device/account testing between phases — that gate **is** the plan, not an afterthought.
