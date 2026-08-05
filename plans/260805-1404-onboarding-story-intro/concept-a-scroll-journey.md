# Concept A — "One Continuous Scroll Journey" (story intro, post-onboarding)

One-time cinematic scrollytelling screen shown at the first frame of `.unlocked`, before the Home tutorial. The user physically pulls the story forward: chaos (passwords everywhere) → consequence (one leak opens every door) → turn (the scroll gathers them) → sanctuary (one private vault) → commitment (enter the vault). Built entirely on the proven house stack: TimelineView + Canvas particles + one `colorEffect` Metal shader + iOS 17 scroll APIs. No packages, iOS 17.3 floor respected.

Sources: researcher-01 (flow seam), researcher-02 (design system), researcher-03 (reactbits catalog), researcher-04 (benchmarks + stats), researcher-05 (SwiftUI feasibility).

---

## 1. Narrative arc

Six beats, one continuous vertical scroll. Total content = 6 full-height pages. Target dwell 45–75 s read at natural pace; a rushed scroll completes in ~10 s; skip is available from the first frame. The story never gates anything (DNA rule 5: motion never gates a result).

| # | Beat | Emotion | What the audience feels | Stage state |
|---|------|---------|--------------------------|-------------|
| 1 | **Hook** | Curiosity, recognition | "Wait, where ARE my passwords?" | Near-black veil, one lonely glowing dot |
| 2 | **Chaos** | Sheepish self-recognition | "That is literally me" | Dot multiplies into ~120 drifting scraps (notes, chats, browser) |
| 3 | **Consequence** | Quiet unease (warning, not horror) | "Oh. That could actually hurt me" | One scrap clones itself across the field, pulses warning hue; live attack counter |
| 4 | **Turn** | Agency, hope | "I am fixing this right now, with my own hand" | Scroll scrubs every scrap converging to center |
| 5 | **Sanctuary** | Calm, relief | "This is what safe feels like" | Ordered ring around the Loox mark; stage resolves into the user's own theme |
| 6 | **Commitment** | Resolve | "Lock them in. I am doing this" | Ring tightens around the mark above one CTA; tap seals the vault |

**Skip affordance**: quiet "Skip" text control, top-trailing, fades in with beat 1's copy (~0.8 s), padded to a 44 pt hit area, present for the rest of the journey. Skipping sets the same completion flag as finishing (researcher-01 lock-interplay rule: set flag on BOTH finish and skip) and logs `outcome: "skipped"`.

**Emotional design cribs** (researcher-04): Opal's mirror → dread → hope → commitment ritual arc; Proton Pass "one idea per screen"; Arc "end the story early, get out of the way"; Blinkist Psych audit — no permission prompts, no questions, nothing draining mid-story. Max 2 stats total (Pew 69%, Microsoft 7,000/s), phrased as worldwide figures in VI (no Vietnam-specific data exists).

---

## 2. Why guided free scroll (not strict paging, not fully free)

**Choice: continuous scroll + `.viewAligned` snapping over full-height beats.**

- The signature moment (beat 4, convergence scrubbed by the user's finger) requires CONTINUOUS scroll offsets — strict `.paging`/`TabView(.page)` quantizes the gesture and kills the "you are pulling them home" physicality.
- Fully free scroll can release mid-beat: copy stuck half-blurred, stage mid-morph. `.viewAligned` + `scrollTargetLayout()` with `.containerRelativeFrame(.vertical)` beats means every release lands a composed page while the DRAG remains continuous (effects scrub live during the gesture, exactly the Apple-product-page feel).
- `.scrollTargetBehavior(.paging)` has known iOS 17.x early-point-release inset quirks (researcher-05 §4); `.viewAligned` with full-height items gives identical snap semantics with less risk. Verify both on a 17.3 simulator; the design degrades gracefully to plain free scroll if snapping misbehaves (all effects are offset-driven, none depend on snap).

---

## 3. Architecture (two layers, one scalar)

```
ZStack {
    StoryStageView(progress: journeyProgress)   // pinned, full-bleed, decorative
    ScrollView(.vertical) {                      // the narrative column
        VStack(spacing: 0) { 6 × StoryBeatView } // each .containerRelativeFrame(.vertical)
            .scrollTargetLayout()
    }
    .scrollTargetBehavior(.viewAligned)
    .scrollIndicators(.hidden)
    SkipButton (top-trailing overlay)
}
```

- **`journeyProgress` (0…1)** = scrollOffset / (contentHeight − viewport). iOS 17.3: `GeometryReader` in the scroll content background bubbling `frame(in: .named("story")).minY` via `PreferenceKey`, writes throttled by rounding to 0.5 pt (researcher-05 §4). iOS 18+: `if #available(iOS 18, *)` → `.onScrollGeometryChange(for: CGFloat.self)`. One scalar drives everything.
- **StoryStageView** = `TimelineView(.animation(minimumInterval: 1/60, paused: paused))` wrapping:
  1. `Rectangle().ignoresSafeArea().colorEffect(ShaderLibrary.default.storyAurora(.float(t), .float(progress), .float2(size), .color(accent), .color(warn)))` — ONE full-screen fragment pass does veil, aurora, warning tinge, and the calm accent close (researcher-05 §1, §8: budget winner on iPhone 12).
  2. `Canvas { … } symbols: { … }` — ≤120 "scrap" particles. Each scrap = seeded struct (scatter position, drift phase, size, kind). Kinds rendered ONCE in `symbols:` (rounded-rect card + `Image(vaultIcon:)` Polaris glyph: note, chat bubble, globe, key dot) then stamped via `ctx.draw(resolveSymbol:at:)` — batching per researcher-05 §2. Glow pre-baked into a blurred circle symbol, never `ctx.addFilter(.blur)` per particle.
  3. Every visual property is a **pure function of (t, journeyProgress, seeds)** — the LooxAnimationEngine house pattern (researcher-02 §8). No per-frame @State.
  - `paused = reduceMotion || scenePhase != .active`; the whole stage is `.accessibilityHidden(true)`.
- **StoryBeatView** = copy stack using `OnboardingStepHeader`-style composition; entrances via `.scrollTransition(.interactive)` (blur ≤8 on the hero line only, otherwise opacity+offset); mid-layer decoration parallax via `.visualEffect { $0.offset(y: proxy.frame(in: .scrollView).minY * -0.15) }` (render-side, no layout invalidation).
- New files under `Vaultify/Features/StoryIntro/` + `StoryShaders.metal` (app-target glob only; `tuist generate` after adding — CLAUDE.md).
- Shader lazy-compile hitch: render the shader view once at 0 opacity during the route crossfade before beat 1 becomes interactive (`Shader.compile` prewarm is believed 17.4+, unverified — researcher-05 Q1).

**Color / theme decision**: beats 1–3 commit to a fixed near-black cinematic canvas with fixed light text (brand-animation precedent: LooxCloud/LooxSwirl raw-white decorative layers, researcher-02 §4). Across beat 4 the shader cross-fades the canvas into `theme.color(.background)` and text flips to semantic roles — "light returns" IS the relief, and the sanctuary literally looks like the theme the user picked one minute ago in onboarding. This needs the owner call flagged in researcher-02 Q2; the safe fallback is theme-following throughout with an `overlayDim` scrim behind beats 1–3 copy.

---

## 4. Storyboard

Haptics note up front: the DNA haptics vocabulary gives scene changes and scroll NOTHING (researcher-02 §3). The story is deliberately silent until the user commits — exactly one haptic in the whole experience, on the seal. That silence is the design.

### Beat 1 — Hook
- **Scene**: near-black veil (shader: soft vignette + barely-drifting cold blue nebula). One small glowing dot floats center-high, breathing at the LooxLogoBreathe cadence (~4 s sine). Title blurs in, then a chevron + "Scroll" hint pulses gently near the bottom.
- **Reactbits ref**: Dark Veil + Orb (single) + Blur Text.
- **SwiftUI**: shader pass (t-driven); dot = one Canvas symbol, scale 1±0.02 sine; title `.scrollTransition` blur-in (whole-block, localization-proof per researcher-05 §5); hint = `.phaseAnimator` no-trigger loop, offset ±4 pt.
- **Continuity**: opens on darkness that reads as the after-image of the onboarding done-step flood; the flood's last bloom visually shrinks into this single dot (nice-to-have, pure timing).
- **Haptic**: none.
- **Interaction**: the first scroll pull is the user ANSWERING the question — motion starts only when they move. Deepens the beat because the story refuses to autoplay: their hand starts it.

### Beat 2 — Chaos
- **Scene**: as beat 1→2 progress rises, the one dot splits and multiplies into ~120 drifting scraps — tiny note cards, chat bubbles, browser pills, key dots — wandering on seeded Lissajous paths, slightly parallaxed against the scroll. Copy names the places; the stat lands last.
- **Reactbits ref**: Ballpit / Swarm Cursor (drift chaos), Falling Text mood, Noise grain (baked into shader at low amplitude).
- **SwiftUI**: particle positions = `lerp(centerPoint, scatterSeed[i], smoothstep(beatProgress))` + drift term; symbols stamped from the `symbols:` cache; copy `.scrollTransition` staggered opacity+offset (no per-row blur — researcher-05 perf note).
- **Haptic**: none.
- **Interaction**: scroll speed = spawn speed. Pull fast and the mess erupts; pull slow and it seeps. The user manufactures their own mess, which is the mirror moment.

### Beat 3 — Consequence
- **Scene**: drift freezes to a tense near-still. One chat-bubble scrap brightens, then identical clones of it light up across the field one by one (the reused password). Field takes a subtle warning tinge (shader lerps toward `theme.warning`-derived hue, never full red horror). A live counter ticks: 7,000 attacks every second, plus a "since you started reading" tally. Micro-jitter (±1 pt, 2 Hz) on the cloned scraps reads as glitch without a glitch shader.
- **Reactbits ref**: Letter Glitch / Electric Border (as restrained jitter + glow), Count Up.
- **SwiftUI**: clone highlight = time-staggered opacity ramps on a seeded subset; counter = local `TimelineView(.periodic(by: 1))` + `Text` with `.contentTransition(.numericText(value:))` + `.monospacedDigit()` (iOS 17.0 — researcher-05 §5); warning hue = shader uniform driven by beat progress.
- **Haptic**: none (a warning haptic here would be a scene-change haptic — vocabulary forbids it; unease is carried by stillness and the counter).
- **Interaction**: the beat rewards a pause — the tally only grows while they linger, quantifying the threat with their own reading time (Opal's quantified-dread move). Scrolling on is the escape, which tees up the turn.

### Beat 4 — Turn (signature moment)
- **Scene**: copy instructs what the hand is already doing. Every scrap's position becomes `lerp(scatterPos[i], ringSlot[i], easeInOut(beat4Progress))` where `beat4Progress` is driven DIRECTLY by scroll offset — the drag visibly reels every stray password toward a center point. Warning hue drains out; accent hue rises; the fixed-dark canvas begins cross-fading into the user's theme background.
- **Reactbits ref**: Magnet Lines / Meta Balls consolidation, Scroll Expand's scrubbed-pin feel, Particle Text's chaos→order metaphor.
- **SwiftUI**: pure scrub — no animation curves, position is a function of `journeyProgress` (KeyframeTimeline-style sampling per researcher-05 §3, implemented as plain math). Release mid-gather and `.viewAligned` settles the scroll, which settles the particles with it.
- **Haptic**: none — the payoff is withheld for beat 6.
- **Interaction**: THE interaction of the concept. The scroll gesture is recast as the product's core promise: gathering scattered credentials into one place. Reversing the scroll scatters them again — the user can play the moment like a fidget, which builds ownership (endowment effect, researcher-04/Blinkist).

### Beat 5 — Sanctuary
- **Scene**: scraps snap into a serene orbit — 24 survivors forming a slow-rotating ring (LooxSwirl's ring aesthetic) around the Loox mark; surplus particles fade out. Concentric sigil arcs draw themselves around the ring with soft glow. Stage is now fully the user's theme; aurora is calm accent-soft. Promise lines blur in one by one; the title's key word resolves through `GlyphResolveText` (the app's decrypt verb, 0.4 s fixed budget).
- **Reactbits ref**: Magic Rings (sigil), Aurora (calm close), Animated List spirit (order), Decrypted Text (via the existing house component).
- **SwiftUI**: ring positions = polar slots + slow `t` rotation; sigil arcs = Canvas `Path.addArc` with trim driven by beat progress, glow from a pre-blurred stroke symbol; `GlyphResolveText` reused as-is; copy whole-block blur-in via `.scrollTransition`.
- **Haptic**: none.
- **Interaction**: micro-parallax — the ring counter-drifts a few points against the last scroll delta (`visualEffect`), so tiny scroll adjustments make the vault feel suspended and physical, a precious object (Tilted Card energy without gyro scope creep).

### Beat 6 — Commitment / CTA
- **Scene**: ring tightens around the mark, which settles top-center; one line of copy; one full-width capsule CTA in the thumb zone with a slow sheen sweep every ~4 s. Tap: `Haptics.tap()` fires, the ring contracts then bursts outward (the LooxSwirl `.dismiss` verb, ~0.8 s), the stage blooms to the theme background, the flag flips, and RootView's existing 0.35 s route crossfade lands on Home. The tutorial then arrives on its own after its 1200 ms settle delay — the story's burst reads as the curtain-raise for the real app.
- **Reactbits ref**: Star Border / Shiny Text (CTA sheen), Click Spark (burst), Prismatic Burst (restrained).
- **SwiftUI**: `BrandCapsuleCTA` (existing component), height `Metric.controlLarge`, sheen = masked `LinearGradient` offset sweep behind `reduceMotion` guard; burst = the Canvas particles' final position function (outward radial + fade over 0.8 s) triggered by a beat-state flip; completion via `withAnimation(completionCriteria: .logicallyComplete) { } completion: { settings.storyIntroCompleted = true }`.
- **Haptic**: `Haptics.tap()` on CTA activation — the single haptic of the story, per vocabulary (selection/minor action = tap; success is reserved for copy actions). Fired once, from the action handler.
- **Interaction**: one tap = the commitment ritual (Opal's fist-bump analog compressed to the platform-native gesture). DNA rule 7 honored: exactly one filled primary, the quiet Skip remains the only secondary, and it is now redundant.

---

## 5. Copy draft (EN + VI)

Rules honored: no "!", no em-dash, no interpunct; short lines; calm and honest; VI written as native everyday speech (matching the catalog's tone: vault = "kho", brand = "Loox", pronoun "bạn"). VI is the layout-longest and is designed first at 375 pt. JA values are also mandatory at implementation (CLAUDE.md) — not drafted here.

| Key (suggested) | EN | VI |
|---|---|---|
| `story.hook.title` | Where do your passwords live? | Mật khẩu của bạn đang ở đâu? |
| `story.hook.body` | Take a second and try to count them. | Thử dành một giây đếm xem sao. |
| `story.hook.hint` | Scroll | Kéo lên |
| `story.chaos.title` | A little bit of everywhere | Mỗi nơi một ít |
| `story.chaos.body` | Notes. Screenshots. That chat with yourself. A browser that keeps asking to save. | Ghi chú. Ảnh màn hình. Đoạn chat tự nhắn cho mình. Trình duyệt thì cứ hỏi lưu. |
| `story.chaos.stat` | 69% of people say they have too many to keep track of | 69% người dùng nói họ có quá nhiều mật khẩu để nhớ nổi |
| `story.chaos.source` | Pew Research Center, 2023 | Pew Research Center, 2023 |
| `story.consequence.title` | One leak opens every door | Một chỗ lộ, mở mọi cánh cửa |
| `story.consequence.body` | Reuse a password and a single breach quietly tries it everywhere else. | Dùng lại một mật khẩu, chỉ cần lộ một nơi là kẻ xấu sẽ lặng lẽ đem thử ở mọi nơi khác. |
| `story.consequence.stat` | 7,000 password attacks every second | 7.000 cuộc tấn công mật khẩu mỗi giây |
| `story.consequence.tally` | Since you started reading: %@ | Từ lúc bạn đọc tới giờ: %@ |
| `story.consequence.source` | Microsoft, 2024 | Microsoft, 2024 |
| `story.turn.title` | Now pull them back | Giờ thì gom chúng về |
| `story.turn.body` | Keep scrolling. You are gathering every stray password into one place. | Cứ kéo tiếp. Bạn đang gom từng mật khẩu rải rác về một chỗ. |
| `story.sanctuary.title` | One vault. Yours alone. | Một chiếc kho. Của riêng bạn. |
| `story.sanctuary.body1` | Encrypted on this device. No account. Nothing leaves unless you say so. | Mã hóa ngay trên máy. Không cần tài khoản. Không gì rời khỏi máy nếu bạn không cho phép. |
| `story.sanctuary.body2` | Unlock with Face ID. Sign in with one tap. | Mở khóa bằng Face ID. Đăng nhập chỉ một chạm. |
| `story.commit.title` | Lock them in | Cất hết vào kho |
| `story.commit.body` | Loox remembers, so you can forget. | Loox nhớ giúp bạn, để bạn thoải mái quên. |
| `story.commit.cta` | Enter your vault | Vào kho của bạn |
| `story.skip` | Skip | Bỏ qua |

Copy notes:
- "%" and "?" are permitted; only "!", "—", "·" are banned. VI thousands separator "7.000" is standard VI number formatting, not an interpunct.
- Stats phrased as global figures; no Vietnam-specific claims (researcher-04 Q3). Sources rendered as a caption (`.vaultType(.caption)`, tertiary role) — honest attribution keeps the "copy never lies" bar.
- The tally string takes a localized formatted number (`%@` via `appString`-compatible interpolation); digits get `.monospacedDigit()`.
- Face ID line: at implementation, mirror however existing onboarding biometric copy brands the sensor (Face ID vs Touch ID device variants) — reuse that existing string logic if present.

---

## 6. Integration

- **Flag**: `SettingsStore.storyIntroCompleted`, UserDefaults key `"story_intro_completed"` (snake_case Key enum convention, SettingsStore.swift L313-337). Set `true` on finish AND skip.
- **Decision seat**: `RootView.swift` `.unlocked` branch (L44-50) — render `StoryIntroScreen` INSTEAD OF `AdaptiveRootView` while `StoryIntroFeature.enabled && !settings.storyIntroCompleted`. Never a fullScreenCover/overlay: HomeScreen must not mount, or its `.task` starts the firstRun tutorial behind the story (researcher-01 §4).
- **Kill switch**: `StoryIntroFeature.enabled` static let in `VaultifyCore/` mirroring `TutorialFeature` (release-train decoupling convention).
- **Handoff to tutorial**: zero coordinator changes. Flag flips → route re-renders `AdaptiveRootView` → Home `.task` → `startIfNeeded(.firstRun)` → 1200 ms settle → spotlight tour. The story's exit burst + 0.35 s route crossfade land, then the tour arrives on its own beat.
- **Restore path**: `JoinVaultFlow.finish()` sets `storyIntroCompleted = true` — returning users restoring a vault skip the story (recommendation on researcher-01 Q1).
- **Recovery reset**: `VaultSession+Recovery` (onboarding reset) also clears the story flag so full re-onboarding replays it (researcher-01 Q2).
- **Settings replay**: "Show tutorials again" does NOT replay the story; it stays a once-per-vault-life cinematic (researcher-01 Q3). Revisitable later if asked.
- **Test isolation**: default `storyIntroCompleted = true` in the AppEnvironment DEBUG isolation block (next to `onboardingCompleted = true`, L177), with a `-ui-test-story` launch-arg opt-in mirroring `-ui-test-tutorials` (L123-135). Without this every UI test hits a non-hittable full-screen story.
- **Analytics** (typed catalog only, auditSamples entries test-enforced):
  - `.analyticsScreen("story_intro")` on the screen.
  - `AnalyticsEvent.storyIntroEnded(outcome: "completed" | "skipped", furthestBeat: 1...6)` → `story_intro_ended` with `outcome` + `furthest_beat`. Fixed ids only; no user content, no timings, privacy contract intact. `furthestBeat` derived from max `journeyProgress` reached.
- **Reduce Motion path** (screen fully usable with zero motion):
  - Stage: TimelineView `paused`, shader `t` frozen; particle layout becomes a static composition PER BEAT (scatter poster for 2–3, gathered ring for 5–6) derived from the snapped beat index, not time.
  - `.scrollTransition` closures collapse to opacity-only; all discrete animations routed through `Animation.vault(_:reduceMotion:)` (nil under RM); sheen, hint pulse, breathe, and exit burst all skipped; CTA tap flips the flag immediately (route crossfade is already RM-aware at RootView L69).
  - Haptic decision: keep the single `Haptics.tap()` under RM (RM does not disable haptics by system default; one selection haptic is vocabulary-legal).
- **Dynamic Type + small screens**:
  - Designed VI-first at SE 375×667: title ≤2 VI lines, body ≤3 VI lines, stat 1 line + caption; copy paddings on `Space` tokens; edges `Space.gutter`.
  - `dynamicTypeSize >= .accessibility1` OR VoiceOver running → `StoryIntroReaderView`: same copy, same CTA and Skip, plain non-snapping scroll, static poster stage, no `containerRelativeFrame` height locks — the story degrades to a beautiful readable page instead of clipping (reflow, never shrink; `minimumScaleFactor` avoided).
  - VoiceOver: stage `.accessibilityHidden(true)`; beats read in order as grouped text; Skip and CTA are ordinary buttons; counter tally exposed as static text, not a live region.
- **iPad / macOS**: seam covers all platforms uniformly. Copy column clamps `.vaultContentWidth(.form)`; stage stays full-bleed. iPad = no haptics (no-op is fine). macOS slice gets the Reader-style presentation (scroll snapping and scrubbing feel poor with a wheel; static poster + copy + CTA).
- **Localization mechanics**: all strings in `Localizable.xcstrings` with EN source + VI + JA; titles `.inAppLocalized`; runtime strings `appString()`.

---

## 7. Feasibility + risks

| Risk | Severity | Mitigation |
|---|---|---|
| iPhone 12-class perf: shader + ~120 particles + scroll simultaneously | Medium | Single `colorEffect` pass (cheapest full-screen effect); symbol-stamped Canvas, glow pre-baked, no per-particle blur; NO materials over the stage; blur in scrollTransition capped ≤8 and hero-only; mandatory on-device Instruments pass (researcher-05 Q3) |
| Shader lazy-compile hitch on entry | Low | Preflight the shader at 0 opacity during the 0.35 s route crossfade; `Shader.compile` prewarm believed 17.4+ (unverified) so do not depend on it |
| `.viewAligned` / `.paging` quirks on exactly 17.3 | Medium | Prototype both on a 17.3 simulator FIRST (researcher-05 Q4); design survives fallback to free scroll unchanged |
| PreferenceKey offset plumbing jank at 120 Hz | Low | Throttle writes (0.5 pt rounding); per-item effects stay on `visualEffect`/`scrollTransition` (render-side); ProMotion: particles at `minimumInterval: 1/60`, shader free-running |
| Memory | Low | No video, no large textures; symbol cache is a handful of small rasters; the stage Canvas is the only recurring offscreen surface. Well under any budget |
| Committed-dark canvas in light mode | Open call | Precedent exists (brand-animation raw-white layers) but researcher-02 Q2 needs the owner decision; fallback = theme-following canvas + `overlayDim` scrim behind beats 1–3 copy |
| Accessibility-size beats overflowing fixed page height | Medium | Dedicated `StoryIntroReaderView` path (above) — cheaper than making 6 pinned pages elastic, and honest |
| JA copy (no spaces) breaks word-level text effects | Low | Policy: whole-block blur-in everywhere; per-glyph only via existing `GlyphResolveText` (already localization-safe, fixed 0.4 s) |
| UI tests hitting the story | High if missed | DEBUG isolation default `storyIntroCompleted = true` + `-ui-test-story` opt-in (researcher-01 must-do) |
| Story fatigue / App Review | Low | Skip from first frame; total forced content = zero; one-time flag |

**Review-checklist compliance map** (adversarial protocol, answers to be filed in writing at implementation review):
1. Protagonist — one per beat (question, mess, threat, gathering, vault, CTA); stage is always subordinate to the copy line; skip and hint are the only chrome.
2. Every text — table above reads aloud calm in EN and VI; no banned punctuation; VI verified longest at 375 pt.
3. Every control — Skip (44 pt padded, top-trailing) + CTA (`Metric.controlLarge`, thumb zone) are the only controls; both obvious; CTA gives visual press + the one tap haptic.
4. Space and shape — copy stacks on `Space` tokens, edges `Space.gutter`, capsule via existing `BrandCapsuleCTA`, scrap cards `Radius.sm` via `.vaultCornerRadius`; sigil arcs are decorative canvas, not cards.
5. Every state — beats each have composed static (RM) and kinetic states; mid-scroll release always snaps composed; locked-mid-story replays from start until flag set (researcher-01 lock rule); no loading or error states exist.
DNA rule 5 (motion never gates): skip and CTA are always hittable; no animation completion is required for anything. DNA rule 7: one filled primary in the entire experience.

---

## 8. Open decisions for the orchestrator

1. Committed-dark beats 1–3 vs theme-following + scrim (researcher-02 Q2) — recommend committed-dark with the theme-resolve as the beat-4 relief device.
2. Confirm `.viewAligned` behavior on a 17.3 simulator before locking the scroll mechanic (fallback is free scroll, no redesign).
3. Owner sign-off on the two stats and their captions (Pew 2023, Microsoft 2024) — both primary-sourced in researcher-04.
4. macOS: Reader-style presentation vs skipping the story entirely on Mac (flag defaults could set it completed on macOS).
5. JA copy pass by a native reviewer at implementation (mandatory catalog value, not drafted here).
