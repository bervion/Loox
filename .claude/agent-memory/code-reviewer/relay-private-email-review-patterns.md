---
name: relay-private-email-review-patterns
description: Private Email relay review traps - surface-sweep misses for failure copy, escrow overwrite CAS, principal-scoped backend state, persona "identity" copy collision
metadata:
  type: project
---

Learned reviewing PR #216 (reinstall leaves an unopenable RelayPrincipalEscrow, 2026-09-28).

- **Surface sweep for failure affordances.** When a new alert button is wired to N relay-failure surfaces, grep EVERY renderer of the copy (`.userTitle`, `.userMessage`, `verification.outcome`), not just the RelayService.Failure catch sites. `PrivateEmailIntroSheet` owns its own `ForwardingInboxVerification` + plain `.alert` and is the FIRST signed relay call in a fresh vault (item editor → `PrivateEmailGate.unverifiedDestination` → intro sheet, because `destinationRoutingRequiresVerification = true`). #216 missed it.
  **Why:** the missed surface was the main path for the bug being fixed.
  **How to apply:** for any relay UX change, list surfaces by grepping the copy renderers.
- **Escrow overwrite should be CAS, not blind.** Precedent: `ParticipantEscrowService.regenerateEscrow(reusing:)` saves the FETCHED record with `.ifServerRecordUnchanged`, and on collision adopts if it opens. A fresh `CKRecord` + `.allKeys` overwrites whatever landed after the re-check (same-vault concurrent replace → server/Keychain-cache divergence).
- **Singleton escrow vs per-vault principal.** The escrow is one record per iCloud account, but the principal is "one per vault". Two live vaults on one account (sync off) → replacement ping-pong, each destroying the other's only durable copy (other device survives only via its ThisDeviceOnly Keychain cache). Structural fix = per-vault record name (HMAC(vaultKey, label)).
- **Principal-scoped backend state.** `verified_destinations` is `UNIQUE(principal_id, destination_hash)`; genesis happens only on createAlias (`public_key` sent only then). A new principal leaves local `relayDestinationID`/`.verified` inboxes stale, and verified inboxes hide the Confirm action (dead end). Aliases minted by the old principal cannot be disabled/deleted (local delete runs only after the backend send). Entitlement `relay_principal` binding → `binding_conflict` once enforcement is on.
- **Copy collision.** EN "identity" / VI "danh tính" = Persona ("Create identity" = "Tạo danh tính"); JA uses プロフィール. The Private Email principal must not be called a bare "identity" on a button.

Related: [[approval-transport-review-patterns]], [[vaultify-localization-catalog-convention]]
