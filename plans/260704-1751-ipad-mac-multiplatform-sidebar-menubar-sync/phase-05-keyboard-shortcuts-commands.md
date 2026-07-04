---
phase: 5
title: "Keyboard Shortcuts & Commands"
status: pending
priority: P2
effort: "2-4d"
dependencies: [2, 4]
---

# Phase 5: Keyboard Shortcuts & Commands

## Overview

Add keyboard-driven navigation for iPad + Mac: menu bar `CommandMenu` entries, `.keyboardShortcut`
on primary actions, and focus-based list navigation. Depends on both the sidebar (P2) and the Mac
shell (P4).

<!-- Updated: Validation Session 1 — GLOBAL HOTKEY CUT (Mac App Store = App Sandbox, incompatible with
the Accessibility permission a system-wide hotkey needs). Menu-bar click (P4) summons Quick Access;
in-app ⌘ shortcuts cover the rest. All global-hotkey mentions below are OUT OF SCOPE this round. -->
> **Scope note (Validation Session 1):** the global system-wide hotkey is **CUT** — MAS/sandbox rules it
> out. Everything below about `GlobalHotKey.swift` / summoning Quick Access from any app is deferred.
> Quick Access is summoned via the menu-bar click (P4); in-app shortcuts remain.

## Requirements

- Functional: ⌘F focus search, ⌘C copy selected field, ⌘N new item, ⌘, settings (Mac), ⌘L lock now.
- Functional: Arrow-key navigation through the item list; ⏎ opens/reveals; Esc dismisses sheets.
- ~~Functional (Mac): a global hotkey opens Quick Access from any app.~~ **CUT (Validation Session 1)** —
  MAS sandbox. Quick Access is summoned by the menu-bar click (P4) instead.
- Non-functional: shortcuts never bypass lock; ⌘C copy still auto-clears.
- Non-functional: hardware-keyboard support on iPad (Magic Keyboard) matches Mac where sensible.

## Architecture

**Commands** (`Vaultify/App/VaultCommands.swift` — new, `#if os(macOS) || iPad`):
- `.commands { CommandGroup(...) / CommandMenu("Vault") { … } }` attached to the `WindowGroup`/scene.
- Menu items: New Item (⌘N), Find (⌘F), Copy Password (⌘C), Copy Username (⌘⇧C), Copy TOTP (⌘⌥C),
  Lock Now (⌘L), Settings (⌘,), New Space. Each posts to the shared `VaultSectionRouter`/actions.

**Focus & keys**:
- `@FocusState` on search + list; `.keyboardShortcut` modifiers on buttons; `onKeyPress`
  (iOS 17+/macOS 14) for arrow/Enter/Esc in lists.
- Reuse `VaultSectionRouter` (P2) so ⌘F jumps to Search section then focuses the field.

**Global hotkey (Mac only)** — summon Quick Access:
- Preferred: no third-party lib; use a small `NSEvent.addGlobalMonitorForEvents` / Carbon
  `RegisterEventHotKey` wrapper behind `#if os(macOS)`. Requires the app resident (P4 activation policy).
- User-configurable hotkey stored in settings; default e.g. ⌘⇧Space. Confirm scope vs Open Question 4.

## Related Code Files

- Create: `Vaultify/App/VaultCommands.swift` (`GlobalHotKey.swift` cut — Validation Session 1)
- Modify: `Vaultify/App/VaultifyApp.swift` (attach `.commands`; register hotkey on macOS launch)
- Modify: `Vaultify/Features/Main/VaultSidebarView.swift` + list rows (focus, key handling)
- Modify: `Vaultify/Features/QuickAccess/QuickAccessView.swift` (hotkey target)
- Modify: `Vaultify/Features/Settings/MacSettingsView.swift` (hotkey config)
- Modify: `Localizable.xcstrings` (menu titles EN + VI)

## Implementation Steps

1. Build `VaultCommands` menu; attach to scene; wire each command to existing actions/router.
2. Add `.keyboardShortcut` to primary buttons (copy, new, lock) across item detail + sidebar.
3. Add focus + `onKeyPress` arrow/Enter/Esc navigation to the item list & Quick Access.
4. ~~(Mac) implement `GlobalHotKey` + settings config~~ — **CUT (Validation Session 1)**.
5. QA on iPad (Magic Keyboard) + Mac: every shortcut + menu item (no global hotkey).

## Success Criteria

- [ ] ⌘F/⌘C/⌘N/⌘L/⌘, work on Mac and iPad (where applicable) and appear in the Mac menu bar.
- [ ] Arrow keys move list selection; ⏎ opens; Esc dismisses; nothing bypasses the lock.
- [ ] Copy shortcuts still auto-clear the clipboard.
- [ ] Menu titles + shortcut labels localized EN + VI.
- [ ] Quick Access is summoned via the menu-bar click (P4) — no global hotkey shipped this round.

## Risk Assessment

- **Global hotkey APIs are fiddly** (Carbon `RegisterEventHotKey` vs `NSEvent` monitors; sandbox +
  Accessibility permission may be required) → spike early; if it needs Accessibility permission,
  surface a clear onboarding prompt. Fallback: menu-bar click + in-app shortcuts only.
- **⌘C conflict**: global Copy vs field-specific copy → scope command copy to the focused item context;
  don't hijack system copy in text fields.
- **iPad hardware-keyboard parity** is partial (no menu bar) → expose shortcuts via key commands;
  don't assume Mac-only affordances exist on iPad.
- Verify shortcuts never fire while locked (guard on `VaultSession` state).

## Red Team Amendments (2026-07-04)

- **[High #14] RESOLVED (Validation Session 1) — global hotkey CUT.** The user chose Mac App Store
  distribution ⇒ **App Sandbox is mandatory**, which is incompatible with the TCC Accessibility
  permission a system-wide hotkey (`NSEvent.addGlobalMonitorForEvents` / Carbon `RegisterEventHotKey`)
  requires — and that permission is a keylogger-class trust ask for a password manager. Decision: **do
  not ship a global hotkey this round.** Quick Access is summoned via the menu-bar click (P4); in-app ⌘
  shortcuts (⌘F/⌘C/⌘N/⌘L/⌘,) satisfy "shortcuts like 1Password" with no special permission. (1Password's
  global Quick Access uses a privileged helper / system extension, not a sandboxed app — out of scope.)
  Revisit only if a non-sandboxed Developer-ID build is ever added.
- **[High #12] Copy shortcuts + macOS clipboard:** the "still auto-clears" criterion must be the
  macOS-honest version (concealed pasteboard + clear on resign/terminate), not the OS-expiry guarantee
  iOS gives (see P1/P4 amendments).
- **[Medium #20]** Menu command titles + shortcut labels already listed for `Localizable.xcstrings` —
  keep the EN + VI criterion explicit.
