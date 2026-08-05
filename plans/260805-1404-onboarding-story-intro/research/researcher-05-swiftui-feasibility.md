# Researcher 05 — Pure-SwiftUI feasibility for "reactbits-grade" cinematic effects

Constraints recap: iOS 17.3 floor, stable-Xcode CI (iOS 18 API OK behind `#available`; iOS 26 API needs `#if compiler(>=6.2)` + `#available(iOS 26,*)` per CLAUDE.md), zero third-party packages, 60fps on iPhone 12-class, Reduce Motion must collapse everything. App helper: `Motion.vault(_:reduceMotion:) -> Animation?` (Vaultify/DesignSystem/Tokens/Motion.swift:25) returns nil under RM.

Verdict up front: everything requested is buildable at 17.3. The single highest-leverage tool is a **`.colorEffect` Metal shader** — it replaces MeshGradient, aurora, ripple, scramble-glow, and most "reactbits" backgrounds with one cheap full-screen fragment pass.

## 1. Metal shaders in SwiftUI — iOS 17.0, the workhorse

APIs (all iOS 17.0):
- `.colorEffect(Shader)` — per-pixel recolor. Metal sig: `[[stitchable]] half4 fx(float2 position, half4 color, <args>)`.
- `.distortionEffect(Shader, maxSampleOffset:)` — moves pixels. Sig returns `float2`.
- `.layerEffect(Shader, maxSampleOffset:)` — samples neighbors via `SwiftUI::Layer` (`#include <SwiftUI/SwiftUI_Metal.h>`, `layer.sample(pos)`).
- `ShaderLibrary.default.fxName(.float(t), .float2(size), .color(accent), .boundingRect)`; args also `.image`, `.data`.

Wiring: drop `Effects.metal` anywhere under `Vaultify/**` glob → `tuist generate` (file invisible until regen). Vendored first-party Metal source = fine (same posture as CArgon2). App target only.

Time/animation: shader args are NOT animatable. Drive with `TimelineView(.animation)` passing elapsed seconds as `.float`. Freeze the uniform (constant t) under Reduce Motion → static gradient for free.

Perf notes:
- `colorEffect` on a full-screen `Rectangle` = one fragment pass; trivial on iPhone 12 even at 120Hz. This is the aurora/mesh/ripple budget winner.
- `distortionEffect`/`layerEffect` force an offscreen rasterization of the layer every frame; cost ∝ layer pixel area + sampling radius. Declare `maxSampleOffset` honestly: too small clips the effect, huge values inflate the offscreen texture.
- **layerEffect over blurred layers (asked explicitly): bad.** `.blur`/`.ultraThinMaterial` are already offscreen passes; stacking `layerEffect` on top re-rasterizes the blurred result per frame → 2–3 chained offscreen passes on a large layer. On iPhone 12 that's the classic frame-drop recipe. Instead: bake the blur into the shader (cheap fake-blur/gaussian in Metal), or shade the un-blurred content and put material chrome ABOVE it as a sibling, not a parent.
- Shaders only affect SwiftUI-rasterized content — no effect on UIViewRepresentable-backed subtrees.
- First use of a shader compiles it lazily → possible one-frame hitch on entry. `Shader.compile(as:)` prewarm exists but I believe it's iOS 17.4+ (UNVERIFIED — see questions). Mitigation at 17.3: render the shader view once at 0 opacity a beat before the scene starts.

## 2. TimelineView + Canvas particles — iOS 15 base, safe at 17.3

- `TimelineView(.animation)` (or `.animation(minimumInterval:paused:)`) + `Canvas { ctx, size in } symbols: { … }`.
- **Symbol reuse is the batching trick**: declare each particle glyph ONCE in `symbols:`, `ctx.resolveSymbol(id:)`, then stamp N times with `ctx.draw(sym, at:)` + `ctx.translateBy/scaleBy/opacity`. Symbol is rasterized once; stamping is cheap GPU blits. For plain dots, `ctx.fill(Path(ellipseIn:))` is fine too.
- **Statelessness**: derive every particle position purely from `timeline.date` + a precomputed seed array (`let seeds = (0..<n).map { … }` built once). Never mutate `@State` per frame — that invalidates the whole view tree; a pure Canvas re-draw is the only per-frame work.
- Budget: 100–300 particles at 60fps is comfortable on iPhone 12. The killer is per-particle blur: `ctx.addFilter(.blur)` per draw is expensive — bake glow into the symbol (a pre-blurred circle symbol) instead.
- Canvas body runs on CPU each frame (drawing itself is Metal-backed). No allocations in the loop.
- TimelineView keeps ticking while in hierarchy: pause via `.animation(paused: reduceMotion || scenePhase != .active || !visible)`.
- Put the TimelineView leaf-deep so only the Canvas re-evaluates, not the whole screen.
- Reduce Motion: paused timeline → static scattered particles (or none).

## 3. keyframeAnimator / phaseAnimator — iOS 17.0

- `.phaseAnimator([Phase], trigger:) { view, phase in } animation: { phase in }` — no-trigger overload loops forever (idle breathing/orb drift).
- `.keyframeAnimator(initialValue:trigger:content:keyframes:)` with `KeyframeTrack(\.x)` + `LinearKeyframe/SpringKeyframe/CubicKeyframe/MoveKeyframe` — multi-property choreographed scene (logo drop + glow + settle).
- `KeyframeTimeline(initialValue:content:)` → `timeline.value(time:)` lets you SAMPLE keyframes manually — combine with TimelineView for looping, or with scroll offset for scrubbing a scene by scroll (the reactbits "storytelling" feel). This is the reliable loop/scrub mechanism; a `repeating:` keyframeAnimator overload exists in my memory but availability UNVERIFIED — don't depend on it.
- Trap: the `content` closure runs every animation frame. Keep it to transform-ish changes (offset/scale/opacity/rotation/blur-small); animating layout inputs (frame height, font size) triggers full layout per frame.
- Reduce Motion: skip trigger / jump straight to final keyframe value; wrap discrete animations with `Motion.vault`.

## 4. Scroll-driven storytelling

iOS 17.0 (all safe at floor):
- `.scrollTransition(axis:) { content, phase in }` — per-view enter/exit (`ScrollTransitionPhase.identity/.topLeading/.bottomTrailing`, `phase.value` in −1…1). Ideal for blur-in/scale-in of story sections.
- `.visualEffect { content, proxy in }` — per-view continuous effects from `proxy.frame(in: .scrollView)` (the `.scrollView` NamedCoordinateSpace is iOS 17). Runs render-side, does NOT invalidate layout — prefer this over GeometryReader for parallax/scale/hue. It cannot write state (read-only by design).
- `.scrollTargetBehavior(.paging)` / `.viewAligned` + `.scrollTargetLayout()`, `.scrollPosition(id:)`, `.containerRelativeFrame(.horizontal)`, `.scrollClipDisabled()`, `.defaultScrollAnchor`.
- iOS 17.x `.paging` had minor safe-area/inset glitches in early point releases — sanity-check on a 17.3 sim (flagged below).

iOS 18-only — guard `if #available(iOS 18, *)`:
- `.onScrollGeometryChange(for:of:action:)` (content offset/insets as Equatable derivation), `.onScrollVisibilityChange`, `.onScrollPhaseChange`, `ScrollPosition` type.

17.3 fallback for a global scroll offset (page index, progress bar, scrubbing a KeyframeTimeline): classic `GeometryReader` in the scroll content background + `PreferenceKey` bubbling `frame(in: .named("scroll")).minY`. Works fine; throttle writes (round to 0.5pt) so you don't invalidate on every sub-pixel change. Per-item effects should stay on visualEffect/scrollTransition (no state round-trip).

Perf: keep visualEffect/scrollTransition closures allocation-free; avoid `.blur` in scrollTransition across many rows (offscreen pass per row) — cap radius ≤ 8 and limit to hero elements, or use opacity/scale only.

## 5. Text effects

- **`TextRenderer` protocol — iOS 18.0** (`Text.Layout`, iterate `RunSlice`s, `.textRenderer(...)`). Per-glyph blur-in reveal, shimmer, glitch. Use behind `#available(iOS 18,*)`; stable CI Xcode has the iOS 18 SDK so no compiler gate needed.
- 17.3 fallback — character/word split: `HStack(spacing:0) { ForEach(indexed chars) { Text(String($0)) } }` with staggered `.opacity + .blur + .offset` and `.delay(Double(i) * 0.03)`.
  - **Localization trap (EN/VI/JA app)**: per-char HStack kills line wrapping; word-split fails for JA (no spaces); VI diacritics are fine as chars. Safe policy: hero single-line text only for per-unit reveal; multi-line body text gets whole-block blur-in (`.blur(12→0) + opacity`, one offscreen pass, localization-proof). Design DNA already says design for longest label (VI).
- **Scramble/decrypt at 17.3**: TimelineView (~15–20Hz, not 60) rebuilding a display string — resolved prefix + random glyphs for the rest. Must use a monospaced font (`.monospaced()`; `Font.vaultCode` only guarantees tabular DIGITS) or width jitters. `.contentTransition(.identity)` to stop crossfade flicker. Keep strings short (Text re-layout per tick is CPU). JA flavor: katakana glyph pool. Very on-brand for a vault ("decrypting…").
- `contentTransition(.numericText(value:))` — iOS 17.0 (countsDown variant is 16.0). Pair with `withAnimation` on value change + tabular digits. Perfect for counters/TOTP-style beats.

## 6. Glass at 17.3 vs iOS 26 Liquid Glass

- 17.3 recipe: `.background(.ultraThinMaterial, in: .rect(cornerRadius: Radius.lg))` + accent-tint overlay at low opacity + 1pt `LinearGradient` stroke (white 0.35→0.05) + soft `.elevation(.level2)`. Reads as premium glass on every 17.x device.
- iOS 26 `glassEffect(_:in:)` / `GlassEffectContainer`: gate with `#if compiler(>=6.2)` + `#available(iOS 26,*)` + material fallback (CLAUDE.md-mandated pattern). Optional garnish only — do not make the story depend on it.
- Perf of stacked blurs: every material = a backdrop-sample+blur offscreen pass of everything behind it. 2–3 non-overlapping materials on screen is fine on iPhone 12; OVERLAPPING materials multiply passes. Material sitting on top of a live shader background is fine (shader is cheap); material on top of Canvas particles + shader + scrolling simultaneously → profile it.
- Reduce Transparency: materials go opaque automatically — re-check contrast (design DNA matrix already requires this pass).
- Never animate blur radius of a big layer per frame; never glass on content cards/rows (design guideline).

## 7. Haptics choreography

- **`.sensoryFeedback(_:trigger:)` is iOS 17.0 — confirmed, not 17.5.** (macOS 14, watchOS 10.) Variants: plain trigger; `condition:` closure; feedback-returning closure `{ old, new in … }`. Types at 17.0: `.impact(weight:intensity:)`, `.impact(flexibility:intensity:)`, `.selection`, `.success/.warning/.error`, `.increase/.decrease`, `.alignment`, `.levelChange`, `.start/.stop`.
- Beat sync patterns:
  - Bump an `Int` beat-counter state at choreography boundaries (phaseAnimator `onChange(of: phase)`, or iOS 17 `withAnimation(completionCriteria: .logicallyComplete) { } completion: { beat += 1 }`), with `.sensoryFeedback` keyed to the counter. Good to ~1 frame accuracy; simplest; respects the app's haptics vocabulary (docs/design-dna-standard.md).
  - Sub-second patterns (unlock "thunk-tick-tick-seal"): CoreHaptics — `CHHapticEngine` + `CHHapticPattern` of relative-time `CHHapticEvent`s (+ `CHHapticParameterCurve` for swells), fire once aligned to the keyframe timeline start.
- CoreHaptics traps: `engine.start()` has latency — pre-warm on screen appear; set `resetHandler`/`stoppedHandler` (engine dies on background); check `CHHapticEngine.capabilitiesForHardware().supportsHaptics`; iPad = no haptics, no-op gracefully; Mac slice: guard out entirely.
- Reduce Motion does NOT disable haptics by system default — decide deliberately (suggest: keep gentle haptics, drop animation).

## 8. MeshGradient (iOS 18) — 17.3 aurora fallback

`MeshGradient(width:height:points:colors:)` is iOS 18.0. Options for 17.3, ranked:
1. **`colorEffect` shader (recommended, and use it on iOS 18 too — one codepath, KISS)**: full-screen Rectangle, fragment = sum of 3–4 drifting radial falloffs (or cheap value-noise/fbm) blended into theme accent hues, time uniform from TimelineView. Single GPU pass, indistinguishable from animated MeshGradient, trivially 60fps on iPhone 12. RM: constant t → static aurora.
2. Blurred-blob ZStack: 3–5 `Circle().fill(RadialGradient)` + `.blur(50–70)` + slow keyframed offsets. Looks right but large-area blur re-renders offscreen every animated frame — risky on iPhone 12 when combined with materials. Acceptable for a STATIC backdrop (blur once, then animate only opacity/hue of the flattened group via `.drawingGroup()`).
3. Canvas + `ctx.addFilter(.blur)` + gradient fills in TimelineView — middle ground, more CPU than (1), no reason to prefer.
Skip availability-branching to real MeshGradient unless you want point-animation semantics; visual parity across 17/18 is easier with the shader everywhere.

## Cross-cutting for Vaultify

- Reduce Motion collapse plan: `@Environment(\.accessibilityReduceMotion)` at the scene root → freeze shader t, pause TimelineViews, zero particles, replace keyframe scenes with final-state + opacity crossfade, keep haptics decision explicit. Route all discrete animations through `Motion.vault(_:reduceMotion:)`.
- Also pause everything on `scenePhase != .active`; onboarding is short-lived so battery is a non-issue, thermal only if shader+particles+materials run unpaused in background.
- ProMotion devices tick `TimelineView(.animation)` at 120Hz — use `minimumInterval: 1/60` for particles/scramble; let the shader run free (per-pixel cost, not per-tick CPU).
- Tokens: no hardcoded visual constants — radii via `Radius`, motion via `Motion`, colors via `ThemeRole`/`theme.color`; accent-aware shader args (`.color(theme accent)`) keep the aurora on-theme.
- New .metal file + any new strings: `tuist generate` after adding files; every string EN+VI+JA.
- Copy rule reminder: no "!", no em-dash, no "·" in user-facing onboarding copy.

## Unresolved questions

1. `Shader.compile(as:)` prewarm — believed iOS 17.4+; verify in SDK headers. If so, at 17.3 use the hidden-preflight-frame trick instead.
2. `keyframeAnimator(initialValue:repeating:content:keyframes:)` looping overload — exact existence/availability unverified; `KeyframeTimeline` + TimelineView is the guaranteed loop/scrub path.
3. Real iPhone 12 headroom for the worst-case composite (full-screen shader + ~150 particles + 2 materials + scrollTransition blurs) — needs an on-device Instruments pass (Core Animation FPS + GPU); no simulator verdicts.
4. iOS 17.3-specific `.scrollTargetBehavior(.paging)` inset/safe-area quirks — verify on a 17.3 simulator before committing to ScrollView paging over `TabView(.page)`.
5. `SensoryFeedback.pathComplete` — possibly watchOS-only; avoid, stick to the 17.0 set listed.
6. Whether current stable CI Xcode ships the iOS 26 SDK (CLAUDE.md implies yes via the TextField trap) — moot in practice: the mandated `#if compiler(>=6.2)` + `#available(iOS 26,*)` double guard is safe either way.
