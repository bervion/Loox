# Phase 2 — Onboarding + Unlock

**Status**: done · **Wave**: W2 (parallel) · **Owns**: `Onboarding/*`, `Unlock/*` (20 surfaces).
Method = canonical adversarial protocol + 6 audit greps (see `phase-01-shared-primitives.md`).

## Protagonist per screen
- Welcome → "start in 10 seconds or restore". CreateMasterPassword → "pick a password you won't lose".
- NameStep → "who are you". EmergencyKit(onboarding) → "save the one thing that can save you".
- ChooseTheme / EnableBiometric → single choice each. Done → "you're in". JoinVaultFlow → "trust this device".
- LockScreen → "unlock, fast". RecoveryView → "recover without a reset".

## Cluster hotspots (adversarial focus)
- **CreateMasterPasswordView**: inline error "Passwords don't match" + amber no-reset warning card — verify
  copy honest, no `!`; strength meter reused from Phase 1 (read-only). Continue disabled-state contrast.
- **EmergencyKitView**: mono recovery-key two-line block must not clip at SE; Copy/Share/Save-PDF row hit
  targets ≥44; toast "Copied" (not "Copied securely"). Continue gate on PDF-saved is intentional.
- **LockScreen**: three modes (biometric / password / slide-to-unlock). Verify slide knob ≥44 hit,
  Reduce-Motion collapses the slide affordance sanely, password field uses `Font.vaultCode`, error red is
  a semantic role. This screen was touched by the prior pass — regression-check, expect few findings.
- **JoinVaultFlow**: QR ≤260pt renders on SE; "Waiting…" spinner state; error + Start Over dead-end check.
- **SlideToUnlock / BiometricBadge / LockPasswordField**: tiny controls — padded hit areas, correct haptic
  (auth fail → `Haptics.error` from the auth path, not doubled by the badge view).
- VI length: "Sync from another device", "Save Emergency Kit", biometric titles ("Mở khoá bằng Face ID").

## Deliverables
`reports/findings-phase-02.md` (table) · `strings-manifest-phase-02.md` · fixes to owned files.

## Todo
- [x] Protocol answers for all 20 surfaces (24 per registry). [x] 6 audit greps → findings.
- [x] Verify onboarding scroll survives SE + Dynamic Type AX-XXL (Welcome feature cards, warning
      card — already safe; found + fixed the same clip risk on 5 more steps: EnableBiometricView,
      OnboardingDoneStep, JoinMethodChoiceView, JoinByQRView, JoinByRecoveryView via new
      `OnboardingScrollingStep` helper).
- [x] Verify Lock error/slide/biometric haptics single-fire (confirmed, no doubling).
- [x] Apply fixes (see `reports/phase-02-findings.md`).
- [x] Strings manifest (`strings-manifest-phase-02.md` — empty, no copy changed).

## Success / Risk
Success: zero audit-grep hits in owned files; every step renders SE↔Pro Max, light/dark, DT XL, EN+VI;
no dead-end error states. Risk: LockScreen regression from prior pass (Med×Med) → diff-review before edit;
slide-to-unlock only appears on deliberate lock (don't break that invariant).
</content>
