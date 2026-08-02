---
title: "Phase 1: Correctness and Compatibility Guardrails"
status: todo
---

# Phase 1: Correctness and Compatibility Guardrails

## Outcome

Close current secret-disclosure/data-loss paths and freeze compatibility contracts before new
types enter production. This phase is independently releasable as Release A1.

## Requirements

- [ ] Protected multiline values use the same fixed-mask, reveal, copy, and re-auth path as other secrets.
- [ ] Shared envelopes preserve category plus sensitivity/protection semantics; missing metadata fails closed.
- [ ] Quick Link and Quick View absolutely deny key material/API/signing secrets in v1; Approval/Space sharing use explicit resolver policy, never masking as consent.
- [ ] Supported-schema unknown IDs do not disappear or become login; unsupported schema remains concealed
  read-only with authenticated encrypted recovery rather than unsafe save/share.
- [ ] Decode failures are quarantined and surfaced as recoverable records instead of silently skipped.
- [ ] Sensitive iOS clipboard entries are local-only and expire; private key export is never a default row action.
- [ ] Existing Safari invariant remains: `getFillPayload` is the only native command returning fill values.

## File Inventory

- Modify `Vaultify/Features/ItemDetail/DetailFieldRow.swift` and shared reveal components.
- Modify `VaultifyCore/Sharing/SharedDisplayEnvelope.swift`,
  `Vaultify/Services/Sharing/ApprovalShareService.swift`, and
  `Vaultify/Services/Sharing/SharedItemsProjection.swift`, plus `SharedGrantComposer` and all
  Quick Link/Quick View/Approval/Space publish and republish callers.
- Modify `VaultifyCore/Models/ItemCategory.swift`, `VaultifyCore/Models/VaultItem.swift`,
  `Vaultify/Data/Repositories/VaultRepository.swift`, and portable-backup decode paths.
- Modify `VaultifyCore/Platform/PlatformPasteboard.swift`.
- Add focused model, repository, sharing, detail-rendering, and integration-contract tests.
- Do not change Safari command surface or expose any developer-secret payload.

## Implementation Steps

1. Refactor detail rendering so `protected`/secret policy is evaluated before `FieldKind`; multiline
   content uses a masked placeholder until authorized and never initializes Markdown with plaintext.
2. Add backward-compatible optional shared-field policy metadata and populate envelope `category`.
   Inventory `SharedGrantComposer` and every publish/republish caller. Negotiate receiver protocol
   capability; policy-sensitive fields are unavailable to an old/non-negotiated receiver. Treat
   missing/unknown roles as masked and never `.login`-fillable.
3. Replace Quick Link and per-item Approval field-kind denylists with a transitional explicit allowlist
   that Phase 2 later moves into the resolver. Existing
   login sharing stays intentional; private keys, tokens, passphrases, and artifacts are absent from
   Quick Link/Quick View in v1 even when only `protected`. Approval/Space policy separately allowlists
   known roles, requires action-scoped re-auth where permitted, and warns that recipients can retain data.
4. Introduce a lossless unknown-category wire representation or decoding shim. Preserve the raw value
   while mapping presentation to a generic safe fallback.
5. Replace repository `try?/continue` behavior with a quarantine result containing record ID, error
   class, and a recovery UI state. Never log decrypted content.
6. Add `.localOnly` plus expiry to sensitive iOS pasteboard writes. Reveal authorization is one-shot and
   bound to item/field/action; conceal again on timeout, navigation, background, vault lock, or capture
   policy. Remove plaintext temp on dismiss, lock, and launch as containment before Artifact v2.
7. Freeze an exhaustive outbound-surface matrix for all eight current types: detail/AX tree, clipboard,
   export, AutoFill, Safari, Approval/Space/Quick Link/Quick View, backup, CloudKit, search, and telemetry.

## Verification Matrix

- Unit: protected multiline hidden/revealed/copied; unknown category decode/re-encode; envelope vOld/vNew.
- Unit: category and protected policy survive owner-to-recipient projection.
- Compatibility: old sender→new receiver and new sender→old receiver; the latter cannot receive a
  policy-sensitive field without negotiated wire support.
- Unit: Quick Link/Quick View cannot contain SSH/API/signing secrets; Approval/Space obey resolver policy.
- Integration: supported-schema unknown IDs remain editable and preserved; unsupported future schema
  remains visible as read-only recovery and retains original sealed bytes through backup.
- Negative: SSH private key/recovery codes never appear in a view snapshot before reveal.
- Negative: no SSH/custom secret appears in AutoFill identity cache or Safari `getFillPayload`.
- Accessibility: VoiceOver reads “hidden value”, not the underlying value, while masked.

## Risks and Mitigations

- Changing old envelope behavior can affect existing grants: keep optional fields, support old decode,
  and fail closed only for missing security metadata.
- Quarantine UX can alarm users: distinguish corruption, unsupported-newer-data, and transient key failure.
- Clipboard `.localOnly` changes cross-device habits: apply only to sensitive actions and explain once.

## Success Criteria

- [ ] The two current protected-multiline disclosure cases have regression tests.
- [ ] Existing share grants still decode; new grants preserve category and protected policy.
- [ ] No record is silently dropped because of an unknown category.
- [ ] Safari command-contract tests are unchanged and green.
