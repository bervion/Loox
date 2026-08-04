# Phase 6 — iPad, accessibility, polish

**Scope depends on OPEN-1.** Branch A (keep iPad) runs everything below. Branch B
(iPhone-only for v1) drops Agent 6A's iPad-specific items and the Phase 7 iPad screenshot
session, but **M12 and M13 still ship** — M13 lives in Phase 2E because it is an iPhone bug,
and M12 is triggered by any size-class change.

---

## Agent 6A — iPad adaptive UX

### M12 — a size-class flip destroys the open editor draft (worst defect in this phase)

`ItemEditorScreen.swift` treats `onDisappear` as "the user closed the editor". When the
shell swaps on a size-class change, the sheet disappears, the draft is deleted from memory,
staged attachment ciphertext is swept, and nothing is written to disk because the app never
backgrounded.

Concretely: an iPad user halfway through a new login drags the Split View divider, or
resizes the Stage Manager window — and silently, unrecoverably loses typed secret material.
This is worse than losing a scroll position; it loses data the user just entered.

- Stop clearing `uiState.editorDraft` from `onDisappear`. Distinguish "user dismissed" from
  "shell remounted".
- `UIStateStore.swift` — allow a live (non-cold-launch) hand-back: when `editorDraft != nil`
  and no editor is mounted, repopulate.
- `VaultShellBehaviors.swift:66` already applies `.sheet(item: $uiState.restoredDraft)` in
  both shells — reuse that path rather than adding a new one.
- The same reasoning applies to `VaultSidebarView.swift:20` `editorTarget` and the
  generator/TOTP sheets at `:23`.

### P1-07 — sidebar search cannot be cleared

`VaultSidebarView.swift:70` guards `!query.isEmpty` before emitting, so clearing the field
never tells the detail column. Worse than the audit recorded: `VaultSidebarList.swift:50`
filters `.search` out of the sidebar rows, so this field is the **only** way in or out of
the Search detail — there is no second affordance to recover with.

Fix: emit `.query("")` (or use a two-way binding). UI test clearing via both the clear
button and the keyboard; result list, title and empty state must all reset together.

### Two more sidebar defects the audit missed

- The **first keystroke can be dropped**: `SearchScreen.handleEntry()` guards on
  `selectedTab`, so the first character typed before the detail column settles is lost.
- `FlushSearchHeaderChrome` hides the navigation bar **unconditionally** on iOS 26,
  including where there is no host to hide it in.

### P1-08 — orientation contract

`UIRequiresFullScreen` is absent, there is no `~ipad` variant, and
`UIInterfaceOrientationPortraitUpsideDown` is missing — all confirmed. This is **not** a
submission blocker: iPad support landed at `78fb56c0` on 2026-07-28 and eight releases have
shipped on this exact Info.plist without the historical ITMS-90474 rejection firing.

It is a genuine rotation UX defect. Add the iPad four-orientation list in `Project.swift`
(Agent 1D owns that file — coordinate, do not edit it here).

### P1-09 — navigation continuity: fix the comment, file the rest

The audit implies a broken promise. The code never promised nav depth survives —
`AdaptiveRootView.swift:7-9` and `UIStateStore.swift:31-34` both scope the guarantee to
**selection**, and selection genuinely does survive.

The real defect is narrower and one-directional: compact pushes go through UIKit
(`AppNavigator`) and never touch the shared paths, so compact→regular loses depth while
regular→compact restores it.

**Do not** mirror UIKit nav depth into `uiState`. That is L-effort across `AppNavigator`,
`HomeScreen`, `ItemsScreen` and `VaultUINavShell` — the recently-rewritten nav shell, the
app's highest-risk surface — for the payoff of "your reading position survives a window
resize". Correct the doc comment and file the rest as follow-up.

---

## Agent 6B — accessibility and design DNA

Judge against `docs/design-dna-standard.md`, not against generic guidance.

### Real user-visible defects

- **VoiceOver `.isSelected` missing on theme cards** — `ChooseThemeView.swift:68-90`,
  `AppearanceSettingsView.swift:46-88`. A VoiceOver user cannot tell which theme is active.
  Plain failure, small fix.
- **Three sub-44pt targets** — `HomeScreen.swift:703-730`,
  `WelcomeLandingView.swift:135-143`, `JoinVaultFlow.swift:185-191`. One of them is the
  Emergency-Kit restore escape hatch, which is the worst possible control to make hard to hit.
- **`WatchtowerEmptyState.swift:11-50`** — fixed artwork and `Spacer` create an AX5 dead-end
  and clip in a narrow Split View.
- **`"Untitled"` fallback is never localized** — 9 call sites pass a `String` to `Text(_:)`,
  which bypasses the catalog entirely. Ships English into VI and JA.
- **`ThemedToggleStyle.swift:38`** animates with no Reduce Motion gate.
- **Reduce Transparency** — `CopyToastOverlay.swift` always uses material;
  `EditorFieldRow.swift:449-466` keeps `.regularMaterial` inside the reduce-transparency
  branch.
- **`EditorFieldRow`** paints a raw `Color.primary` hairline on a themed floating surface.

### The app-level Reduce Motion toggle — delete it, do not wire it

`AppearanceSettingsView.swift:105-108` reaches only `\.meshAnimated`, consumed only by the
wallpaper engine, which `WallpaperFeature.decorativeEnabled = false` turns off. **It has
never done anything.**

Wiring it means a new environment key, a `Motion` overload, and edits across ~42 files — for
a setting that duplicates iOS Settings → Accessibility → Motion, which every affected user
already knows. Delete the toggle and the stored property; the views that read the system
setting already behave correctly.

Removing a user-facing control is an owner call, but "remove a control that has never
worked" is an easy sell.

### `minimumScaleFactor` below the DNA floor

`LooxHubScreen.swift:113-117` uses 0.65 and `LargeTypeView.swift:156-160` uses 0.5 against a
0.7 floor. `LargeTypeView` is a deliberate exception — its whole purpose is fitting a code
on screen. Fix `LooxHubScreen`; document `LargeTypeView` as intentional rather than raising
it and breaking the feature.

### "iPhone" in copy that is not iPhone-only

12 strings across `HomeScreen.swift:796`, `JoinVaultFlow.swift:194-201`,
`QuickLinkView.swift:117-120`, `AboutView.swift:67-76,94-102`, `ShareAccessSheet.swift:762`,
`ShareSpaceSheet.swift:357`, `ShareResumeStepperSheet.swift:79`,
`ItemDetailScreen.swift:841-848`.

Change to "device" only where the feature genuinely is not iPhone-only, and only if iPad or
Mac ships (OPEN-1). Every changed string needs EN + VI + JA.

### Small addition — relay data deletion

Add a "Delete my relay data" affordance in the relay settings pane. Account deletion is not
required (no accounts), but the relay stores a principal bound to a verified real email
address, and today the only deletion path is the nuclear Erase — and not at all on macOS
before Phase 2B. Cheap, and it is the answer if a reviewer asks.

---

## Verification matrix

Every screen touched must pass: light and dark, Reduce Transparency, Reduce Motion,
increased contrast, AX XXXL, VoiceOver, 44pt targets — on iPhone SE (375), Pro Max (430),
and, if OPEN-1 keeps iPad, a narrow Split View. Design for the **longest localized label**,
usually VI.

## Phase exit criteria

- [ ] No draft or staged attachment is lost on any size-class change or rotation
- [ ] Sidebar search clears query, results, title and empty state together
- [ ] First keystroke never dropped; nav bar not hidden without a host
- [ ] Theme cards announce selection to VoiceOver
- [ ] No control under 44pt on the audited screens
- [ ] `"Untitled"` localized in all 9 places, EN + VI + JA
- [ ] Reduce Motion and Reduce Transparency honored on every touched surface
- [ ] Dead Reduce Motion toggle removed (owner-approved)
- [ ] Full matrix walked and recorded
