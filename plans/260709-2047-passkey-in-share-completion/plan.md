# Passkey-in-Share Completion

## Problem

Sharing a login that has an associated passkey does not surface / grant the passkey end to end.
Three surfaces, uneven support (all verified on-device + code):

1. **Owner CREATE** (`ShareAccessSheet`) — passkey rows now show (already fixed: switched
   `itemPasskeys` to `repository.passkeys`, the decrypted source the detail screen uses, dropping
   the live-Vault-Key dependency that made rows vanish). Grants via `confirmFingerprintAndPublish`.
   Default OFF. **Done, shipped on branch `fix/participant-escrow-stale-vault-key`.**
2. **Owner EDIT** (`ShareRecipientDetailSheet`, the "Share details" sheet) — **no passkey rows at
   all**; only iterates `item.fields`. Worse, `applyCapabilities`/`sendUpdateNow` republish the
   grant WITHOUT `displayPasskeys`, passkey `sharedValues`, `deviceScope`, or `allowedDevices` —
   silently **stripping passkeys and reverting single-device → multi**. Clear bug.
3. **Recipient (device B)** — shared passkeys work via **AutoFill/QuickType** (projection →
   `cachePasskeys` → `ASPasskeyCredentialIdentity` → extension signing). The **in-app** shared-item
   detail shows NO passkey section (`ItemDetailScreen` gates `ItemPasskeysSection` on
   `sharedOrigin == nil`; `buildItem` strips passkey slots). Gap, not a deliberate decision
   (decision 260705 only governs QuickType registration).

Net user symptom: an existing share (created pre-fix) has no passkey in its grant, so B shows
nothing and the edit sheet can't add it.

## Approach

Bring EDIT to parity with CREATE (and stop it degrading the grant), then optionally give the
recipient in-app visibility. Extract the owner's "build passkey display + sealed secrets + resolve
device scope + publish grant" logic into one reusable path so CREATE and EDIT can't drift again.

## Phases

| # | Phase | Status | File |
|---|-------|--------|------|
| 1 | Owner edit-share passkey management + stop grant strip | ✅ done (compiles) | [phase-01](phase-01-owner-edit-share-passkey-management.md) |
| 2 | Recipient in-app shared-passkey display | ✅ done (compiles) | [phase-02](phase-02-recipient-inapp-passkey-display.md) |
| 3 | Tests + device QA | ⚙️ unit done (5 composer tests pass); device QA pending | [phase-03](phase-03-tests-and-device-qa.md) |

## Implemented (as built)

- **Phase 1** — `SharedGrantComposer` (new) centralizes fields+passkeys+device-scope+display grant
  assembly; both `ShareAccessSheet.confirmFingerprintAndPublish` (create) and
  `ShareRecipientDetailSheet.applyCapabilities` (edit) publish through it. Edit sheet now shows
  `PasskeyCapabilityRow`s, seeds passkey caps + device scope from the live grant, and republishes
  preserving passkeys + single/multi scope (fetches the participant profile). Hand-over
  confirmation added. `sendUpdateNow` unchanged (passkeys don't change on a value push).
- **Phase 2** — `SharedItemPasskeysSection` (read-only, metadata only) on the recipient's shared
  item detail, driven by `SharedItemsProjection.sharedPasskeys(itemID:)`. Private key stays
  AutoFill-only (decision 260705 intact).
- **Phase 3** — `SharedGrantComposerTests` (5: device-scope multi/empty/first-enrolled; passkey
  artifacts by mode) green; full suite green. On-device 2-account QA pending.

## Key decisions (ADR)

- **ADR-P1**: EDIT must republish the grant with the SAME shape CREATE produces — passkeys +
  device scope preserved. Re-derive `allowedDevices` from the recipient's live participant profile
  (`fetchParticipantProfile`) keyed by the loaded grant's `allowedDeviceKeyBindings`; empty
  bindings ⇒ multi-device. Never silently downgrade scope.
- **ADR-P2**: DRY — extract a single `SharedGrantComposer` (or a method on `ApprovalShareService`)
  used by both `ShareAccessSheet.confirmFingerprintAndPublish` and
  `ShareRecipientDetailSheet.applyCapabilities`, so passkey/device handling lives in one place.
- **ADR-P3**: Recipient in-app display is READ-ONLY metadata (relying party / username), driven by
  the existing `cachePasskeys` / `SharedPasskeyEntry` — no new decryption, no store writes; the
  private key stays AutoFill-only (respects decision 260705).
- **ADR-P4**: Passkey capability stays OFF by default in both CREATE and EDIT (least exposure).

## Non-goals

- Changing the recipient AutoFill/signing pipeline (works).
- Storing shared passkey secrets into the recipient's `PasskeyVault` (deliberately not done).
- Any change to the crypto kernel / grant wire format (v2 already carries passkeys).

## Dependencies

- Phase 1 needs the shared composer before EDIT can seal correctly.
- Phase 3 after 1 (+2 if taken).
