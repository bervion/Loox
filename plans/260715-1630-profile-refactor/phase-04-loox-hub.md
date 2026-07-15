# Phase 04 — Loox hub

Type: reuse consolidation · Depends: 01 · ("Loox" is the brand name, already in product copy.)

## Context — three features to gather under one hub
- **Private Email**: `PersonaAliasesScreen` (persona-scoped aliases + forwarding inboxes; reusable + site-specific). Entry is currently a row inside ProfileScreen.
- **Share links**: per-item `ItemShareRecord` (`SharingStore`), managed today via the ItemDetail share sheet + `NotificationsScreen` + `ShareRecipientDetailSheet`. No central config screen.
- **Approval Mode**: `env.settings.approvalModeEnabled` toggle in `SettingsScreen` (app-wide, independent of iCloud sync — ADR-2).

## Requirements
- New `LooxHubScreen` (pushed from Profile) with rows:
  1. `Private Email` → `PersonaAliasesScreen` (unchanged) + alias-count trailing value.
  2. `Share links` → a management view listing active shares grouped by recipient (over `SharingStore.shares`); reuse `ShareRecipientDetailSheet` per recipient.
  3. `Approval Mode` → toggle bound to the SAME `approvalModeEnabled` flag + a link to approval requests (`NotificationsScreen`).
- UI must distinguish scope: Private Email is **per-persona**; Share links + Approval are **app-wide** (separate groups/captions).

## Constraints
- **Single source of truth** for the Approval Mode flag — surface the existing binding; pick ONE home (recommend Loox) and reconcile the Settings toggle (leave a pointer or remove there). Do not fork the flag logic.
- Respect ADR-2: never gate vault sync on `approvalModeEnabled`.

## Files
- New: `Vaultify/Features/Profile/LooxHubScreen.swift` (+ maybe `ShareLinksScreen`).
- Reuse: `PersonaAliasesScreen`, `ShareRecipientDetailSheet`, `NotificationsScreen`, `SettingsStore.approvalModeEnabled`.
- Modify: `ProfileScreen` (Loox row), `SettingsScreen` (reconcile the Approval Mode toggle location).

## Validation
- `make check`; toggling Approval Mode from Loox matches the old Settings behavior (one flag, same confirmation-on-off); alias + share management reachable; EN + VI.
