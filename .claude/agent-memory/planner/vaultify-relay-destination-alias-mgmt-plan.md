---
name: vaultify-relay-destination-alias-mgmt-plan
description: Plan for Relay Destination + Alias Mgmt UX — per-alias real-email via rotateDestination, write-back, alias detail screen
metadata:
  type: project
---

Plan `plans/260706-1238-persona-spaces-relay-proposal-v3/reldest-*.md` (branch `feat/relay-destination-alias-mgmt`). Relay is LIVE (P0–P4B merged). Extends [[vaultify-persona-relay-proposal-v3]].

**Why:** backend handoff — relay now forwards each alias to a per-alias REAL email set via `rotateDestination` (kind=3, already signed+vector-frozen; body carries `destination`). "Create alias" is now TWO calls: createAlias(mint) → rotateDestination(set email). Not zero-knowledge → privacy-policy disclosure needed.

**How to apply (5 phases, sequential chain):**
- P1 destination plumbing: `destinationEmail(for persona:)` = profile card's real `.email`; `send` gains `destination`; `activate` = createAlias→rotateDestination→active. Added `backendMinted: Bool?` to EmailAliasSecret (growable) to make activate RESUMABLE (avoid orphan re-mint on mint-then-rotate failure); disable/delete must fire backend when `backendMinted || active`.
- P2 write-back: activated alias appended as "Private email" `.email` field — persona-tier→profile card (AFTER real Email so `username(from:)` still returns real), per-site→bound login. `fieldLabelText`=LocalizedStringKey so "Private email" localizes (add VI).
- P3 change-email: `RelayService.updateDestination(for:to:)` re-rotates persona's ACTIVE aliases sequentially (idempotent, partial-failure reports n/m). Trigger = explicit "Forwards to" control, NOT item-edit hook (documented gap).
- P4 `AliasDetailScreen`: address/status/tier/binding + editable "Forwards to" + irreversible Delete confirm.
- P5 wiring: guard create when persona has no email (`.missingDestination`), rows→detail.

**LOCKED decisions:** (1) destination = owning persona's identity-card Email field; (2) write alias back as "Private email" field; (3) destination is per-persona. Autonomous call: `backendMinted` checkpoint field for resumable activate.

Live path (network) = device QA only; unit-test destinationEmail selection, write-back idempotency/ordering, body shape.
