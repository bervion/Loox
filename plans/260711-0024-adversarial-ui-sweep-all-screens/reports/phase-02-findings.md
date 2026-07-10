# Phase 2 — Onboarding + Unlock: Findings

Scope: 24 surfaces (per `reports/phase-00-surface-registry.md`, Phase 2 row) across `Onboarding/*`,
`Unlock/*`, +1 review-exempt gap (`Vaultify/Security/UserActivityMonitor.swift`). Method:
`docs/design-dna-standard.md` adversarial protocol Q1-5 + the 6 audit greps. Grouped by file; every
struct named so all 24 registry rows are traceable.

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| WelcomeStep, FeatureCard, WelcomeBackdrop | OnboardingFlow.swift | "start in 10 seconds or restore" — Get Started primary, Sync-from-device secondary, both above the fold | copy calm, no `!`/`—`/`·`; VI checked for "Sync from another device" (fits SE) | CTA buttons `.controlSize(.large)` ≥44pt; GeometryReader+ScrollView already handles SE/AX-XXL overflow (pre-existing, correct) | tokens throughout; `FeatureCard`'s SF `faceid` icon uses `.font(.system(size: Metric.iconUtility))` — documented SF-exception (Polaris ships no Face ID glyph), sized via token, not a defect | zero-state only (static hero); scroll fallback covers AX-XXL | none | — | — | pass |
| OnboardingFlow (root switch) | OnboardingFlow.swift | orchestrates step transitions, no own UI | n/a | n/a | **step-switch `.animation(.smooth(duration:0.35))` and copy-toast `.animation(.spring(duration:0.3))` ignored Reduce Motion** | step transitions (welcome→…→done) | Reduce Motion not respected on 2 animations | wrapped both via `.vault(_, reduceMotion:)` (added `@Environment(\.accessibilityReduceMotion)`) | medium | fixed |
| OnboardingDoneStep | OnboardingFlow.swift | "you're in" | recap line truthful (mentions biometrics only if enabled) | Open Loox button ≥44pt | fixed `Spacer()`-centered `VStack`, **no scroll fallback — clips at AX-XXL Dynamic Type on SE** (icon+header+recap+button don't fit) | done-state only, but that one state could clip | wrapped in new `OnboardingScrollingStep` (same GeometryReader+ScrollView+minHeight technique as `WelcomeStep`) | medium | fixed |
| CreateMasterPasswordView | CreateMasterPasswordView.swift | "pick a password you won't lose" | "Passwords don't match" honest, no banned punctuation; amber warning card copy calm | Continue disabled-state via `.disabled` (opacity handled by `ThemedProminentButtonStyle`, not raw `.opacity`) — correct | tokens throughout; already in `ScrollView` (AX-XXL safe) | empty/mismatch/error/busy(spinner via `prominentButtonLoading`) all covered | none | — | — | pass |
| NameStepView | NameStepView.swift | "who are you" | copy calm | fields ≥44pt via padding math | **field's own `TextField` used raw `.font(.body)`**; **card `cornerRadius: 12` + `.padding(.horizontal, 14)` drift from sibling `RevealableSecureField` (`Radius.sm`=10 / `Space.s3`=12)** | empty/typed/focus-advance all covered; already in ScrollView | 2 defects (typography + token drift vs. sibling field) | `.font(.body)`→`.vaultType(.body)`; radius 12→`Radius.sm`, padding 14→`Space.s3` (now matches `RevealableSecureField` exactly) | medium | fixed |
| EmergencyKitView | EmergencyKitView.swift | "save the one thing that can save you" | Copy/Share/Continue copy honest ("Copied Recovery key" via `ClipboardService`, not "Copied securely" — verified); mono key block splits into 2 balanced lines (no SE clip) | Copy/Share (`.themedTinted`, `.controlSize(.large)`) and Save-PDF row all ≥44pt by construction (verified against `ThemedTintedButtonStyle`'s `Space.s4` vertical padding) | tokens throughout | loading(key generating)/ready/saved/export-error all covered; Continue gate on PDF-saved intentional | none | — | — | pass |
| ChooseThemeView, ThemeOptionRow | ChooseThemeView.swift | single choice: appearance | copy calm | row ≥44pt; swatch circles are documented literal-swatch exemption (raw white/black/gradient) | **selection had no haptic** — vocabulary requires `Haptics.tap()` for "selection/toggle" (sibling `RevealableSecureField`'s reveal toggle already does this); **selection animation `.smooth(duration:0.2)` ignored Reduce Motion** | selected/unselected per mode, live preview | 2 defects (missing haptic, Reduce Motion) | added `Haptics.tap()` + `@Environment(\.accessibilityReduceMotion)` wrapping via `.vault(_, reduceMotion:)` | medium | fixed |
| EnableBiometricView | EnableBiometricView.swift | single choice: enable biometrics | copy calm, names the actual biometric type | Enable/Not-now buttons ≥44pt | **icon used raw `Color.accentColor`** (static asset-catalog tint) instead of the live per-preset `VaultColors.accent` — breaks the 7-preset accent system; **fixed `Spacer()`-centered layout, no scroll fallback — AX-XXL clip risk on SE** (same class of bug as `OnboardingDoneStep`) | enable/skip only, no error state | 2 defects (accent theme break, AX-XXL clip risk) | `Color.accentColor`→`VaultColors.accent`; wrapped in `OnboardingScrollingStep` | medium | fixed |
| JoinVaultFlow (root switch) | JoinVaultFlow.swift | orchestrates join-flow steps | n/a | n/a | **step-switch `.animation(.smooth(duration:0.35))` ignored Reduce Motion** (same class as `OnboardingFlow`) | choice→qr/recovery→password→biometric, key zeroed on back-out (verified `onChange` clears `SecureBytes`) | Reduce Motion not respected | wrapped via `.vault(_, reduceMotion:)` | medium | fixed |
| JoinMethodChoiceView, JoinOptionCard | JoinVaultFlow.swift | "trust this device" — choose QR or recovery key | copy calm | cards fully tappable (`.contentShape(Rectangle())`), ≥44pt; Back button ≥44pt | icon tile already `VaultColors.accent` (correct, no accentColor bug here); **fixed `Spacer()`-centered layout, no scroll fallback** | choice-only, no error state, but AX-XXL clip risk | 1 defect (AX-XXL clip risk) | wrapped in `OnboardingScrollingStep` | medium | fixed |
| JoinByQRView | JoinVaultFlow.swift | pair via QR | "Waiting for your other device…" honest, VI checked (fits SE); error/Start-Over path is not a dead end (fresh session + retry) | QR ≤260pt renders on SE (`.frame(maxWidth: 260)`, verified against 375pt SE width — comfortable margin); Start Over/Back ≥44pt | **fixed `Spacer()`-centered layout, no scroll fallback** — the error+Start-Over+Back stack could clip at AX-XXL | waiting/error/(implicit success→pop) all covered, no dead end | 1 defect (AX-XXL clip risk) | wrapped in `OnboardingScrollingStep` | medium | fixed |
| JoinByRecoveryView | JoinVaultFlow.swift | recover via Emergency Kit key | "That recovery key didn't work." honest, no banned punctuation | Scan/Continue/Back ≥44pt (native `.themedTinted`/`.themedProminent`/`.bordered` styles) | **recovery-key field used `.font(recoveryKey.isEmpty ? .body : .vaultCode())` — raw `.body` half of the ternary**; **`cornerRadius: 12` + `.padding(.horizontal, 14)` drift from `RevealableSecureField`**; **fixed `Spacer()`-centered layout, no scroll fallback** | empty/typed(mono)/busy/error all covered | 3 defects (typography, token drift, AX-XXL clip risk) | ternary→`VaultType.body.font`; radius→`Radius.sm`, padding→`Space.s3`; wrapped in `OnboardingScrollingStep` | medium | fixed |
| RecoveryScannerSheet | JoinVaultFlow.swift | scan the Setup Code QR | "Scan Setup Code" / "Cancel" calm | **Cancel pill's tap area ≈34-36pt tall (padding `Space.s3`h/`Space.s2`v around ~15pt text) — under the 44pt minimum** | raw `.white`/`.black.opacity(0.35)` — documented camera-overlay exemption (matches QR/favicon class); `Radius`/`Space` n/a (Capsule fits content) | scanning-only state (no error/empty needed — camera feed is always "ready") | 1 defect (hit target) | added `.frame(minHeight: Metric.hitMin)` on the real Cancel button only (invisible growth; the visible pill/background still sizes to the smaller padded content, so it doesn't visually bulge) | high | fixed |
| OnboardingStepHeader | OnboardingStepHeader.swift | shared hero title+subtitle, no own protagonist (shared header) | `minimumScaleFactor(0.85)` floor respects the "never below 0.7" rule; `lineLimit(2)` + `fixedSize` prevents silent single-line truncation | n/a (no controls) | tokens throughout | hero/compact style both covered | none | — | — | pass |
| BiometricBadge | BiometricBadge.swift | Face ID / Touch ID retry affordance on the lock screen | a11y label "Unlock with {biometric}" present | **badge is exactly 40×40pt (`side`), no padded hit area — under the 44pt minimum** (same defect class the sweep already fixed once in `RevealableSecureField`, Phase 1) | tokens (`Radius.sm`, `.elevation(.level2)`); SF biometric glyph is a documented exception (Polaris ships none) | idle/authenticating(spinner, disabled)/failure(reverts) all covered; no haptic fired here — correctly deferred to `LockScreen.runBiometric()` (no doubling) | 1 defect (hit target) | added `.contentShape(Rectangle().inset(by: -(Metric.hitMin - side)/2))` — visual badge unchanged, tap area now 44×44 | high | fixed |
| LockPasswordField | LockPasswordField.swift | master-password entry + submit, lock screen | placeholder honest ("Enter password") | **embedded login/submit button is 36×36pt — under the 44pt minimum** | **placeholder `Text` used raw `.font(.body)`**; **outer field `cornerRadius: 14`/button `cornerRadius: 10` were raw numeric literals** (exact `Radius.md`/`Radius.sm` matches — zero-diff token swap); asymmetric row padding (leading 14/trailing 6/vertical 6) has no exact `Space` token but is a deliberate fit for the embedded 36pt button — left as-is, documented | empty(button disabled+dimmed)/typed/busy(spinner replaces arrow) all covered | 3 defects (hit target, typography, radius tokens) | button hit area padded via `.contentShape` inset to 44pt (visual button stays 36pt); `.font(.body)`→`.vaultType(.body)`; `14`→`Radius.md`, `10`→`Radius.sm` | high (hit target) / medium (typography/radius) | fixed |
| LockScreen | LockScreen.swift | "unlock, fast" | subtitle logic truthful per mode (biometric/password/requireSlide); "Unlocking" a11y announcement present during ∞-gate motion | slide/biometric/password modes gate correctly (verified `requireSlide`/`canUseBiometrics` logic untouched — presentational-only changes made) | **"Forgot password?" button and inline error `Text` both used raw `.font(.footnote)`**; **`mode`/`requireSlide` transition springs and the bio-fallback `withAnimation` did NOT go through the file's own already-declared `reduceMotion` env var** (inconsistent with the correctly-gated `bioAuthenticating`/`busy` animation two lines above) | biometric/password/requireSlide/error/busy(∞-gate) all covered; regression-checked against the prior Controlled Reveal pass — no logic touched | 2 defects (typography, partial Reduce Motion gating) | `.font(.footnote)`→`.vaultType(.footnote)` ×2; 3 animation sites wrapped via `.vault(_, reduceMotion: reduceMotion)` (same var already in scope) — **no changes to biometric trigger logic, slide gating, or attempt counters** | medium | fixed |
| RecoveryView | RecoveryView.swift | "recover without a reset" | error copy honest | Recover/fields ≥44pt (uses `VaultSheetScaffold` + `RevealableSecureField`, both Phase-1 owned/frozen) | **recovery-key field: `.font(recoveryKey.isEmpty ? .body : .vaultCode())` raw `.body`**; **`cornerRadius: 12` + `.padding(.horizontal, 14)` drift from `RevealableSecureField`** (same defect class as `JoinByRecoveryView` — identical field pattern duplicated 3×) | empty/typed/busy(ProgressView overlay)/error all covered | 2 defects (typography, token drift) | ternary→`VaultType.body.font`; radius→`Radius.sm`, padding→`Space.s3` | medium | fixed |
| SlideToUnlock | SlideToUnlock.swift | deliberate-unlock confirmation after a shake-lock | label "Slide to unlock" VI checked | **knob = `height - inset*2` = 56-8 = 48pt ≥44 — passes by construction**, no fix needed | `height: CGFloat = 56` and `inset: CGFloat = 4` were raw literals that happen to equal `Metric.rowHeight`(56)/`Space.s1`(4) exactly | idle/dragging/completed(snap to end)/released-early(snap back) all covered; completion haptic (`Haptics.success`) correct per vocabulary (not doubled — `LockScreen` fires no haptic on slide-confirm) | 1 low defect (magic numbers, zero-diff token opportunity) | `56`→`Metric.rowHeight`, `4`→`Space.s1` (exact values, no visual change) | low | fixed |
| — (review-exempt) | `Vaultify/Security/UserActivityMonitor.swift` | n/a — invisible idle-timer probe, `allowsHitTesting(false)`, no rendered pixels | n/a | n/a | n/a | n/a | none (out of design-DNA scope per Phase 0) | — | — | pass, review-exempt |

## Deferred / documented, not fixed

- **`LockPasswordField`'s asymmetric row padding** (leading 14 / trailing 6 / vertical 6) has no
  exact 4pt-grid token — it's tuned so the row height matches the embedded 36pt login button.
  Forcing `Space.s3`/`Space.s2` would change the row's proportions around that button. Left as a
  documented exception (comment added in code).
- **`ChooseThemeView`'s `Divider().padding(.leading, 54)`** — a computed alignment value
  (`Space.s4`(16) + swatch(26) + `Space.s3`(12) = 54), already commented in code. Not a raw
  magic number in spirit; left as-is.
- **`LockScreen` is not wrapped in a `ScrollView`** (fixed `Spacer()`-centered layout, matching the
  LaunchScreen hand-off exactly per its own code comment). This is the same defect class fixed on
  5 onboarding steps in this phase, and could theoretically clip at AX-XXL on SE with a long error
  message. Per the phase brief's explicit risk note ("LockScreen regression from prior pass —
  diff-review before edit") and "presentational only, no redesign" instruction, restructuring this
  security-critical, recently-shipped screen's root layout was judged out of scope for this pass
  without device-level AX-XXL verification. **Flagged for Phase 15 / a follow-up device QA pass**,
  not silently dropped.

## Haptics vocabulary check

All `Haptics.` call sites in owned files verified against the vocabulary table:

| Site | Event | Haptic | Verdict |
|---|---|---|---|
| `EmergencyKitView.swift:88` | Emergency Kit PDF saved | `.success` | correct — one-time completion confirmation, not doubled |
| `CreateMasterPasswordView.swift:104` | vault-creation submit failure | `.error` | correct |
| `ChooseThemeView.swift:49` (added) | theme selection | `.tap` | correct — matches sibling `RevealableSecureField`'s reveal-toggle precedent |
| `SlideToUnlock.swift:53` | slide-to-unlock confirmed | `.success` | correct, single-fire (LockScreen fires nothing on this path) |
| `LockScreen.swift:207` | biometric auth failure | `.error` | correct |
| `LockScreen.swift:224` | password unlock failure | `.error` | correct; distinct flow from bio failure, not doubled |
| `RecoveryView.swift:88` | vault recovery failure | `.error` | correct |

`BiometricBadge`'s tap-to-retry fires no haptic of its own (correctly defers to `LockScreen`'s
`runBiometric()` failure path) — confirmed no doubling, matching the phase brief's explicit todo.

## Full re-run of the 6 audit greps (post-fix)

1. **Raw fonts**: 0 hits except `OnboardingFlow.swift:244` (`Image(systemName:)` FaceID glyph icon
   sizing via `Metric.iconUtility` — documented SF-symbol exception, not text typography).
2. **Raw numeric radii**: 0 hits.
3. **Raw numeric paddings**: 0 hits except `ChooseThemeView.swift:53` (documented computed
   alignment, see above) and `LockPasswordField.swift:40-42` (documented asymmetric embedded-button
   fit, see above). `SlideToUnlock.swift:40 .padding(inset)` uses the now-tokenized `inset` constant.
4. **Raw colors**: 0 hits except documented exemptions — `ChooseThemeView`'s literal light/dark
   preview swatches, `RecoveryScannerSheet`'s camera-overlay white/black pill+title.
5. **Haptics**: all 7 call sites verified against vocabulary, no doubling (table above).
6. **Fixed frames / GeometryReader / minimumScaleFactor**: all `.frame(width:...)` hits are either
   `Metric.*` tokens or documented literal swatches (26pt theme-preview circle, 22pt biometric SF
   glyph inside a fixed badge). `GeometryReader` usages are the intentional scroll-safety technique
   (`OnboardingStepHeader.OnboardingScrollingStep`, `SlideToUnlock`'s drag-track sizing).

**Status:** DONE
**Summary:** 24 surfaces reviewed (23 + 1 review-exempt). 16 defects found and fixed (2 high hit-target,
1 medium hit-target, 5 Reduce-Motion gaps, 1 missing haptic, 1 theme-accent bug, 6 typography/token-drift,
1 magic-number cleanup) plus 5 AX-XXL scroll-safety fixes (new shared `OnboardingScrollingStep` helper
added to `OnboardingStepHeader.swift`, applied to `EnableBiometricView`, `OnboardingDoneStep`,
`JoinMethodChoiceView`, `JoinByQRView`, `JoinByRecoveryView`). LockScreen: 2 typography + 3 Reduce-Motion
fixes applied (presentational only — biometric trigger logic, slide gating, and attempt counters
untouched, per the phase's security-critical constraint); LockScreen's own AX-XXL scroll-safety left
deferred/documented per explicit regression-risk guidance. Zero shared-component-request needed (no
DesignSystem/Phase-1 file required a change). Zero new/changed user-facing strings (strings-manifest is
empty by design — every fix was presentational/structural, no copy changed). Compile: app + AutoFill
extension both green.
