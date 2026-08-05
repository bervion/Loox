# Story Intro — Final Concept (hybrid A+B)

One-time cinematic story screen: after onboarding completes, before the Home tutorial.
Pain point: people keep passwords in notes, chats, browsers, memory. Arc: chaos → consequence → turn → sanctuary → commitment. Goal: emotional buy-in before the first Home visit.

**Decision**: Concept A's continuous scroll-journey spine (won design-dna 7v5, narrative 6.5v5.5) rebuilt on Concept B's shader-free repo-proven stack (won feasibility 7v6), with B's four best moments grafted in. Verdicts: `research/` + workflow critics (design-dna, feasibility-perf, narrative-retention).

Sources: `concept-a-scroll-journey.md`, `concept-b-interactive-vignettes.md`, `research/researcher-01..05`.

---

## 1. Shape

- One vertical scroll, 6 full-height beats (`.containerRelativeFrame(.vertical)` + `scrollTargetLayout` + `.scrollTargetBehavior(.viewAligned)`). The scroll IS the story: the user's drag scrubs the stage.
- Skip from first frame (quiet text, top-trailing, 44pt padded). Rushed floor ~10s, natural read 45–75s. Nothing gated by motion (DNA rule 5).
- Stage = pinned full-bleed ZStack layer behind the scroll column, driven by one scalar `journeyProgress` (0…1).
- **No Metal shader in v1** (feasibility verdict: repo has zero .metal files; greenfield GPU work + 17.3 lazy-compile hitch). Stage stack = `MeshGradientView` (repo-proven baked mesh) for veil/aurora + `TimelineView(.animation)` + `Canvas` symbol-stamped particles (pre-blurred glow symbols, never per-draw filters). Single `colorEffect` aurora documented as upgrade path only (with 0-opacity preflight note).
- Beats 1–3 committed near-black cinematic canvas (brand-animation raw-color precedent); across beat 4 the canvas cross-fades into the user's own theme background — "light returns" is the relief device. Needs owner sign-off (researcher-02 Q2); fallback = theme-following + `overlayDim` scrim.

## 2. Storyboard (6 beats + arrival)

| # | Beat | Stage | Interaction | Haptic |
|---|------|-------|-------------|--------|
| 1 | **Hook** | Near-black veil, one glowing dot breathing (~4s sine, LooxLogoBreathe cadence). Title blur-in (whole block). "Kéo lên" hint pulse. | First scroll pull answers the question; story refuses to autoplay | none |
| 2 | **Chaos** | Dot multiplies into drifting scraps (note cards, chat bubbles, browser pills, key dots — Canvas symbols, seeded Lissajous drift, cap ~90, Instruments-verified). Copy names the places; the futility line lands last | Scroll speed = spawn speed; the user manufactures their own mess | none |
| 3 | **Consequence** | Drift freezes. One chat-bubble scrap brightens. **Graft B: "Chạm để gửi"** — one optional tap "sends" it; concentric ripple, ghost clones stamp outward, subtle warning tinge (never full red). No statistics (owner decision): the ripple, the multiplying clones and the aftermath line carry the dread alone | The optional send tap: the user's own thumb performs the everyday mistake (Zalo-true, blame-free). Non-tappers: ripple auto-plays softly as they scroll on | none (warning haptic = scene-change, vocabulary forbids) |
| 4 | **Turn** (signature) | Every scrap position = `lerp(scatterPos, ringSlot, easeInOut(beat4Progress))`, scrubbed DIRECTLY by scroll offset. Warning hue drains, accent rises, canvas cross-fades to theme | THE moment: the drag visibly reels every stray password home; reversing scatters them again (fidget/ownership) | none |
| 5 | **Sanctuary** | 24 survivors settle into slow-rotating ring around the Loox mark; sigil arcs trim-draw; calm accent aurora; theme fully resolved. **Graft B: press-to-peek** — one masked demo row (fixed 6-dot mask, `Font.vaultCode`); hold → `GlyphResolveText` 0.4s reveal, release → INSTANT conceal (teaches the product's Controlled Reveal physics as play) | Optional peek; micro-parallax counter-drift on ring (`visualEffect`) | none |
| 6 | **Commitment** | Ring tightens around mark above one capsule CTA. **Graft B: hold-to-seal on the CTA itself** — press fills a progress sweep across the capsule (`Motion.slow`-derived, ~0.9s); release early springs back; at 100%: ring contracts, bursts outward (LooxSwirl `.dismiss` verb), stage blooms, flag flips, 0.35s route crossfade lands Home | Physical commitment ritual (Opal fist-bump analog). `.accessibilityRepresentation { Button }` so VoiceOver/Switch Control activate completes without timed hold | `Haptics.tap()` once at completion — the single haptic of the story (`.sensoryFeedback(.success)` rejected: ClipboardService-only vocabulary) |
| 7 | **Arrival bridge** (both critics' biggest shared issue: never seal an empty vault passively) | After the firstRun tutorial ends, Home consumes a one-shot `storyIntroWantsFirstItem` hint → pulse/spotlight the Add button (or auto-open prefilled editor). Converts the narrative promise into the activation moment | — | — |

Silence is the design: exactly one haptic in the whole experience.

## 3. Copy (EN + VI + JA draft)

Rules: no "!", no em-dash, no interpunct; short lines; brand voice **Loox** (catalog: 353 Loox vs 8 Vaultify), vault = **kho** (catalog: 65+ uses; never "két"), VI designed first at 375pt (longest render). JA drafted, flagged for native review.

| Key | EN | VI | JA (draft) |
|---|---|---|---|
| story.skip | Skip | Bỏ qua | スキップ |
| story.hook.title | Where do your passwords live? | Mật khẩu của bạn đang ở đâu? | パスワードはどこにありますか？ |
| story.hook.body | Take a second and try to count them. | Thử dành một giây đếm xem sao. | 少しだけ、数えてみてください。 |
| story.hook.hint | Scroll | Kéo lên | スクロール |
| story.chaos.title | A little bit of everywhere | Mỗi nơi một ít | あちこちに少しずつ |
| story.chaos.body | Notes. Screenshots. That chat with yourself. A browser that keeps asking to save. | Ghi chú. Ảnh màn hình. Đoạn chat tự nhắn cho mình. Trình duyệt thì cứ hỏi lưu. | メモ。スクリーンショット。自分へのチャット。保存を聞いてくるブラウザ。 |
| story.chaos.futility | The more you clear, the more spill out | Càng dọn, chúng càng tràn ra | 消すほど、あふれていく |
| story.consequence.title | One leak opens every door | Một chỗ lộ, mở mọi cánh cửa | ひとつの漏えいが、すべての扉を開く |
| story.consequence.prompt | Tap to send it, like we all do | Chạm để gửi, ai cũng từng làm vậy | タップして送る、誰もがしてきたように |
| story.consequence.body | Once it leaves, it never comes back. | Gửi đi rồi thì không lấy lại được. | 送った瞬間、もう戻せない。 |
| story.turn.title | Now pull them back | Giờ thì gom chúng về | さあ、取り戻そう |
| story.turn.body | Keep scrolling. You are gathering every stray password into one place. | Cứ kéo tiếp. Bạn đang gom từng mật khẩu rải rác về một chỗ. | スクロールを続けて。散らばったパスワードをひとつの場所へ集めています。 |
| story.sanctuary.title | One vault. Yours alone. | Một chiếc kho. Của riêng bạn. | ひとつの金庫。あなただけのもの。 |
| story.sanctuary.body1 | Encrypted on this device. No account. Nothing leaves unless you say so. | Mã hóa ngay trên máy. Không cần tài khoản. Không gì rời khỏi máy nếu bạn không cho phép. | この端末で暗号化。アカウント不要。許可なく外に出ることはありません。 |
| story.sanctuary.peek | Hold a row to peek | Giữ một dòng để xem thử | 長押しでのぞき見 |
| story.sanctuary.conceal | Let go and it hides again | Thả tay là ẩn ngay | 指を離せばすぐ隠れる |
| story.commit.title | Lock them in | Cất hết vào kho | すべてを金庫へ |
| story.commit.body | Loox remembers, so you can forget. | Loox nhớ giúp bạn, để bạn thoải mái quên. | Looxが覚えるから、あなたは忘れていい。 |
| story.commit.cta | Hold to enter your vault | Giữ để vào kho của bạn | 長押しで金庫へ |
| story.commit.a11y | Enter my vault | Vào kho của tôi | 金庫に入る |

Copy corrections vs drafts: dropped B's "No cloud / Không đưa lên mạng" (copy lie — opt-in iCloud sync exists; A's "nothing leaves unless you say so" is the honest line), dropped "You move one, Vaultify moves the rest" (over-promise), dropped "Đã khóa/Sealed" label (collides with lock-state terminology; the burst is the confirmation). ALL statistics dropped (owner decision 2026-08-05): pure emotional storytelling, no citations. Chip strings ("123456", "qwerty") = non-localized constants.

## 4. Integration

- **Flag**: `SettingsStore.storyIntroCompleted`, key `"story_intro_completed"`; set on finish AND skip. One-shot hint `storyIntroWantsFirstItem` for the arrival bridge.
- **Seam**: `RootView.swift` `.unlocked` branch (L44-50) renders `StoryIntroScreen` INSTEAD OF `AdaptiveRootView` while `StoryIntroFeature.enabled && !storyIntroCompleted`. Never fullScreenCover/overlay (Home's `.task` would start the tutorial underneath — researcher-01).
- **Handoff**: zero coordinator changes. Flag flips → AdaptiveRootView mounts → Home `.task` → `startIfNeeded(.firstRun)` → 1200ms settle → spotlight tour.
- **Kill switch**: `StoryIntroFeature.enabled` in `VaultifyCore/` mirroring `TutorialFeature`.
- **Restore path**: `JoinVaultFlow.finish()` sets flag true (restore users skip). Recovery reset clears it (replay on full re-onboarding).
- **Test isolation**: default flag true in AppEnvironment DEBUG isolation block (next to L177) + `-ui-test-story` opt-in arg — without this every UI test breaks.
- **Analytics**: `.analyticsScreen("story_intro")`; `storyIntroEnded(outcome: completed|skipped, furthestBeat: 1...6)` + `auditSamples` entry. Fixed ids only, no content, no timings.
- **Offset plumbing** (feasibility fix): scroll offset lives in an `@Observable` model read ONLY inside `StoryStageView` (scroll writes never re-evaluate the beat column); quantize 1–2pt; iOS 18+ `.onScrollGeometryChange` behind availability, 17.3 = GeometryReader + PreferenceKey. Per-item copy effects stay render-side (`scrollTransition`/`visualEffect`).
- **Snap guarantee decoupled from API** (feasibility fix): if `.viewAligned` misbehaves on a 17.3 device, free-scroll fallback + on-gesture-end settle animation of stage progress to nearest beat — composed pages guaranteed either way.
- **Motion literals** → routed through `Motion` tokens (fast/base/medium/slow, `Motion.spring`, `.vault(_, reduceMotion:)`); sheen + hint pulse behind reduceMotion guard.
- **Reduce Motion**: TimelineView paused; per-beat static poster compositions (scatter poster / gathered ring) from snapped beat index; scrollTransition collapses to opacity; hold-to-seal keeps its progress arc (functional, not decorative); single haptic kept.
- **Dynamic Type / small screens**: VI-first budgets at SE 375 (title ≤2 VI lines, body ≤3, stat 1 + caption). `dynamicTypeSize >= .accessibility1` OR VoiceOver → `StoryIntroReaderView`: same copy + CTA + Skip, plain scroll, static poster (reflow, never shrink). VoiceOver: stage `.accessibilityHidden(true)`, beats read as grouped text.
- **iPad / macOS**: copy clamps `.vaultContentWidth(.form)`; macOS gets the Reader presentation (wheel-scrub + timed mouse-hold feel poor).
- **L10n**: all strings in `Localizable.xcstrings` EN+VI+JA; titles `.inAppLocalized`; runtime `appString()`.
- **Files**: `Vaultify/Features/StoryIntro/` — `StoryIntroScreen.swift`, `StoryStageView.swift`, `StoryBeatView.swift`, `StoryIntroReaderView.swift`, `StoryParticleField.swift` (each <200 lines); `tuist generate` after adding.

## 5. Risks

| Risk | Sev | Mitigation |
|---|---|---|
| iPhone 12 perf: mesh + ~90 particles + scroll | Med | Symbol stamping, pre-baked glow, blur ≤8 hero-only, no materials over stage; mandatory on-device Instruments pass before merge |
| `.viewAligned` quirks at exactly 17.3 | Med | Prototype FIRST on 17.3 sim; settle-animation fallback designed in |
| Accessibility-size overflow of fixed pages | Med | Dedicated ReaderView path |
| UI tests hitting the story | High if missed | DEBUG isolation default + launch-arg opt-in |
| Committed-dark canvas in light mode | Open | Owner call; scrim fallback ready |
| Story fatigue / App Review | Low | Skip from frame one, ~10s rushed floor, one-time flag |
| JA per-glyph effects | Low | Whole-block blur-ins only; per-glyph solely via `GlyphResolveText` |

**Estimate**: 9–14 engineer-days (stage + 6 beats + reader view + copy/l10n + Instruments + review checklist). No new dependencies, no .metal file, no iOS 18-only API unguarded.

## Decisions locked (owner, 2026-08-05)

1. **Committed-dark beats 1–3** in both appearance modes; theme-resolve as the beat-4 relief. ✔
2. **Arrival bridge = post-tutorial Add-button pulse** via one-shot `storyIntroWantsFirstItem` hint. ✔
3. **Brand voice = Loox** (product rebranded from Vaultify; site looxpassword.com). ✔
4. **No statistics anywhere** — pure emotional storytelling; stat/source/tally keys removed from copy. ✔
5. **macOS: Arc/Dia-style full-screen cinematic onboarding IF feasible** (research task `research/researcher-06-macos-arc-style-onboarding.md`); fallback = `StoryIntroReaderView` static presentation. ✔
6. JA ships with the drafted values, flagged for native review before a JA-market push (process note).
7. `.viewAligned` verification on a 17.3 sim = phase-02 gate task (process note).
