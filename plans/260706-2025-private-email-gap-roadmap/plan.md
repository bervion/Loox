# Private Email — Gap Roadmap (proposal reconciliation)

Source: app proposal (forwarded 260706) reconciled against `develop` (PR #43 merged, 286/286 green).
Proposal phases A–D + half of F already shipped. This roadmap covers only the real deltas.

## Locked decisions (user, 260706)

- **Cardinality**: drop the 1-persona-alias cap → 0..N "Reusable addresses" per persona, with label.
- **ForwardingInbox**: first-class sealed model NOW (multi-inbox, per-alias selection, default inbox).
- **IA**: feature stays in **Profile** (user's prior decision; overrides proposal's Settings placement).
  Persona detail keeps contextual entry.
- **Scope**: full gap roadmap, auto-mode, 1 PR per phase into `develop`. `main` stays v1.17.0.

## Already satisfied (do NOT redo)

- INV-PE02 two-step provisioning: `backendMinted` checkpoint; address never rendered pre-active.
- SEC-PE01..10, PE12 hold (verified in RelayService/RelayAPIClient/canonical).
- Reply warning, permanent-delete confirm, D4 erase gate, rotate-all idempotent.

## Phases

| # | Phase | File | Status |
|---|-------|------|--------|
| G1 | Naming & copy: "Private Email", Pause/Resume terminology, masked email display | phase-g1-private-email-naming-copy.md | ⏳ pending |
| G2 | ForwardingInbox sealed model + 0..N reusable aliases + alias label | phase-g2-forwarding-inbox-model.md | ⏳ pending |
| G4 | Create Login integration (flagship): suggest → explicit provision → bind → fill | phase-g4-create-login-integration.md | ⏳ pending |
| G3 | Management UI: reusable list, per-alias inbox picker, default inbox, resumable bulk rotation | phase-g3-management-ui-bulk-rotation.md | ⏳ pending |
| G5 | Error mapping polish + Resume Forwarding (**blocked on BE re-enable contract freeze**) | phase-g5-error-mapping-resume.md | ⏳ pending (resume blocked on BE) |
| G6 | AutoFill: existing-alias reuse only; no in-extension provisioning V1 | phase-g6-autofill-alias-reuse.md | ⏳ pending |

Order G4 before G3 per proposal author's priority (Create Login > management dashboard).

## Cross-phase invariants

- INV-PE01/SEC-PE12: strictAnonymous never surfaces/suggests another persona's aliases or real email.
- INV-PE02: alias unusable until mint + destination both succeed.
- INV-PE03: rendering a suggestion never allocates a backend alias.
- SEC-PE01..04: personaID / boundDomain / boundVaultItemID / label never sent to relay.
- New CK record type (`VaultForwardingInbox`) must be added to the prod-schema deploy checklist.

## External dependency

- BE must freeze the disabled→createAlias(same local-part) re-enable contract (response code,
  ownership, destination preserved?) before G5's Resume ships. Draft message sent to user 260706.
