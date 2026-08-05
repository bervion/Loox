# Researcher 02 — Design System Digest (for cinematic animated story screen)

Sources read: `docs/design-dna-standard.md`, `docs/design-guidelines.md`,
`Vaultify/DesignSystem/Tokens/{Spacing,Radius,Metrics,Motion,Elevation,ContentWidth}.swift`,
`Vaultify/DesignSystem/Typography.swift`, `VaultifyCore/Theme/AppTheme.swift` + `AppTheme+Tokens.swift`,
`VaultifyCore/Localization.swift`, `Vaultify/DesignSystem/Icons/*`, animation-heavy screens
(`LooxSwirlAnimationView`, `LooxLogoBreatheView`, `LooxCloudAnimationView` + `BrandAnimation/*`,
`GlyphResolveText`, `TotpCardView`, `MeshGradientView`, `RootView.controlledReveal`,
`ZoomNavigationTransition`).

## 1. The 10 DNA rules (acceptance bar — `docs/design-dna-standard.md`)

Formula: **top-tier = system familiarity × product personality**. Cover the logo — screen must still read as Loox.

1. **One protagonist per screen** — screen answers ONE question; anything competing gets demoted or cut.
2. **Glass is for controls, canvas is for content** — material/glass only on control layers (bars, floating clusters); content on canvas; cards only for true semantic grouping.
3. **Concentricity** — nested rounded shapes use `Radius.concentric(outer:inset:)` (`R_inner ≈ R_outer − inset`, floored at `Radius.xs`); standalone shapes use the scale.
4. **Typography is architecture** — only `vaultType` roles; raw `.font(.system…)` in feature code is a defect. Secrets/codes: `Font.vaultCode` (SF + tabular digits). OTP grouped `381 942`.
5. **Motion explains spatial relationships (Controlled Reveal)** — product physics = reveal/conceal; use the shipped verb vocabulary, no decorative "wow" animation; motion NEVER gates a security result; every effect collapses to instant swap under Reduce Motion.
6. **One-handed ergonomic hierarchy** — F0/F1 actions in thumb zone; hit targets ≥ `Metric.hitMin` (44pt), small glyphs get invisible padded hit areas.
7. **Progressive disclosure + no button walls** — max ONE filled primary + at most one quiet secondary per screen state; 3+ stacked buttons = defect. Completion screens design for the one next action. Destructive actions once per screen, in a menu, with confirmation.
8. **Personality in micro-detail, "calm intelligence"** — short, still, confident copy. NO "!", NO em-dash "—", NO interpunct "·", no emoji cheerleading. Copy never lies. EN+VI ship together; design for VI (longest).
9. **Physics: Controlled Reveal** — nothing exposed before needed; fixed-length masks (never leak secret length); reveal local + deliberate; conceal instant.
10. **Search is a superpower** — (not relevant to story screen).

### Adversarial review protocol (answers filed IN WRITING per screen in the plan report)
1. **Protagonist** — one job; first glance serves it; what competes and why not demoted?
2. **Every text** — read aloud EN + VI; calm/honest/shorter-than-could-be; no "·"/"—"/"!"; VI fits at SE width (375pt)?
3. **Every control** — thumb-reachable one-handed; ≥44pt hit box; purpose obvious; feedback (visual + correct haptic)?
4. **Every space and shape** — every padding a `Space` token; every radius from scale or `concentric`; nothing pinched/flared/floating unanchored?
5. **Every state** — empty/one/many/loading/error/locked each intentional; no scaffolding exposed?

### Multi-device acceptance matrix
- Widths: SE 375pt AND Pro Max 430pt, tested with LONGEST localized string (usually VI).
- Regular width (iPad 11" fullscreen + Split View pane): full-screen surfaces (onboarding, lock) clamp via `.vaultContentWidth(.form/560, .reading/640, .wide/960)` — never stretch iPhone layout.
- Dynamic Type: default, XL, accessibility XXL; `minimumScaleFactor` last resort, never <0.7; reflow not shrink.
- Appearance: light AND dark, live theme switch without restart, semantic roles only.
- Accessibility: Reduce Motion (instant swaps), Reduce Transparency (solid fallbacks), VoiceOver (meaningful labels; decorative views `.accessibilityHidden(true)`).
- Locales: EN and VI both rendered and eyeballed.

## 2. Motion tokens + contract (`Tokens/Motion.swift`)

```swift
Motion.fast = 0.14s   Motion.base = 0.20s   Motion.medium = 0.26s   Motion.slow = 0.32s
Motion.standard = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.20)  // Apple ease-out
Motion.spring   = .spring(response: 0.34, dampingFraction: 0.86)           // low-bounce
Motion.pressScale = 0.97
Animation.vault(_ animation:, reduceMotion:) -> Animation?  // nil (instant) under Reduce Motion
```
- Guideline: durations stay ≤ ~0.4s for interaction motion. Long choreography (brand animations) is precedent-allowed but must be `accessibilityHidden(true)` and hold a static frame under Reduce Motion.
- Motion verb vocabulary (do NOT invent new verbs, pick a matching one):
  - secret reveal → glyphs resolve L→R (`GlyphResolveText`, fixed 0.4s budget regardless of length)
  - unlock → world blurs away (`AnyTransition.controlledReveal` in `App/RootView.swift:200` — opacity 0 + blur 10 + scale 1.05 active state)
  - lock → contract-in, content vanishes instantly (privacy)
  - derivation in flight → gate draws itself open (NOTE: `LooxGateShape`/`LooxGateMark` referenced in design-guidelines.md do NOT exist in repo — doc drift; current loading brand indicator is `LooxSwirlAnimationView(.loop)`)
  - copy → clipboard glyph morphs to check (`CopyMorphIcon`)
- Reduce Motion pattern actually used everywhere: `@Environment(\.accessibilityReduceMotion)` + either `Animation.vault(..., reduceMotion:)`, `reduceMotion ? nil : .easeInOut(...)`, or frozen `TimelineView` frame (`LooxSwirlAnimationView.frozenTime`, `LooxLogoBreatheView` phase=0).

## 3. Haptics vocabulary (`Vaultify/Services/Haptics.swift`, `@MainActor enum Haptics`)

One physical event = one haptic, fired from SERVICE layer, never doubled by a view:
- Copy → `Haptics.success()` (fired by `ClipboardService` — views must NOT add another)
- Destructive confirm / auth failure → `Haptics.error()`
- Risky state entered → `Haptics.warning()`
- Selection / toggle / minor action → `Haptics.tap()`
- Scroll, navigation, appear → **none** (a story screen's scene changes get NO haptics)

## 4. Tokens relevant to a full-screen dark cinematic scene

**Spacing** (`Space`, 4pt grid): s1=4 s2=8 s3=12 s4=16 s5=20 s6=24 s7=32 s8=40 s9=48 s10=64;
`Space.gutter` (adaptive 16/20, SCREEN-edge insets only; interiors fixed `s4`); `Space.contentMax`=430.

**Radius**: xs 6 · sm 10 · md 14 · lg 20 · xl 28 · pill 999; apply via `.vaultCornerRadius(_)` (continuous/squircle); nested = `Radius.concentric(outer:inset:)`.

**Metric**: hitMin 44 · controlSmall 34 / Medium 44 / Large 52 (primary CTA = full-width controlLarge) · rowHeight 56 · icons: compact 16 / inline 20 / utility 24 / tab 28 / tile 32 / tileLarge 40 · avatarHero 92.

**Elevation**: level0/1/2 now cast NO shadow (flat rebrand); only level3 (radius 30, y10) and .sheet (radius 40, y-8) lift; opacity dark 0.55 / light 0.10. Never glowing.

**Typography** (`VaultType` → Dynamic Type): largeTitle (.largeTitle bold, rare root identity screens — a story screen title qualifies) · screenTitle (.title2 bold) · section (.title3 semibold) · headline · body · callout · subhead · footnote · caption · sectionLabel (.footnote semibold ALL-CAPS). One fixed-size exception exists (`scoreDisplay` 58pt bold, gauge only). `Font.vaultCode(style/size, weight)` for any secret/code shown. No third-party typeface, never mono the whole app; aligned numerals get `.monospacedDigit()`.

**Color** — packed `0xRRGGBB` UInt32 on `AppTheme`; UI edge via `Color(rgb: theme.<token>)`, `.themedForeground(role)`, `theme.color(role)`. `ThemeRole`: primary/secondary/tertiary/disabled · iconPrimary/Secondary/Disabled · accent/accentText/accentSoft/onAccent · destructive/onDestructive/success/warning.
- Stored: background, secondaryBackground, groupedBackground, elevatedBackground, barBackground, primary/secondary/tertiary/placeholderText, accent (+accentForeground, linkAccent), separator, border, controlBackground, switchOn/checkmark/selection, destructive/success/warning, overlayDim.
- Derived (`AppTheme+Tokens.swift`, free for every theme): surfaceBase/Elevated, surfaceFloatingSolid, surfacePressed, iconPrimary/Secondary/Disabled, textDisabled, accentSoft/accentPress/accentFill/accentText, separatorOpaque, onDestructive/onSuccess/onWarning, destructiveSoft/successSoft/warningSoft, warningText/destructiveText.
- Contrast: accent-as-fill 3:1, accent-as-text use `accentText` (guarded 3:1 on control+soft surfaces); onAccent WCAG-derived (`RGBMath.onColor`), text 4.5:1.
- **Raw `.white`/`.black` ban with precedent exception**: brand-animation surfaces (LooxSwirl dots, glow, star, memoji discs) DO use raw `.white` + fixed brand gradients (`.looxBlue/.looxDeep`, `LooxCanvas.logoGradients`, `SwirlGradient` asset) — a cinematic brand story scene can follow that precedent for its DECORATIVE layer, but all TEXT/controls must stay on semantic roles and survive light+dark. If the scene commits to one dark look, it must still be deliberate in light mode (no invisible text).
- Decorative wallpapers gated OFF (`WallpaperFeature.decorativeEnabled = false`); do not resurrect the wallpaper engine for the story screen without a flag decision.
- Full-screen surface on iPad: clamp `.vaultContentWidth(.form)`.

## 5. Copy style rules

- NO "!", NO em-dash "—", NO interpunct "·" in user-facing strings; separate ideas with layout (two lines, label+value) or real words.
- Short, still, confident, never lies, no emoji cheerleading.
- VI is first-class and usually the LONGEST rendering — design layout for VI first, verify at SE 375pt.
- Read every string aloud in EN and VI during review (adversarial protocol item 2).

## 6. Localization mechanics for new strings

- Catalog: `Vaultify/Localizable.xcstrings` (single file, sourceLanguage "en", ~1900 keys with `vi` + `ja` stringUnits). Every new string needs EN source + **VI + JA** values (missing VI = bug per CLAUDE.md; JA also mandatory).
- SwiftUI `Text("…")` literals auto-extract on build — still add VI+JA values (same JSON structure).
- `LocalizedStringResource` titles must use `.inAppLocalized` (`VaultifyCore/Localization.swift:25`) — pins resource to `appResourceLocale` (in-app language toggle, not device locale).
- Runtime strings (outside SwiftUI): `appString(_ key:)` (`Localization.swift:34`). Stored field labels: `appLabel(_:)`.
- iOS 17.3 trap: `TextField`/`SecureField` with `LocalizedStringResource` title is iOS 26+ → use `LocalizedStringKey`.
- Safari extension `_locales` not relevant for a native screen.

## 7. Icon rules

- Polaris asset set (`Assets.xcassets/PolarisIcons` incl. `dt_*` duotone) is the app's icon language; render ONLY via `VaultIcon(name, size: Metric.icon*)` (`DesignSystem/Icons/VaultIcon.swift`) or `Image(vaultIcon:)` where a raw Image is genuinely required (resizable decorative glyph). Never `Image(systemName:)` / `Image(name)` / `Label(_, image:)` / `UIImage(named:)` — an `sf:` token passed there renders BLANK silently.
- `Icons` enum = chrome tokens (`ic_*` asset names, e.g. `Icons.lock`, `Icons.shield`); never convert a chrome token to SF.
- `IconResolver`: `sf:` prefix → SF Symbol, else asset. SF Symbols only as picker choices + documented exemptions (icloud family, envelope.fill).
- SF floor = iOS 17.3: newer symbols compile but render BLANK; allowlist `VaultifyTests/Fixtures/sf-symbols-ios-17-3.txt` is test-enforced for catalog symbols.
- `dt_house`, `dt_coins`, `dt_shield` imagesets are pathless (render blank) — excluded; don't use them.
- Decorative icons "should be rare"; icon-only controls need accessibility labels; purely decorative animation layers `.accessibilityHidden(true)`.

## 8. Existing particle/gradient/animation code to reuse (NO Metal, NO SwiftUI Shader API in repo)

Searched: zero `.metal` files, zero `colorEffect/distortionEffect/layerEffect/ShaderLibrary` usage. All motion is Canvas/TimelineView/CoreAnimation. Reusable inventory:

- **`LooxSwirlAnimationView`** (`DesignSystem/Components/`, 255 ln) — THE particle system: `TimelineView(.animation)` + `Canvas` drawing 4 rings × 24 white dots masking a `SwirlGradient` rainbow mesh image; modes `.reveal` (one-shot emanation, 1.6s) / `.loop` (breathing loading pulse) / `.dismiss` (burst outward 1.0s); easeOutCubic, ring stagger 0.2s, stops ticking when done; Reduce Motion → frozen settled frame; supports custom center glyph (`centerIcon`/`centerSystemImage`/`centerTint`). Best base for cinematic particle moments.
- **`LooxCloudAnimationView` + `BrandAnimation/` engine** (~1000 ln total) — the launch/landing story choreography: deterministic pure-function-of-time timeline (`LooxTimeline.phase(at:)` — 12.5s loop: logo → burst → 3 themed clusters → converge), `LooxEase` (smoothstep, inOut, clamp01), ghost-frame fake motion blur, screen-flooding bloom disc (`LooxLaunchResolver.bloomState`, floodDiameter boost for iPad), memoji video discs (`LooxMemojiPlayerView`), radial glow + star sparkle layers, `LooxCanvas` fixed-geometry canvas with scale-to-fit math. This IS the house pattern for a multi-scene cinematic sequence: derive every visual property from elapsed time, no imperative animation state.
- **`LooxLogoBreatheView`** (73 ln) — idle "alive" brand mark: ~4s sine breathe (scale 1±0.02 + glow pulse) via TimelineView; Reduce Motion holds phase 0.
- **`LooxAnimationThemes` / `LooxAnimationGeometry`** — orbit specs, gradients, canvas constants.
- **`GlyphResolveText`** (80 ln) — L→R glyph resolve within fixed 0.4s budget; reuse for any "text decrypts into view" story beat.
- **`AnyTransition.controlledReveal`** (`App/RootView.swift:200`) — blur(10)+opacity+scale(1.05) modifier transition; the unlock/reveal verb.
- **`MeshGradientView` + `MeshGradientRenderer`** (Wallpaper/Mesh + VaultifyCore/Theme/Mesh) — Telegram-style animated mesh WITHOUT Metal: bakes 16 interpolated 80×80 frames, plays via `CAKeyframeAnimation` on layer contents (GPU-composited, zero ongoing cost); honors Reduce Motion. Currently unreachable (wallpapers gated off) but fully working — candidate for a slow ambient cinematic backdrop.
- **`TotpCardView`/`TotpRingView`** — shared `TimelineView(.periodic(by: 1))` tick pattern (one timeline, many cards); ring→numeric-countdown swap under Reduce Motion.
- **`ZoomNavigationTransition`** — iOS 18+ `.navigationTransition(.zoom)` with environment-injected namespace; no-op on 17.x/Reduce Motion.
- **`WelcomeLandingView`** — onboarding hand-off pattern: `withAnimation(.easeOut(duration: 0.25).delay(0.35)) { contentHidden = true }` + reduceMotion early-exit branch before launch transition.
- Gradients in use: `LinearGradient` (brand `.looxBlue/.looxDeep`), `RadialGradient` (white glow), prerendered `SwirlGradient` image asset masked by Canvas. `AngularGradient` in TotpRing/WatchtowerScoreRing.

## Key constraints summary for the story screen spec

- Choreograph as pure function of time (LooxTimeline pattern), TimelineView-driven; stop ticking when a one-shot completes.
- Every beat needs a Reduce Motion resolution: frozen final frame or instant swap; screen must be fully usable with zero motion.
- Decorative layers `.accessibilityHidden(true)`; VoiceOver gets a meaningful text alternative + skip path.
- Skippable, never gates a security/consent result; primary CTA = one full-width `controlLarge` `.themedProminent`, at most one quiet secondary.
- Text on semantic roles, survives light+dark live switch; VI/JA longest-label layout at 375pt; `.vaultContentWidth(.form)` on iPad.
- All new strings → `Localizable.xcstrings` EN+VI+JA; titles `.inAppLocalized`; runtime `appString()`.
- No haptics on scene changes; `Haptics.tap()` only if user performs a selection-like action.
- iOS 17.3 API ceiling (no SwiftUI Shader assumptions violated — none used anyway; `colorEffect` etc. ARE available from 17.0 if we want them, but repo precedent is Canvas/CA, and CI stable-Xcode compatibility must be checked before introducing Metal shader files to the Tuist globs).

## Unresolved questions

1. `LooxGateShape`/`LooxGateMark` cited in design-guidelines.md motion table do not exist in the repo — was the gate mark removed intentionally (doc drift) or renamed? Affects which "derivation" verb the story screen may reference.
2. May the story screen commit to a single dark cinematic look in both light and dark modes (like brand animation surfaces do), or must its canvas follow the active theme? Docs allow raw white/brand gradients only for brand-animation precedent; needs owner call.
3. Is introducing SwiftUI `colorEffect`/`layerEffect` (Metal `.metal` file added to `Project.swift` sources) acceptable to CI/self-hosted runner, or should the spec stay on the proven Canvas/TimelineView/CAKeyframeAnimation stack? (Recommend the latter per YAGNI + repo precedent.)
4. Story screen skip/replay entitlement: does it replay from Settings (like Watchtower intro's `WatchtowerIntroGate` replays only on real data moments), or one-shot per install?
5. `SwirlGradient` asset is the only rainbow mesh texture; if the story needs new large decorative textures, asset-size budget and dark-mode variants need a decision.
