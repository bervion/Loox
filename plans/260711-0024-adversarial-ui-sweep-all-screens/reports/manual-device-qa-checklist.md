# Manual Device QA Checklist — Adversarial UI/UX Sweep

Everything below requires real hardware or a real simulator session — it was NOT (and cannot be)
verified by static code review. Run once per release candidate on this branch. Check off each box;
anything unchecked before release should be triaged, not silently skipped.

## 0. Setup

- [ ] Install the build on: 1 SE-class device/sim (iPhone SE, 375pt width) + 1 Pro Max-class
      device/sim (430pt width).
- [ ] Have both EN and VI available in Settings → General → Language & Region (or the in-app
      language toggle) to switch without reinstalling.

## 1. Widths (SE 375pt / Pro Max 430pt)

- [ ] Home: TOTP scroller, Needs Attention rows, quick-actions 2×2 grid — no clipped VI labels, no
      squeezed grids at SE.
- [ ] Watchtower: `CategoryRow` titles (longest is EN "Set up two-factor authentication", 33 chars,
      now `lineLimit(2)`) — confirm it wraps to 2 lines cleanly at SE, doesn't overlap the count
      badge/chevron.
- [ ] Item Editor / Item Detail: tag chips, "Located In" pill, field rows — no truncated VI at SE.
- [ ] Onboarding: `JoinByRecoveryView`'s recovery-key field with the new trailing scan-icon
      accessory — confirm the icon doesn't crowd the field at SE width, and is still tappable.
- [ ] QuickLink result screen (post-fix layout): Copy (primary) / Done (secondary) / Share+Shorten
      (utility row) — confirm the utility row doesn't crowd or wrap awkwardly at SE.

## 2. Dynamic Type (default / XL / accessibility XXL)

- [ ] LockScreen at AX-XXL on SE with a long inline error message showing (e.g. repeated wrong
      password) — **known deferred risk** (Phase 2): fixed `Spacer()`-centered layout, no scroll
      fallback. Confirm whether content actually clips; if it does, this needs a follow-up fix.
- [ ] TOTP card (Home + Item Detail) at AX-XXL — the OTP code (`Font.vaultCode`, now with
      `minimumScaleFactor(0.7)` guard) must not clip "123 456" inside the fixed-width card.
- [ ] `DetailFieldRow`'s trailing cluster (strength badge + countdown ring + copy glyph + menu) at
      AX-XXL — Phase 5 flagged this as static-analysis-only, not device-verified.
- [ ] Onboarding scroll-safety steps (`EnableBiometricView`, `OnboardingDoneStep`,
      `JoinMethodChoiceView`, `JoinByQRView`, `JoinByRecoveryView`) at AX-XXL on SE — confirm the
      new `OnboardingScrollingStep` wrapper actually scrolls instead of clipping.
- [ ] Any `minimumScaleFactor` in the app never visibly shrinks text to illegibility (floor is 0.7
      everywhere; confirm no reflow looks squashed).

## 3. Appearance (light + dark, all 7 accents)

- [ ] Cycle all 7 accent presets (Settings → Appearance) in both light and dark — confirm no
      invisible-after-switch text/icon anywhere (Home, Item Detail, Watchtower score ring,
      Generator, Sharing sheets).
- [ ] Watchtower score ring: confirm the red→amber→green gauge blend (now theme-role-driven, was a
      fixed hex triple) still reads correctly across all 7 accents in both themes.
- [ ] Appearance screen's own theme-card selection ring and accent-swatch selection ring — both use
      the live accent; confirm visually correct across presets (one residual `Color.accentColor`
      site was found but not fixed this pass — see consolidated report §2/§4; visually verify it is
      or isn't a problem on-device).
- [ ] Reduce Transparency ON: confirm solid-fallback bars/glass surfaces render correctly (header
      bars, tab bar, sheets).

## 4. Accessibility (Reduce Motion, Reduce Transparency, VoiceOver)

- [ ] Reduce Motion ON: Onboarding step transitions, LockScreen mode transitions, ChooseThemeView
      selection, AutoNight brightness slider, Watchtower ring/strength-bar — all should render as
      instant swaps, not animated.
- [ ] VoiceOver: Watchtower score ring now announces the qualitative band ("Fairly secure" /
      "Needs attention" / "At risk") alongside the number — confirm it reads naturally.
- [ ] VoiceOver: confirm the new `JoinByRecoveryView` scan-icon accessory announces "Scan Setup
      Code" (not just "button").

## 5. Locale (EN + VI)

- [ ] Full EN pass + full VI pass of: Onboarding, Unlock, Home, Item Detail/Editor, Watchtower,
      Generator, Settings (incl. Appearance/Export/Import/Emergency Kit), Personas/Profile,
      Sharing (owner + approval + QuickLink/QuickView), Main shell/Mac (if testing on Mac/iPad).
- [ ] Confirm the reworded `ShareAccessSheet` hint ("check again from the menu above", replacing
      the now-removed "tap Check Now" copy) reads naturally in both languages.

## 6. Haptics on hardware (simulator cannot verify)

- [ ] Copy actions (password, username, TOTP, recovery key, share code) fire exactly one haptic
      (`.success`) — never doubled.
- [ ] Destructive confirms (delete item, empty trash, delete Space, delete passkey, delete persona,
      cancel invite, revoke share) fire `.error` once.
- [ ] Selection/toggle actions (theme card tap, accent swatch tap, AutoNight mode row,
      pin/favorite toggle, tab switch) fire `.tap` once.
- [ ] AutoNight brightness slider fires a tick-per-percent while dragging + a firm tap on release
      (mirrors the Generator length slider).
- [ ] Confirm "Activate Sharing" / "Approve with Face ID" / "Check Now" / persona
      confirm-email/check-verification-class buttons fire **no view-level haptic** — this is the
      app's deliberate, confirmed convention (see consolidated report §3), not a bug to fix.

## 7. Specific flows flagged by phases (functional + visual)

- [ ] **Persona delete confirm** (P10): swipe-delete a persona with ≥2 aliases — confirm the new
      confirmation dialog states the real cascade consequence (aliases tombstoned), and
      `Haptics.error()` fires on confirm.
- [ ] **Forwarding inbox delete** (P10): delete a manually-added, currently-unused inbox — confirm
      the new confirmation dialog appears and behaves correctly.
- [ ] **Unlock gate motion + LockScreen at AX-XXL** (P2, P14): biometric fallback → password entry
      transition; confirm no double Face ID prompt on the AutoFill extension's `UnlockGate`.
- [ ] **QuickLink result sheet** (P12, this report's user-named hotspot): create a link, confirm
      the new hierarchy (Copy primary / Done secondary / Share+Shorten utility row) feels
      obviously "one thing to do", not a wall of choices.
- [ ] **Share waiting sheet** (P11): `ShareAccessSheet` `.waiting` state before AND after the
      recipient accepts — confirm "Check Now" (now in the toolbar `•••` menu) still works, and
      "Nudge via Messages"/"Share Invite Link" disappears once accepted.
- [ ] **Bottom Copy Password cluster fade** (Item Detail, prior Controlled-Reveal pass) — confirm
      still smooth after this sweep's unrelated fixes to sibling rows on the same screen.
- [ ] **TOTP card at AX sizes** (Home + Item Detail + Generator) — see §2, confirm no clipping.
- [ ] **Dark-mode card separation after stroke removal** (Item Detail's Passkeys section, now using
      `.elevation(.level1)` instead of a raw border) — confirm cards still read as visually distinct
      from the background in dark mode without a stroke.
- [ ] **JoinByRecoveryView scan-icon accessory** (this phase's fix): confirm tapping the trailing
      icon opens the QR scanner exactly like the old full-width button did, and the field row
      doesn't look cramped.

## 8. Regression spot-checks (things fixed this sweep, verify they stayed fixed)

- [ ] `RevealableSecureField`'s reveal/hide toggle: 44pt tappable, doesn't visually overlap the
      password field's adjacent tap region in a confusing way.
- [ ] `TagChipEditor`'s remove (×) button: tappable without accidentally removing the wrong chip
      in a dense multi-tag row.
- [ ] `IconColorPicker`'s color swatches: 44pt tappable without visually growing.
- [ ] Export flow: both "Create Export" (encrypted) and "Create Unencrypted Export" (CSV, now with
      a confirmation + `Haptics.error`) — confirm haptic parity with Import's existing feedback.
