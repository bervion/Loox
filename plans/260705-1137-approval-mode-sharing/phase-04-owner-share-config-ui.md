---
phase: 4
title: "Owner share-config UI"
status: completed # 2026-07-05 — see Implementation Status; device QA rides Phase 8
priority: P1
effort: "1.5d"
dependencies: [3]
---

# Phase 4: Owner share-config UI

## Overview
Owner entry point: from item detail, open a share-config sheet to pick a **looked-up recipient** and set
**per-field capability**, confirm the one-time trust fingerprint, then create the grant + CKShare. Gated
by notification permission (ADR-2) and iCloud account availability.

## Requirements
- Functional: new "Share access" action (distinct from the existing non-secret `ShareLink`); per-field
  capability picker — **TOTP → none/askEachTime; password/username/url/text → none/shared** (password
  ask-each-time is NOT offered); recipient chosen by iCloud identity (not a bearer URL); one-time
  fingerprint confirmation UI; "Shared with N" state.
- Non-functional: DS tokens, PolarisIcons, 44pt, localized EN+VI; fail-closed on missing notification
  auth or `accountStatus != available`; no plaintext secret in any invite artifact.

## Architecture
- **Entry:** keep the current `ShareLink` (URL/title) in `ItemDetailScreen`; add a separate "Share
  access…" action opening `ShareAccessSheet`.
- **`ShareAccessSheet`:** recipient entered by **email/phone → `CKUserIdentity` lookup → programmatic
  add-participant** (Validation §4, NOT `UICloudSharingController`) + field list. Each row's picker options
  are **capability-constrained by field kind** (Phase 2 type): TOTP rows show none/askEachTime; other
  rows show none/shared. Default policy = least exposure (everything `none`; user opts in). Passkey fields
  shown disabled ("Not shareable yet").
- **Gates:** entering the sheet requires notification authorization (else prompt/deny per Phase 1) and an
  available iCloud account; block with a clear localized message otherwise.
- **Create + fingerprint:** on confirm → `ApprovalShareService.share(item:capabilities:to:)` (Phase 3);
  present the `TrustFingerprint` (Phase 2) for A and B to compare once (ADR-4) before the grant is trusted.
- **State:** `SharingStore` (@Observable) tracks created shares per item → "Shared with N" + Phase 7.

## Related Code Files
- Create: `Vaultify/Features/Sharing/ShareAccessSheet.swift`, `FieldCapabilityRow.swift`,
  `TrustFingerprintView.swift`, `SharingStore.swift`
- Modify: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` (add "Share access" action)
- Reference: `Vaultify/DesignSystem/Tokens/*`, `Components/*`, `ItemDetail/DetailFieldRow.swift`,
  `PolarisIconCatalog.swift`, `Vaultify/Resources/Localizable.xcstrings`

## Implementation Steps
1. `FieldCapabilityRow`: kind-constrained picker (DS tokens + Polaris icons).
2. `ShareAccessSheet`: recipient lookup + field list + least-exposure defaults + notification/account gate.
3. Add "Share access…" action to `ItemDetailScreen` (separate from `ShareLink`).
4. Confirm → `ApprovalShareService.share(...)`; present `TrustFingerprintView` compare step.
5. `SharingStore` per-item share tracking → "Shared with N".
6. Strings to `Localizable.xcstrings` EN+VI (titles `.inAppLocalized`, runtime `appString()`).
7. `make check`; verify light/dark/Reduce-Transparency, 44pt.

## Success Criteria
- [ ] Owner shares by iCloud identity (no bearer URL), sets per-field capability, confirms fingerprint.
- [ ] Password can only be none/shared; TOTP only none/askEachTime; passkey non-shareable.
- [ ] Sheet blocked (clear message) when notifications denied or iCloud unavailable.
- [ ] Fully localized EN+VI; DS-compliant; existing `ShareLink` unchanged.

## Implementation Status — 2026-07-05

**Complete (on feat/approval-mode-sharing, uncommitted).** NEW `Vaultify/Features/Sharing/`:
`ShareAccessSheet.swift` (step machine: fail-closed gate → config → create → waiting/poll → fingerprint
→ publish → done), `FieldCapabilityRow.swift` (kind-constrained picker; guard2 + attachments disabled),
`TrustFingerprintView.swift`, `SharingStore.swift` (device-local registry). MODIFIED: ItemDetailScreen
("Share Access…" menu entry, distinct from ShareLink), AppEnvironment (`sharingStore`),
Localizable.xcstrings (32 entries EN+VI — reviewer script-verified 100% incl. byte-exact interpolation
keys). 161/161 tests; iOS+macOS green.

**Review applied** (`plans/reports/from-code-reviewer-260705-phase4-share-config-ui-report.md` —
0 Critical, secret hygiene + fingerprint-before-grant verified): H1 poll leak → structural
`.task(id: pollingZoneName)` with bounded backoff (3s→10s cap, ~10min budget), identity hoisted;
H2 orphan zones → pending `ItemShareRecord(fingerprintConfirmed: false)` persisted at create, retry to
the same recipient reuses its zone via `createShare(existingZoneName:)` ("Pending" state now real);
M2 re-entrancy guard; M3 `LocalizedError` on `ApprovalShareService.Failure` (EN+VI); L: blocked view got
"Check Again" re-check, item-gone → failed state, Icons.shield constant, prominent 44pt buttons.

**Accepted/known:** `approvalModeEnabled` flips on at create (intentional — the accept push must be
receivable before the grant exists; pending record accounts for it). Orphan zones for a DIFFERENT
abandoned recipient → Phase 7 GC. `epoch: 1` hardcoded until Phase 7 revocation. Duplicate share to the
same email is prevented by the resume path; "Shared with N" badge on the detail screen itself deferred
to Phase 7 share management.

## Risk Assessment
- <!-- Updated: Validation Session 1 - programmatic add-participant, not UICloudSharingController -->
  Programmatic `CKUserIdentity` lookup + add-participant at iOS 17.6 — verify the lookup-by-email/phone
  API against the 17.6 SDK; handle "recipient not an iCloud user / not found" explicitly.
- Copy must say "encrypted approval transport", not "iCloud sync" (Validation §2), and explain the
  one-time fingerprint step briefly.
