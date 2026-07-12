# Phase 03 — Honest copy, actionable bell badge, responsive waiting sheet (R3 + R4 + R7)

## Context links

- Audit §2-F2 (false promise), §2-F3 (badge), §2-F5 (60s lag), §5-R3/R4/R7
- Depends on: phase 01 (`.shareAcceptanceHint` exists; push makes the copy true)

## Overview

- **Priority:** P2
- **Status:** completed
- **Description:** Three small, user-visible fixes: (R3) rewrite the invite-sent reassurance copy so it matches real behavior; (R4) count `.readyForCeremony` shares in the bell badge; (R7) make the waiting sheet flip to "Accepted" within seconds by checking acceptance every tick and reacting to the acceptance hint, while cutting the poll budget from ~10 min to ~2.5 min.

## Key insights

- With phases 1+2 shipped, "we'll notify you" is true — copy should say notify, not "ping", and must survive the edge where the user later revokes notification permission (say "notify", never "instantly").
- Badge: `HomeHeaderBar.notificationCount` = invites + owner requests only (`HomeHeaderBar.swift:15-18`). `.readyForCeremony` is the one state waiting on A's action. `SharingStore` is `@Observable` (`SharingStore.swift:72`) and already in `AppEnvironment` — pure additive.
- Sheet lag root cause: `participantAccepted` checked only every 6th tick (`ShareAccessSheet.swift:366-371`). It is a single-record `fetchShare` (`ApprovalShareService.swift:137-149`) — cheap enough for every tick.
- Poll redundancy: with the silent push + `OwnerShareRefresher` reacting, the sheet's own poll is a fallback, not the primary detector — 24 attempts (~2.5 min at the 10s cap) suffices; `pollExhausted` footnote behavior stays (`ShareAccessSheet.swift:375-377`).
- `retryAutoInviteIfNeeded` must KEEP its slower cadence (`attempt % 6`) — it does public-DB writes, not reads (`ShareAccessSheet.swift:331-344`).

## Requirements

**Functional**
1. `ShareInviteSentSheet.swift:34` copy replaced (EN + VI): promise = notification on acceptance + trackable from Home. No "ping".
2. Bell badge includes count of shares at `.readyForCeremony`.
3. Waiting sheet: acceptance-status check every tick; immediate re-check when `.shareAcceptanceHint` fires; budget 80 → 24 attempts.

**Non-functional**
- Badge count exposed as a testable `SharingStore` computed property, not inline view logic.
- Copy rules: no "!", no "—", no "·"; design for longest localized label (VI).

## Architecture

- `SharingStore.awaitingCeremonyCount: Int` — `shares.filter { $0.status == .readyForCeremony }.count`. View sums it with the two existing sources.
- Sheet responsiveness: keep the existing loop shape; move `participantAccepted` out of the `% 6` branch to every iteration; add `.onReceive(NotificationCenter.default.publisher(for: .shareAcceptanceHint))` on the sheet → `Task { await checkProfileNow() }` (`checkProfileNow` already handles both profile-found and accepted-only outcomes, `ShareAccessSheet.swift:382-398`).

## Related code files

**Modify**
- `Vaultify/Features/Sharing/ShareInviteSentSheet.swift:34` — copy.
- `Vaultify/Features/Sharing/SharingStore.swift` — `awaitingCeremonyCount` computed var (near `shares(forItem:)`, `SharingStore.swift:86-88`).
- `Vaultify/Features/Home/Components/HomeHeaderBar.swift:15-18` — add `env.sharingStore.awaitingCeremonyCount`.
- `Vaultify/Features/Sharing/ShareAccessSheet.swift:349-378` — poll changes; `.onReceive` hint hook on the waiting step's view.
- `Vaultify/Localizable.xcstrings` — updated EN source string + VI translation (note: changing the EN literal creates a NEW catalog key; remove/let the old key age out and add the VI value for the new one).

**Create / delete:** none.

## Implementation steps

1. `SharingStore`: add documented `awaitingCeremonyCount`.
2. `HomeHeaderBar`: extend `notificationCount`. Verify badge renders 3-source sums in light/dark (numeric only, no layout change).
3. New copy (EN, adjust in review): "No need to wait here. We'll notify you as soon as they accept, and you can track progress anytime from Home." + VI translation. Replace `ShareInviteSentSheet.swift:34` literal; add xcstrings entry with VI value.
4. `pollForProfile`: loop `0..<24`; each tick: profile check (unchanged) then `participantAccepted` check + `updateStatus(.accepted)` (previously gated by `% 6`); keep `retryAutoInviteIfNeeded()` behind `attempt % 6 == 5`. Update the stale comment block (`ShareAccessSheet.swift:362-365`) to describe the new cadence and WHY the budget shrank (push is primary; poll is fallback).
5. Waiting-step view: add `.onReceive` for `.shareAcceptanceHint` → single `checkProfileNow()` (re-entrancy safe: it is a one-shot fetch; `step` guard at `ShareAccessSheet.swift:384` drops it if the sheet moved on).
6. Compile check; visual pass light/dark/VI per design-dna-standard.

## Todo list

- [x] SharingStore.awaitingCeremonyCount
- [x] HomeHeaderBar badge source
- [x] ShareInviteSentSheet copy EN + VI (xcstrings)
- [x] pollForProfile every-tick acceptance check + 24-attempt budget
- [x] Hint-driven checkProfileNow on the waiting step
- [x] Compile check + light/dark/VI visual pass

## Success criteria

- B accepts while A's sheet is open → "Accepted. Finishing on their device" copy within ≤10s (was 30-60s).
- Home bell badges when a share reaches `.readyForCeremony`; opening Notifications shows the actionable row.
- No string ships without a VI value.

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Every-tick `fetchShare` raises CloudKit request volume while sheet open | L×L | Bounded: ≤24 extra single-record fetches per invite, only while the sheet is visibly open; net volume DROPS vs today (80 → 24 ticks). |
| Badge count double-counts a share that also has a pending owner request | L×L | Different sources (share lifecycle vs live requests); a request only exists on `.active` shares (grant required), which are excluded by `.readyForCeremony` filter. |
| Old EN catalog key orphaned in xcstrings | L×L | Xcode build auto-prunes unreferenced auto-extracted keys; verify catalog diff at review. |

## Security considerations

None new — read paths only; copy contains no secrets.

## Next steps

Phases 4-6 are independent; proceed in any order.
