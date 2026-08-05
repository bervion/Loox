# Concept B — Interactive Vignettes ("Your passwords, everywhere. Then one place.")

One-time cinematic story screen shown after onboarding completes, before the Home tutorial.
Chapter-based vignettes; each beat asks for ONE tiny meaningful touch. Tap, drag, hold are the
language; every gesture is a metaphor for the security story.

Inputs: researcher-01 (flow seam), researcher-02 (design system), researcher-03 (reactbits
catalog), researcher-04 (benchmarks + stats), researcher-05 (SwiftUI feasibility).

---

## 1. Narrative arc

Spine (Opal/Noom pattern, researcher-04): mirror → futility → dread → agency → relief → ritual.
The user is the protagonist in every beat; their own finger causes the chaos AND builds the
sanctuary. One idea per beat (DNA rule 1), one interaction per beat, one primary action on
screen at any time (DNA rule 7).

| # | Beat | Emotion | Interaction | Duration |
|---|------|---------|-------------|----------|
| 1 | Hook — "Where do your passwords live?" | curiosity, recognition | tap the dark, secrets bloom from the finger | ~4s + tap |
| 2 | Chaos — the leaking notes app | playful overwhelm turning to futility | pop bubbles; each pop spawns more | 8–10s |
| 3 | Consequence — one share ripples out | unease, gut punch (user caused it) | tap to "send" the password; ripple spreads, copies corrupt | ~8s |
| 4 | Turn — the vault ring appears | hope, agency | drag ONE chip into the ring; the rest follow | 8–12s |
| 5 | Sanctuary — inside the vault | calm, relief | optional press-to-peek a masked row; release conceals instantly | 6–10s |
| 6 | Commitment — seal it | ownership, ritual | hold the ring 0.9s; ripple + haptic seals the vault, hands off to Home | ~4s + hold |

- **Target total**: 40–55s engaged; rushed path ~25s; hard cap ~75s (every interactive beat
  auto-completes at 10–12s so nobody is stranded; a gentle prompt pulse at ~6s idle).
- **Skip affordance**: quiet text button "Skip", top-trailing, appears once beat 1 settles
  (~2s), persistent through all beats, padded to `Metric.hitMin` (44pt). Skip = same flag flip
  as completion, logged with outcome `skipped`. Story never gates anything (DNA rule 5: motion
  never gates a result).
- **Stats discipline** (researcher-04: 1–2 max, primary-sourced only): Pew 2023 "69% feel
  buried" in beat 2; Verizon DBIR 2025 "1 in 3 breaches" in beat 3. Nothing else quantified.
- Why interaction deepens each beat: popping is fun then futile (you FEEL the mess outgrow
  you); the share ripple is triggered by the user's own tap (ownership of the risk); dragging
  one chip while the rest follow mirrors the real product promise (you start, Vaultify does
  the work); the hold-to-seal is a physical commitment ritual (Opal fist-bump analog).

---

## 2. Storyboard

Global stage: committed dark cinematic canvas in BOTH appearance modes (brand-animation
precedent per researcher-02 §4; needs owner sign-off, see risks). All text/controls on
semantic roles (`theme.color(role)` resolved against the dark scene) so a future light
treatment survives. Decorative layers `.accessibilityHidden(true)`; per-beat VoiceOver
summary + activate action replaces each gesture. Beat transitions reuse the onboarding
pattern: `@State beat` + ZStack switch + `.animation(.vault(.smooth(duration: 0.35),
reduceMotion:), value: beat)` — no haptics on beat changes (haptics vocabulary).
All timelines are pure functions of elapsed time (LooxTimeline house pattern); state mutates
only on user events, never per frame. `TimelineView(.animation(minimumInterval: 1/60,
paused: reduceMotion || scenePhase != .active))`, leaf-deep so only the Canvas re-evaluates.

### Beat 1 — Hook
- **Scene**: near-black canvas. Title blur-resolves as a whole block (never per-char split —
  VI/JA safe, researcher-05 §5): "Where do your passwords live?" Prompt fades in below.
- **Reactbits ref**: Blur Text (title), Click Spark + Particles (tap bloom).
- **SwiftUI**: title `.blur(12→0) + .opacity` via `withAnimation(.vault(Motion.standard...))`.
  Tap location from `SpatialTapGesture` (iOS 16). Bloom = one-shot seeded Canvas burst,
  LooxSwirl `.reveal` pattern: pre-resolved glow-dot symbols (`ctx.resolveSymbol` +
  `ctx.draw(_:at:)`), easeOutCubic radius as fn of (now − tapDate); 5 faint ghost password
  chips drift out of the burst and linger into beat 2.
- **Haptic**: `Haptics.tap()` on the tap (selection-like act that advances the story). None on appear.
- **Interaction meaning**: one touch reveals what is already hiding in your digital life.

### Beat 2 — Chaos (pop the leaking bubbles)
- **Scene**: a notes-app-like card (canvas surface, `Radius.lg`, `.vaultCornerRadius`) center;
  masked lines inside. Bubbles leak upward carrying tiny chips: fixed fictional strings only
  ("123456", "qwerty", "•••• 2024" — constants, never user content, not localized). Caption
  builds in three stacked short lines (layout separates ideas, no interpunct). After the
  multiply moment, the futility line + the Pew stat land.
- **Reactbits ref**: Bubble Menu (elastic pop-in), Ballpit (drift), Falling Text (mood).
- **SwiftUI**: TimelineView + Canvas; bubbles = 2 pre-blurred circle symbols + chip text
  symbols, positions = seeded sine drift, pure fn of t (researcher-05 §2; no per-draw
  `.addFilter(.blur)`). Tap hit-test: on `SpatialTapGesture` end, compare location against
  positions computed at current t; inflate hit radius to ≥22pt (44pt diameter); snap to
  nearest. Popped ids in a small `@State Set<Int>` (mutates on tap only). Each pop draws an
  expanding ring fade and ACTIVATES two new seeds. Hard cap ~48 live bubbles (perf + the
  point is made). Beat completes after 5 pops or 10s.
- **Haptic**: `Haptics.tap()` per pop, throttled ≥150ms. No warning here (single warning
  reserved for beat 3 where it lands hardest).
- **Interaction meaning**: cleaning by hand is a losing game; the mess multiplies.

### Beat 3 — Consequence (the shared password ripples out)
- **Scene**: one glowing chip center, chat-bubble motif behind it. Prompt invites the SEND.
  On tap: concentric rings expand; at each ring radius, ghost copies of the chip stamp in at
  polar positions, dimmer with distance; after 1s their text scrambles into corruption and
  tints toward `destructive`. Stat line resolves last.
- **Reactbits ref**: Ripple Grid / Magic Rings (rings), Scrambled + Glitch Text (corruption).
- **SwiftUI**: rings = `ctx.stroke(Path(ellipseIn:))`, radius easeOutCubic fn of t. Ghost
  chips = Canvas symbols. Scramble = `TimelineView(.periodic(by: 1/15))` rebuilding a short
  display string (resolved prefix + random glyphs), `.monospaced()` +
  `.contentTransition(.identity)` to kill crossfade flicker (researcher-05 §5); chips ≤8 chars.
  Auto-advance 8s after tap (or 10s idle → plays itself).
- **Haptic**: `Haptics.warning()` once, when the ripple begins — risky state entered. The
  only warning in the whole story.
- **Interaction meaning**: the user's own thumb performs the everyday mistake; once sent, it
  cannot be unsent.

### Beat 4 — Turn (drag scattered chips into the vault ring)
- **Scene**: the vault ring draws itself center-screen: 3 concentric accent-tinted arcs with
  angular cutaways, slow counter-rotation, soft bloom. 5 scattered chips (survivors of beats
  1–3) lie around the edges as real views. Prompt: drag one in. When the user's chip crosses
  the capture radius it springs to center, scales to 0.3, its text morphs to a FIXED 6-dot
  mask (DNA rule 9: masks never leak length), and the ring brightens. The remaining chips
  then follow one by one with 120ms stagger. Closing line lands.
- **Reactbits ref**: Magic Rings (sigil), Magnet Lines (alignment), Animated List (filing).
- **SwiftUI**: ring draw-in via `.keyframeAnimator(initialValue:trigger:)` (iOS 17.0) driving
  trim + opacity; ongoing rotation from the shared TimelineView. Chips are SwiftUI views with
  `DragGesture()` updating an offset `@GestureState`; capture check on `.onEnded` AND live
  during drag (distance < captureRadius); spring-in with
  `withAnimation(.vault(Motion.spring, reduceMotion:))`. Followers animate on a stagger of
  `.delay(Double(i) * 0.12)`. Fallback: 12s idle → chips auto-file.
- **Haptic**: `Haptics.tap()` on the user's own capture only (one physical event); follower
  chips are silent.
- **Interaction meaning**: you lead once, the app does the rest — the literal product promise
  (import/autofill) played as a toy.

### Beat 5 — Sanctuary (inside the vault)
- **Scene**: crossfade "through" the ring: backdrop becomes a slow dark aurora; the chips are
  now a neat filed list of 3 masked rows (`Radius.md` rows, fixed 6-dot masks,
  `Font.vaultCode`); a small lock mark breathes above. Promise copy in stacked short lines.
  Optional play: press a row to peek — glyphs resolve left-to-right in 0.4s; release conceals
  INSTANTLY (the app's controlled-reveal physics, taught as play).
- **Reactbits ref**: Aurora / Silk (backdrop), Spotlight Card (peek row), Decrypted Text (peek).
- **SwiftUI**: backdrop = reuse `MeshGradientView` / `MeshGradientRenderer` (repo-proven
  CAKeyframeAnimation baked mesh, zero ongoing cost, honors Reduce Motion; avoids introducing
  a `.metal` file — researcher-02 §8, researcher-05 §8 option 1 kept as an upgrade path).
  Lock breathe = reuse `LooxLogoBreatheView`. Peek = `.onLongPressGesture(minimumDuration:
  0.15, pressing:)`; reveal via repo `GlyphResolveText` (fixed 0.4s budget); conceal = instant
  swap, no animation (privacy verb). Beat completes on a Continue tap or 10s.
- **Haptic**: none (reveal/conceal has no haptic in the vocabulary; success belongs to
  ClipboardService).
- **Interaction meaning**: secrets open only under your finger, and hide the instant you let go.

### Beat 6 — Commitment (hold to seal)
- **Scene**: the ring contracts tight around the lock mark (≥ `Metric.avatarHero` 92pt hit
  area). Single instruction. While the user holds, a progress arc sweeps the ring (0.9s);
  at 100% a soft ripple emits outward, arcs converge and flash gently, "Sealed" resolves,
  then the screen hands off (flag flip → RootView route crossfade).
- **Reactbits ref**: Magic Rings clickBurst, Ripple, Shiny Text (sealed line).
- **SwiftUI**: press tracking via `DragGesture(minimumDistance: 0)` recording press-start
  date; arc trim = pure fn of (now − start) from TimelineView; release before 0.9s springs
  the arc back (`Motion.spring`). Completion: play seal ripple (~0.6s), set
  `env.settings.storyIntroCompleted = true`; RootView's existing route animation (L69) does
  the exit. Accessibility: `.accessibilityRepresentation { Button("Seal my vault") }` so
  VoiceOver/Switch Control activate completes without a timed hold.
- **Haptic**: `Haptics.tap()` at hold start; `.sensoryFeedback(.success)` (iOS 17.0,
  researcher-05 §7) once at seal completion — a genuine operation-completed event. This is a
  deliberate vocabulary extension (success is currently ClipboardService-only) and needs
  owner sign-off; fallback is `Haptics.tap()`.
- **Interaction meaning**: a physical ritual of commitment; the vault is sealed by your hand,
  nobody else's.

### Reduce Motion (whole screen)
`@Environment(\.accessibilityReduceMotion)` at the scene root: TimelineViews paused, shader/
mesh static, particles replaced by a sparse frozen scatter, all discrete animations routed
through `.vault(_, reduceMotion:)` (nil → instant swaps), beat transitions become instant
crossfades, scramble text shows the corrupted end state directly. Interactions all still work:
pops complete instantly, the drag snaps without spring, hold-to-seal keeps its arc progress
(functional feedback, not decoration). Haptics kept deliberately (researcher-05 §7 note).

---

## 3. Copy draft

Rules applied: no "!", no em-dash, no interpunct; ideas separated by line breaks, not
punctuation; short lines; VI written for everyday speech, not translated; designed for VI as
the longest render at 375pt. JA drafts included because the catalog requires EN+VI+JA
(CLAUDE.md); mark JA for native review at implementation. Keys suggested as
`story.beatN.role` in `Localizable.xcstrings`; titles `.inAppLocalized`, runtime `appString()`.

| Key | EN | VI | JA (draft) |
|---|---|---|---|
| story.skip | Skip | Bỏ qua | スキップ |
| story.beat1.title | Where do your passwords live? | Bạn đang cất mật khẩu ở đâu? | パスワードはどこにありますか？ |
| story.beat1.prompt | Tap to see | Chạm để xem | タップして見る |
| story.beat2.line1 | In notes | Trong ghi chú | メモの中 |
| story.beat2.line2 | In chats | Trong tin nhắn | チャットの中 |
| story.beat2.line3 | In your head | Trong trí nhớ | 頭の中 |
| story.beat2.prompt | Try popping them | Thử chạm cho vỡ xem | 触れて割ってみて |
| story.beat2.futility | The more you clear, the more spill out | Càng dọn, chúng càng tràn ra | 消すほど、あふれていく |
| story.beat2.stat | 69 percent of people feel buried by their passwords | 69% mọi người thấy quá tải vì mật khẩu | 69%の人がパスワードに疲れています |
| story.beat3.setup | One of them gets shared | Rồi một cái được đem đi chia sẻ | ひとつが共有される |
| story.beat3.prompt | Tap to send it, like we all do | Chạm để gửi, ai cũng từng làm vậy | タップして送る、誰もがしてきたように |
| story.beat3.aftermath | Once it leaves, it never comes back | Gửi đi rồi thì không lấy lại được | 送った瞬間、もう戻せない |
| story.beat3.stat | Stolen logins are behind 1 in 3 data breaches | Cứ 3 vụ lộ dữ liệu thì 1 vụ bắt đầu từ mật khẩu bị đánh cắp | 情報漏えいの3件に1件は盗まれたパスワードから |
| story.beat4.title | There is a safer place | Có một nơi an toàn hơn | もっと安全な場所がある |
| story.beat4.prompt | Drag one into the ring | Kéo thử một cái vào vòng sáng | ひとつをリングへドラッグ |
| story.beat4.payoff | You move one, Vaultify moves the rest | Bạn cất một cái, Vaultify lo phần còn lại | ひとつ動かせば、残りはVaultifyが |
| story.beat5.title | Everything in one vault | Tất cả nằm gọn trong một két | すべてをひとつの金庫に |
| story.beat5.line1 | No account | Không cần tài khoản | アカウント不要 |
| story.beat5.line2 | No cloud | Không đưa lên mạng | クラウドに送らない |
| story.beat5.line3 | Only you hold the key | Chìa khóa chỉ mình bạn giữ | 鍵を持つのはあなただけ |
| story.beat5.peek | Hold a row to peek | Giữ một dòng để xem thử | 長押しでのぞき見 |
| story.beat5.conceal | Let go and it hides again | Thả tay là ẩn ngay | 指を離せばすぐ隠れる |
| story.beat5.continue | Continue | Tiếp tục | 続ける |
| story.beat6.instruction | Hold to seal your vault | Giữ để khóa két của bạn | 長押しで金庫を封印 |
| story.beat6.sealed | Sealed | Đã khóa | 封印完了 |
| story.beat6.a11y | Seal my vault | Khóa két của tôi | 金庫を封印する |

Notes:
- Bubble chip strings ("123456", "qwerty", "•••• 2024") are non-localized constants, never
  user content.
- Stats phrased as global figures (researcher-04: no VN/JP breakouts exist; VI copy avoids
  implying local data). Sources to keep in the plan: Pew Research Oct 2023 (69% overwhelmed);
  Verizon DBIR 2025 (stolen credentials in 32% of breaches, rounded honestly to "1 in 3").
- "két" reads naturally in VI as the everyday word for a safe; consistent with vault framing.

---

## 4. Integration

- **Flag**: `SettingsStore.storyIntroCompleted`, UserDefaults key `"story_intro_completed"`
  (snake_case Key enum convention, SettingsStore.swift L313-337). Set `true` on BOTH seal
  completion and skip. Abandoned mid-story (lock/background) → replays next unlock until set
  (researcher-01 §4 lock interplay).
- **Decision seam**: RootView unlocked branch (RootView.swift:44-50) renders
  `StoryIntroScreen` INSTEAD OF `AdaptiveRootView` while flag is false — never
  fullScreenCover/overlay, so HomeScreen's `.task` cannot start the tutorial underneath
  (researcher-01 §4). Route crossfade at L69 is inherited free.
- **Handoff to tutorial**: zero-code — flag flips → `AdaptiveRootView` mounts → Home `.task`
  → `startIfNeeded(.firstRun)` → 1200ms settle → spotlight tour. No TutorialCoordinator
  changes.
- **Scope**: create-path only; `JoinVaultFlow.finish()` also sets `storyIntroCompleted = true`
  (restore users skip the story). Recovery reset (`VaultSession+Recovery.swift:93`) also
  clears the story flag so a re-onboarded vault replays it (recommended; confirm with owner).
- **Kill-switch**: `StoryIntroFeature.enabled = true` in `VaultifyCore/` mirroring
  `TutorialFeature` (release-train decoupling convention).
- **Test isolation**: default `storyIntroCompleted = true` in the AppEnvironment DEBUG
  isolation block (AppEnvironment.swift:166-180, next to L177) or every UI test lands on a
  non-hittable story; mirror the `-ui-test-tutorials` opt-in arg if tests drive it.
- **Analytics** (typed catalog, AnalyticsEvents.swift rules; privacy contract — fixed ids
  only, no content, no timings beyond beat index):
  - `.analyticsScreen("story_intro")` on the screen.
  - `storyIntroEnded(outcome: "completed" | "skipped", atBeat: Int)` — single event, plus its
    `auditSamples` entry (test-enforced). Per-interaction logging deliberately omitted.
- **Reduce Motion**: full static-vignette path per §2; screen fully usable with zero motion.
- **Dynamic Type + small screens**: all text `.vaultType` roles (title = `.largeTitle` on
  beat 1 only, body/callout elsewhere); whole-block blur-ins are wrap-safe at accessibility
  XXL; layout = text zone top, interactive stage center (scale-to-fit via the LooxCanvas
  geometry pattern), prompt pinned above home indicator with reserved 2-line space. Verify at
  SE 375pt with VI strings (longest). iPad/macOS: stage clamped `.vaultContentWidth(.form)`,
  centered; iPad has no haptics — `Haptics` no-ops gracefully; hold-to-seal unchanged.
- **New files** (each <200 lines, app target only): `Vaultify/Features/StoryIntro/`
  `StoryIntroScreen.swift` (beat switch + skip + flag), `StoryIntroBeat.swift` (enum +
  timings), one canvas view per vignette (`StoryChaosBubblesView.swift`,
  `StoryRippleView.swift`, `StoryVaultRingView.swift`, `StorySealHoldView.swift`). Run
  `tuist generate` after adding files.

---

## 5. Feasibility + risks

Feasibility: every effect sits on the repo-proven Canvas/TimelineView/CoreAnimation stack —
LooxSwirl symbol-stamping pattern (bursts, bubbles, ring glow), MeshGradientView (aurora),
GlyphResolveText (peek), LooxLogoBreatheView (lock breathe), keyframeAnimator (ring draw-in),
SpatialTapGesture/DragGesture (all iOS 16/17.0). No Metal file, no iOS 18+ dependency, no
third-party code. The optional upgrade path (single `colorEffect` aurora shader,
researcher-05 §1/§8) is documented but not required by this concept.

Perf budget (iPhone 12-class, researcher-05):
- Bubble cap 48 live + pre-blurred glow symbols (never per-draw blur filters); ~1 Canvas +
  1 mesh layer + ≤1 material at any time; state mutations only on user events; TimelineViews
  `minimumInterval: 1/60` (ProMotion-safe) and paused off-scene/`scenePhase != .active`.
- Memory trivial: symbols + 16 baked 80×80 mesh frames; no video/memoji layers.

Risks and mitigations:
1. **Dark-look-in-both-modes** is an open owner call (researcher-02 Q2). Concept commits to
   dark cinematic per brand-animation precedent; all text stays on semantic roles so a light
   variant remains possible. BLOCKER-level sign-off needed before build.
2. **Haptic vocabulary stretch**: `.success` at seal completion extends the ClipboardService
   -only convention. Needs owner sign-off; degrade to `Haptics.tap()` if refused.
3. **Hold-to-seal accessibility**: timed holds exclude VoiceOver/Switch Control users →
   `.accessibilityRepresentation { Button }` completes on activate; every beat exposes a
   summary label + activate action; decorative canvases `.accessibilityHidden(true)`.
4. **Drifting-bubble hit-testing** can feel unfair → ≥44pt effective hit diameter +
   snap-to-nearest; beat also completes on a timer so misses never strand the user.
5. **Stranding**: every interactive beat auto-completes (10–12s cap) and Skip is persistent;
   total hard cap ~75s protects App Review first-run impressions.
6. **Stat integrity**: only Pew 2023 and DBIR 2025 (primary-sourced) are printed; the
   Reforge retention figure and Gen Z sharing splits from researcher-04 are NOT used in copy.
7. **UI tests**: without the DEBUG isolation default the story blocks every existing UI test
   (same hazard as tutorials, researcher-01 §3).
8. **Review checklist compliance** (design-dna adversarial protocol): one protagonist per
   beat; one primary action per beat + quiet Skip only (rule 7); all paddings/radii from
   tokens; fixed-length masks throughout (rule 9); five written answers per beat must be
   filed in the implementation plan; device matrix incl. VI-at-375pt, accessibility XXL,
   light+dark live switch, Reduce Motion/Transparency, VoiceOver.
9. **Scene-change haptics**: none anywhere — only user-caused events fire (tap/warning/seal),
   keeping the one-event-one-haptic contract.

## Unresolved questions
1. Owner call: dark cinematic canvas in both appearance modes (risk 1).
2. Owner call: `.sensoryFeedback(.success)` at seal (risk 2).
3. Replay entitlement: should Settings "Show tutorials again" also replay the story, or is it
   strictly once per install (researcher-01 Q3)? Concept assumes once, replay via recovery
   reset only.
4. Confirm restore-path exclusion (JoinVaultFlow sets the flag) with product owner.
5. JA copy needs native review before ship (drafts provided).
