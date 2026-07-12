# Phase 02 — Local notification on acceptance + tap routing to resume stepper

## Context links

- Audit §2-F2/F4, §5-R2
- Local-notification pattern to mirror: `Vaultify/Services/RotationNotificationService.swift:91-112`
- Cold-launch mailbox pattern to mirror: `PendingInviteLink` (`Vaultify/App/AppPushKind.swift:54-60`)
- Depends on: phase 01 (background silent push is what triggers the refresh that advances status while backgrounded)

## Overview

- **Priority:** P1
- **Status:** completed
- **Description:** When a share advances to `.readyForCeremony` while the app is not active, post a LOCAL `UNUserNotificationCenter` notification ("<recipient> accepted. Tap to finish setting up the share."). Tapping it opens `ShareResumeStepperSheet` for that zone after unlock. This makes the `ShareInviteSentSheet.swift:34` promise ("we'll ping you") true.

## Key insights

- Notification permission is guaranteed before any share exists: `ApprovalPrerequisites.check()` prompts/verifies at share creation (`ApprovalPrerequisites.swift:20-41`, called from `createShare` at `ApprovalShareService.swift:76-78`).
- The advance decision point already exists: `OwnerShareRefresher.refreshAll` computes `next` per record (`OwnerShareRefresher.swift:44-49`); the store's monotonic guard (`SharingStore.swift:99-105`) means a given share crosses into `.readyForCeremony` exactly once — natural dedup, no extra bookkeeping.
- Fire ONLY for `.readyForCeremony`, not `.accepted` (audit open question 2): one accept would otherwise produce two banners minutes apart; `.readyForCeremony` is the state that actually needs A's hands.
- `ShareResumeStepperSheet` is a value-type sheet presented via `.sheet(item:)` with an `ItemShareRecord` (`HomeScreen.swift:195`, `NotificationsScreen.swift:99`, `ItemDetailScreen.swift:235`). The shell only exists while the vault is unlocked — draining a tap mailbox from the shell automatically defers presentation until after unlock.
- Foreground suppression is free: `AppPushDelegate.willPresent` returns `[]` for anything without an approval/invite CK payload (`AppPushDelegate.swift:81-94`) — a local share-status banner never doubles the in-app UI. Still guard scheduling on app-not-active to avoid pointless notification-center entries.

## Requirements

**Functional**
1. Local notification when a share record transitions (previous rank < readyForCeremony) → `.readyForCeremony` and `UIApplication.shared.applicationState != .active`.
2. Content: localized title/body including recipient label (device-local data, no secrets, no item title in the LOCK-SCREEN visible text — recipient email only, matching the existing privacy stance that labels never leave the device).
3. `userInfo` carries the zone name; tap → after unlock, `ShareResumeStepperSheet` for that share presents once.
4. Cold-launch tap (app killed): mailbox buffers the zone name until the unlocked shell appears.

**Non-functional**
- Best-effort: `center.add` errors ignored (in-app surfaces remain authoritative, same stance as `RotationNotificationService.swift:108-111`).
- New strings EN + VI in `Localizable.xcstrings`; copy rules: no "!", no "—", no "·".
- One banner max per share (monotonic-advance dedup, see insights).

## Architecture / data flow

```
(bg silent push → OwnerShareRefresher.refreshAll)
  record.status == .accepted/.inviteSent, next == .readyForCeremony
  → store.updateStatus(...)                        [persist]
  → ShareStatusNotifier.notifyReadyForCeremony(record)  [if app not active]
User taps banner
  → AppPushDelegate.userNotificationCenter(didReceive:)
  → userInfo["shareZoneName"] found → PendingShareResumeTap.zoneName = …
  → post .shareResumeTapRequested
Shell (unlocked only)
  → onAppear drains mailbox / onReceive reacts warm
  → env.sharingStore.shares.first { $0.zoneName == … } → .sheet(item:) ShareResumeStepperSheet
```

## Related code files

**Create**
- `Vaultify/Services/Sharing/ShareStatusNotifier.swift` (~70 lines) — schedules the immediate local notification; pure decision helper `static func shouldNotify(previous: ShareLifecycle, next: ShareLifecycle, appActive: Bool) -> Bool` for unit testing.

**Modify**
- `Vaultify/Services/Sharing/OwnerShareRefresher.swift` — capture `record.status` before `updateStatus`, call notifier after (`OwnerShareRefresher.swift:44-49`); inject notifier via init.
- `Vaultify/App/AppEnvironment.swift` — construct/wire notifier into `OwnerShareRefresher` (`AppEnvironment.swift:119`).
- `Vaultify/App/AppPushKind.swift` — add `PendingShareResumeTap` mailbox (mirror `PendingInviteLink`, `AppPushKind.swift:58-60`) + `Notification.Name.shareResumeTapRequested`.
- `Vaultify/App/AppPushDelegate.swift` — in `userNotificationCenter(didReceive:)` (`AppPushDelegate.swift:68-76`): before the CK branch, check `userInfo["shareZoneName"] as? String`; buffer + post.
- `Vaultify/Features/Main/VaultShellBehaviors.swift` — `@State` resume share + `.sheet(item:)` presenting `ShareResumeStepperSheet`; drain mailbox in `.onAppear` (near `VaultShellBehaviors.swift:89-97`) and observe the warm-path notification.
- `Vaultify/Localizable.xcstrings` — new keys, EN + VI.

## Implementation steps

1. Create `ShareStatusNotifier.swift`:
   - `@MainActor final class ShareStatusNotifier` holding `UNUserNotificationCenter.current()`.
   - `nonisolated static func shouldNotify(previous:next:appActive:) -> Bool` — `next == .readyForCeremony && previous.rank < next.rank && !appActive`.
   - `func notifyReadyForCeremony(record: ItemShareRecord)` — `UNMutableNotificationContent`, `content.title = appString("They accepted your invite")`, `content.body = appString("<recipient> accepted. Tap to finish setting up the share.")` (interpolated recipientLabel), `content.sound = .default`, `content.userInfo = ["shareZoneName": record.zoneName]`, trigger `nil` (immediate), identifier `"share-ready-\(record.zoneName)"` (stable id: a re-fire replaces rather than stacks). Comment explains the privacy line: recipient label is device-local; never include item titles or secrets.
2. `OwnerShareRefresher.refreshAll`: capture `let previous = record.status` before `resolveStatus`; after `store.updateStatus`, `if ShareStatusNotifier.shouldNotify(previous: previous, next: next, appActive: UIApplication.shared.applicationState == .active) { notifier.notifyReadyForCeremony(...) }`. Guard `#if canImport(UIKit)` for the app-state read (macOS branch: use `NSApplication.shared.isActive`; keep behavior parity or no-op on macOS — decide minimal: iOS only, macOS no-op with comment).
3. `AppEnvironment.swift:119`: pass a `ShareStatusNotifier()` into `OwnerShareRefresher`.
4. Mailbox + name in `AppPushKind.swift`; tap handler in `AppPushDelegate.userNotificationCenter(didReceive:)` — local-notification branch FIRST (its userInfo has no CK payload; falls through cleanly today, but explicit ordering documents intent).
5. `VaultShellBehaviors`: `@State private var resumeShareFromTap: ItemShareRecord?`; `.sheet(item: $resumeShareFromTap) { ShareResumeStepperSheet(share: $0) }`; drain in `.onAppear` + `.onReceive(NotificationCenter.default.publisher(for: .shareResumeTapRequested))` → look up `env.sharingStore.shares.first { $0.zoneName == zone }`; clear mailbox after drain. If record no longer exists (revoked), no-op.
6. Add xcstrings entries (EN source + VI translation) for the two notification strings.
7. Compile check.

## Todo list

- [x] ShareStatusNotifier (decision helper + scheduler)
- [x] OwnerShareRefresher transition hook + injection
- [x] AppEnvironment wiring
- [x] Mailbox + Notification.Name
- [x] AppPushDelegate tap routing
- [x] VaultShellBehaviors presenter + mailbox drain
- [x] xcstrings EN + VI
- [x] Compile check

## Success criteria

- Device QA: A invites, locks phone. B accepts + unlocks. A's lock screen shows the banner. Tap → Face ID unlock → resume stepper for that share is frontmost.
- Cold-launch tap (app swiped away): same end state after unlock.
- Share advanced while A is IN the app: no banner (in-app row updates instead).
- Both strings visible in VI when in-app language is Vietnamese.

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Sheet-presentation fight with approval ceremony auto-present (`VaultShellBehaviors` presents `ApprovalRequestSheet`) | M×M | Present resume sheet only if no approval sheet is up (reuse the same idle check `presentNextApprovalIfIdle` uses); tap intent wins over ambient auto-present — document ordering in code. |
| User revoked notification permission after share creation | M×L | Banner silently skipped (`center.add` best-effort); in-app surfaces + badge (phase 3) still work. Copy in phase 3 stays honest ("we'll notify you" — OS-level revocation is standard iOS behavior). |
| Killed-by-user app: iOS does not deliver silent pushes → no refresh → no banner | M×M | Known iOS platform limit. Foreground refresh + badge remain. Do not promise "instant" in copy. |
| `userInfo` key collision with CK payloads | L×L | Key `shareZoneName` is checked only when CK parse is absent/branch ordered first; CK pushes never carry it. |

## Security considerations

- Notification content: recipient email label only (already device-local in `SharingStore`, M2 model). No item title on lock screen, no codes, no URLs.
- Tap routing carries only the opaque zone name; all state re-read from local store; no CloudKit trust decisions from the payload.

## Next steps

Phase 3 rewrites the invite-sent copy to match the now-real behavior.
