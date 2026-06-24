# Red-Team + Validate — Identity & Profile Plan Review

**Date:** 2026-06-24 10:08 · **Plan:** `plans/260624-0959-identity-profile-feature/` · **Reviewer:** ck:plan (combined gate)

Combined adversarial (red-team) + critical-questions (validate) pass on the 4-phase plan.
Sacrifice grammar for concision.

## Severity legend
🔴 blocker (fix before cook) · 🟠 should-fix · 🟢 minor/note · ❓ needs user decision

---

## 🔴 / ❓ F1 — Sync convergence by `updatedAt` is BROKEN for default changes
**Where:** Phase 2 `normalizeDefaultIdentity()` conflict tie-break; spec said "normalize to 1 default by
latest `updatedAt`".
**Problem:** `setDefaultIdentity` is column-only and (per plan) does NOT bump `updatedAt`. So `updatedAt`
reflects *content edits*, not *when the default flag changed*. CloudKit syncs each identity as a separate
record (whole-record last-writer-wins). Two devices changing default between syncs → can land on
**double-default**; normalize then picks the winner by `updatedAt`, which is unrelated to who chose the
default last. Result: the surviving default is effectively arbitrary, not "last choice".
**Why it matters:** the convergence guarantee the user asked for does not hold.
**Options (NEEDS DECISION):**
- (a) **[recommended]** `setDefaultIdentity` bumps `updatedAt` (column write, no re-seal). Deterministic:
  last chooser wins. Cost: identity floats up "Recently Modified" on Home (rare action; acceptable).
- (b) Dedicated synced column `defaultIdentitySetAt: Date?` as tie-break. Cleanest semantics, doesn't
  pollute recents; cost: +1 column, +1 push/pull line.
- (c) Accept arbitrary winner on conflict; document non-determinism. Cheapest; weakest.

## 🔴 F2 — Existing users (TestFlight) get NO identity and NO onboarding
**Where:** Phase 3 only seeds at fresh onboarding; existing users already have `onboardingCompleted=true`.
**Problem:** After update, existing users have 0 identity items → 0 default → Profile/Home avatar has
nothing. Onboarding never re-runs.
**Mitigation (partly already present):** `normalizeDefaultIdentity` auto-promotes IF ≥1 identity exists →
users who *manually* created an `.identity` get a default for free. Users with **zero** identities are
stranded.
**Fix:** Phase 4 must add a **zero-identity empty state** (Profile + Home avatar fallback) with a
"Create your identity" CTA routing to the identity editor/seed. This also covers post-import / post-restore
zero states. Make explicit in Phase 4 + Phase 2 (normalize must NOT fabricate an identity silently).

## 🟠 F3 — Orphaned avatar blobs on permanent delete
**Where:** Phase 4 avatar keyed `Avatars/<itemId>.blob`; `delete()` / `emptyTrash()` never clean it.
**Problem:** permanently deleted identity leaves an encrypted avatar blob on disk forever (disk bloat +
residual personal data). **Fix:** delete avatar blob in the permanent-delete path. Add cleanup hook.

## 🟠 F4 — Avatar scope: device-local (not synced, not in backup)
**Verified:** attachments are NOT in `CloudSyncService` (device-local); `VaultBackup` import returns items
only. So avatars won't sync across devices nor survive export/restore. **Decision:** accept device-local
avatar (consistent w/ attachments) and **document** it (Profile shows letter-avatar fallback on other
devices). If cross-device avatar is wanted → separate future work. (Recommend accept; flag to user.)

## 🟢 F5 — `Phone` field kind
**Where:** Phase 1 `.identity` template "Phone(number/text)". `.number` → numberPad can't type `+`/spaces.
**Fix:** use `.text` (no autocorrect) for Phone; no `.phone` kind exists. Minor.

## 🟢 F6 — Stray `isDefaultIdentity` on non-identity items
`setDefaultIdentity` should assert/guard `item.category == .identity` so a stray flag can't be set on a
login. `defaultIdentity`/normalize already filter by category (defensive), so impact is low. Add guard.

## 🟢 F7 — `normalize` write-amplification / reentrancy
Confirmed acceptable: normalize runs at end of `reload()`, writes only when inconsistent, patches `items`
in place (no nested reload). Keep the no-reload contract; covered by Phase 2 tests. Note for implementer:
do not call `reload()` inside normalize.

## Validate — unspecified assumptions resolved / to pin
- **V1 Onboarding step placement:** put `.name` right after `.create` (vault unlocked → repo.add works).
  Pin in Phase 3. ✅ feasible.
- **V2 Re-onboarding after recovery** (`onboardingCompleted=false`): Phase 3 already guards (skip seed if
  `activeIdentities` non-empty). Keep.
- **V3 Per-field copy on protected fields** (ID number): copy allowed; reuse ItemDetail reveal+copy path
  honoring `clipboardClearSeconds`. Pin in Phase 4.
- **V4 Default switcher when 1 identity:** hide switcher. Trivial; note in Phase 4.
- **V5 Editing default via `ItemEditorScreen`** preserves marker — `update()` doesn't touch the column. ✅.
- **V6 CloudKit map untestable in unit** — accept; verify by push/pull symmetry + code review. ✅.
- **V7 `make test` needs concrete sim UDID** (per project memory) — note for cook.

## Decisions (RESOLVED by user 2026-06-24)
1. **F1 sync tie-break = (b) dedicated `defaultIdentitySetAt: Date?` column.** Winner:
   `max(defaultIdentitySetAt ?? .distantPast)` → tie `max(updatedAt)` → tie `max(createdAt)`.
2. **F4 avatar = sync cross-device.** Implemented as ≤256px JPEG, AES-GCM sealed, stored in new
   `ItemRecord.avatarSealed: Data?` column (rides item CKRecord, zero-knowledge). **F3 auto-resolved**
   (column dies with record → no orphan; the device-local AttachmentStore-blob approach dropped).

## Applied to plan (safe, non-reversing edits)
- Phase 1: Phone → `.text` (F5).
- Phase 2: normalize promotes only if ≥1 identity, never fabricates; `setDefaultIdentity` asserts
  `.identity` (F6); explicit no-reload contract (F7).
- Phase 4: zero-identity empty state + "Create identity" CTA (F2); avatar blob cleanup on permanent
  delete (F3); pin V3/V4.

## Open questions
- None. F1/F4 resolved; all findings applied to phases 1/2/4.
