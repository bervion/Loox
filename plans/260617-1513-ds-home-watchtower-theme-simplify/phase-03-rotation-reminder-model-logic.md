---
phase: 3
title: Rotation reminder model & logic
status: completed
priority: P2
effort: 5-7h
dependencies: []
---

# Phase 3: Rotation reminder model & logic

## Overview

New **password-rotation reminder** feature (user chose "bám spec tối đa"). Port the DS
`rotationStatus` / `attentionReason` logic (`Design System/ui_kits/ios-app/app.jsx:42-57`), add the
backing metadata, and expose a "Nhắc đổi mật khẩu" control in the item editor. Powers Home's
"Cần chú ý" section (Phase 5) **and OS local notifications** (confirmed Session 1 — see updates below).

## Requirements

- Functional: per-item rotation cadence (off / 15 / 30 / 90 days) + last-changed timestamp;
  derive overdue/soon/stale state; an "attention" list = rotation issues + weak passwords.
- Non-functional: new fields are **plaintext columns** (cadence + timing, not secret content) — like
  `lastUsedAt`/`useCount`; sealed `ItemSecret` + codec **unchanged**. `nonisolated` logic.

## Key Insights

- Follows the established pattern: low-sensitivity metadata = plaintext columns on `ItemRecord`
  (`ItemRecord.swift:19-27`), keeping the AES-GCM payload + codec untouched (CloudKit-safe).
- `passwordChangedAt` updates only when the decrypted password value actually changes on save
  (compare old vs new on the unsealed `VaultItem` in the repo save path).
- DS logic: `due = rotateDays - daysSinceChange`; `due<=0` overdue (destructive), `due<=5` soon
  (warning); no cadence + `daysSinceChange>=180` ⇒ stale (warning). `attentionReason` = rotation-not-ok,
  else weak (`score<=1`).

## Architecture

`ItemRecord` (+`rotateDays:Int=0`, `passwordChangedAt:Date?`) → surfaced on decrypted `VaultItem` →
`RotationStatus` value type (pure) → `VaultRepository.itemsNeedingAttention()` (rotation ∪ weak).

## Related Code Files

- Modify: `VaultifyCore/Store/ItemRecord.swift` — add `var rotateDays: Int = 0`, `var passwordChangedAt: Date?`.
- Verify/modify: `VaultifyCore/Store/VaultStore.swift` — SwiftData lightweight migration (defaulted new attributes add cleanly); confirm no manual schema break.
- Modify: `VaultifyCore/Models/VaultItem.swift` — carry `rotateDays` + `passwordChangedAt` on the decrypted model so UI/editor read them.
- Create: `VaultifyCore/Models/RotationStatus.swift` — `nonisolated` enum/struct + `rotationStatus(rotateDays:passwordChangedAt:now:)` + `attentionReason(...)`.
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift` — set `passwordChangedAt` on password change at save; add `itemsNeedingAttention()` (sorted: overdue → weak → soon → stale).
- Modify: `Vaultify/Features/ItemEditor/ItemEditorScreen.swift` — "Nhắc đổi mật khẩu" `Picker`/segmented (Tắt/15/30/90); persist `rotateDays`.
- Create: `VaultifyTests/RotationLogicTests.swift` — boundary cases (due=0, due=5, due=6, stale 180, no-cadence).

## Validation Session 1 updates
<!-- Updated: Validation Session 1 - add OS local notifications for rotation -->

- **Add OS local notifications** for overdue rotation (additive to the in-app "Cần chú ý" surfacing).
  - Create `Vaultify/Services/RotationNotificationService.swift` (UNUserNotificationCenter): schedule a
    local notification when an item becomes due; reschedule on password change / cadence change; cancel
    on cadence=off or item delete/trash.
  - **Defer the authorization prompt** until the user first sets a rotation cadence (privacy-app
    friendly — never prompt at launch). Handle denied authorization gracefully (in-app surfacing still
    works). Local notifications need no Info.plist usage string; verify the auth flow on device.
  - Add success criteria: schedule/reschedule/cancel correctness; denied-permission path safe; no
    notification content leaks the item's secret (title only, e.g. "Đến hạn đổi mật khẩu: {item}").

## Implementation Steps

1. Add the two columns to `ItemRecord` (defaults keep migration lightweight); thread through
   `VaultItem` + the seal/unseal mapping (metadata only — not into `ItemSecret`).
2. Create `RotationStatus.swift`: pure port of the DS logic; `daysSinceChange` from
   `passwordChangedAt ?? createdAt`. Expose `state` (ok/overdue/soon/stale), `tone`, label key, short key.
3. Repo: in the save path, if decrypted new password ≠ old password, set
   `passwordChangedAt = .now`; on create, set `= createdAt`. Add `itemsNeedingAttention(limit:)`.
4. Editor: add the rotation segmented control bound to `rotateDays`; localized label + helper text.
5. Tests: cover overdue/soon/ok/stale boundaries + "no cadence, fresh = ok".
6. `tuist generate --no-open` → compile + `make test DEST=...`.

## Todo List

- [ ] `rotateDays` + `passwordChangedAt` columns (defaulted, lightweight migration)
- [ ] Threaded onto decrypted `VaultItem`
- [ ] `RotationStatus` pure logic ported
- [ ] Repo sets `passwordChangedAt` on real password change + `itemsNeedingAttention()`
- [ ] Editor rotation control persists cadence
- [ ] RotationLogicTests green; `make check` passes

## Success Criteria

- [ ] Setting a 30-day cadence then aging `passwordChangedAt` produces overdue/soon correctly.
- [ ] Changing a password resets `passwordChangedAt`; editing other fields does not.
- [ ] Codec/seal format unchanged (existing vault opens; existing tests pass).

## Risk Assessment

- **SwiftData migration**: defaulted scalar + optional add is lightweight; if the store uses a manual
  schema/version, bump it. Verify on an existing seeded vault — do not data-loss.
- **CloudKit**: new plaintext columns mirror `useCount`/`pinned` precedent; confirm sync mapping if the
  CK schema enumerates columns.

## Security Considerations

`rotateDays`/`passwordChangedAt` reveal cadence + change timing only — acceptable as plaintext (same
class as `lastUsedAt`). Never put password values or derived strength into plaintext columns.
