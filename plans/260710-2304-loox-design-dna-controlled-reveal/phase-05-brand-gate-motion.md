# Phase 5 — Brand gate motion (∞ Shape · unlock/lock physics · Controlled Reveal doc)

**Tier:** T3 · **Priority:** P2 · **Status:** pending · **Depends:** P0
**Owns exclusively:** new `LooxGateShape.swift`, `LockScreen.swift`, `docs/design-guidelines.md` (motion section)

Audit downgraded this to ADR/asset-blocked. **Verify-first result: NOT blocked** — the ∞ vector exists.

## Context (verified)
- `Vaultify/Assets.xcassets/logo.imageset/logo.svg:12` = a **single** bezier `<path d="M337.68…Z">` of the ∞
  loop (gradient `#1544FD`→`#20BDFD`); the L and X are separate paths at `:14-15`. viewBox `0 0 724 167`.
- `BrandLogoMark` (`VaultifyCore/BrandLogoMark.swift:16`) uses a DIFFERENT asset,
  `VaultifyCore/SharedAssets.xcassets/BrandLogo.imageset` (light/dark wordmark). Do not confuse the two.
- LockScreen: unlock success flips `env.session` → view replaced with no motion (`runBiometric` `:183-195`);
  `LockScreen.swift:62-146`, hero logo `:68`. `env.theme.morphMesh()` already fires on failure (:208).
- Reduce Motion: `Animation.vault(_:reduceMotion:)`, `Motion.*` tokens.

## Requirements
1. **`LooxGateShape: Shape`** — transcribe the ∞ path (`logo.svg:12`) into a `Path`, normalized to a unit rect
   (translate/scale from the loop's own bounding box, not the full 724×167). Gradient fill via overlay/mask.
2. **Gate motion vocabulary** (Controlled Reveal):
   - **Unlock = gate opening**: on successful auth, play a short (~0.4s) ∞ resolve/open (trim-stroke draw or
     blur→clear + subtle scale) on the lock logo BEFORE the session tears the view down; then flip.
   - **Lock = gate closing**: LockScreen appear transition contracts to the ∞ mark (blur-in / scale-in).
   - Reduce Motion → static logo, instant unlock (no animation), no regression to the existing unlock path.
3. **Controlled Reveal doc**: add a "Loox Motion Language: Controlled Reveal" section to `design-guidelines.md`
   unifying hidden↔visible vocabulary: glyph resolve (fields, P0/P2), blur→clear (unlock), seal→expand
   (protected note), contract→∞ (lock). Reference the shipped `GlyphResolveText` + `LooxGateShape`.

## Fallback (built-in, so this phase is NEVER "blocked")
If faithful ∞ bezier transcription proves too costly/imperfect, ship **blur→clear on the existing logo image**
(`BrandLogoMark.hero`) as the unlock/lock physics. Still on-brand, still satisfies Controlled Reveal, still
Reduce-Motion-safe. `LooxGateShape` can land later without changing the doc's vocabulary.

## Data flow
- Success: `runBiometric`/`unlock` succeeds → set `@State unlocking=true` → play animation → allow session flip.
  Must not block the security path: if animation is interrupted (backgrounded), session flip still wins.
- No secret/crypto interaction; purely presentational over the existing unlock result.

## Files
**Create:** `Vaultify/DesignSystem/Components/LooxGateShape.swift` (or `Features/Unlock/`)
**Edit (exclusive):** `Vaultify/Features/Unlock/LockScreen.swift`, `docs/design-guidelines.md`
`tuist generate` after new file.

## Implementation steps
1. Transcribe ∞ path → `LooxGateShape`; unit-normalize; preview against `logo.svg`.
2. Add gradient fill (linear `#1544FD`→`#20BDFD`).
3. LockScreen: add `unlocking` state + success animation hook before session flip; appear = gate-close.
4. Reduce Motion branch = instant (current behavior preserved).
5. Write Controlled Reveal doc section.
6. `make check`.

## Todo
- [ ] `LooxGateShape` from `logo.svg:12` (unit-normalized + gradient)
- [ ] unlock = gate-open before session flip
- [ ] lock = gate-close on appear
- [ ] Reduce Motion instant (no regression)
- [ ] Controlled Reveal doc section
- [ ] `make check`; device/sim verify unlock timing not delayed perceptibly

## Success criteria
- Successful unlock shows a brief ∞ gate-open, then the vault; failed/Reduce-Motion paths unchanged.
- Lock screen appears with a gate-close motion.
- Doc section codifies the unified hidden↔visible vocabulary and names the two shipped primitives.
- If fallback taken: blur→clear physics live; doc still accurate; `LooxGateShape` deferred cleanly.

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| ∞ bezier transcription inaccurate/tedious | M×M | built-in blur-unlock fallback; land Shape later |
| Success animation delays unlock (feels slow) | M×M | cap ~0.4s; allow session flip to preempt; Reduce Motion instant |
| Animation races the RootView view-swap | M×M | drive from LockScreen local state; ensure flip is the terminal state |
| Storyboard LaunchScreen mismatch on hand-off | L×L | keep hero logo geometry; gate motion is post-launch only |

## Rollback
Delete `LooxGateShape.swift`, revert LockScreen (restores instant unlock) + doc. No security impact.

## Security
Presentational only. Never gate or delay the actual auth result; interruption → locked/flipped state wins.

## Next
Disjoint from P2/P3/P4. Feeds P6.
