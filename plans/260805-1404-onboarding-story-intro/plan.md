# Story Intro — Research & Concept (overview)

One-time cinematic story screen after onboarding, before the Home tutorial. Pain-point narrative: passwords scattered in notes, chats, browsers → gathered into one private vault. Research phase complete; implementation not started.

## Status

| Phase | Status |
|---|---|
| Research (5 parallel: flow seam, design system, reactbits catalog, benchmarks + stats, SwiftUI 17.3 feasibility) | Done |
| Two independent concepts (A scroll journey, B interactive vignettes) | Done |
| Adversarial critique (design-dna, feasibility-perf, narrative-retention) | Done |
| Final hybrid concept | Done → `concept-final.md` |
| Owner decisions | Locked 2026-08-05 (dark canvas, Add pulse, no stats, Loox, macOS Arc-style research w/ Reader fallback) |
| phase-01 foundation (flags, seam, skeleton) | Done (a6c22b2) |
| phase-02 stage engine | Done (b83bf9e) |
| phase-03 beats 1–4 + tap-to-send | Done (a315252) |
| phase-04 sanctuary peek, hold-to-seal, arrival bridge | Done (2ceffda) |
| phase-05 reader + accessibility | Done (f812ce5) |
| phase-06 l10n VI+JA, unit tests, macOS reader, docs | Done (683bf7b, 2d7ba40) |
| Verification | **CI green on PR #198** (run 30991811746): app + extensions compile, 1332 tests pass incl. all 6 StoryIntroTests. First run caught 3 real compile errors in this code — fixed in 2d7ba40 |

## Verification note
Local `make check` could never validate this: the dev machine has Xcode 16.4 while the repo requires 26.5 (pre-existing VaultifyCore files use `nonisolated struct`), and the Makefile piped xcodebuild into `tail`, masking the exit code so a failed build printed "passed" (fixed in b37fbcb). CI on the self-hosted runner is the only compiler that sees this code.
| macOS research (researcher-06) | Done — Arc/Dia use windowed discrete steps, not full-screen cinema; Reader ships now, stepped window = follow-up |

## Remaining before merge
- On-device Instruments pass (iPhone 12-class) during the beat-4 scrub
- `.viewAligned` behavior check on an iOS 17.3 simulator (fallback designed: free scroll + settle)
- JA native review of the drafted strings
- Design-DNA checklist answers filed at PR review

## Files

- `concept-final.md` — the deliverable: hybrid concept (A's scroll spine on B's shader-free stack + 4 grafts), storyboard, EN/VI/JA copy, integration spec, risks, estimate 9–14 days
- `concept-a-scroll-journey.md` — Concept A (scores: dna 7, feas 6, narrative 6.5)
- `concept-b-interactive-vignettes.md` — Concept B (scores: dna 5, feas 7, narrative 5.5)
- `research/researcher-01-flow-integration.md` — seam: RootView `.unlocked` branch + `storyIntroCompleted` flag; zero tutorial changes
- `research/researcher-02-design-system.md` — DNA rules, Motion/haptics vocabulary, Loox animation house stack
- `research/researcher-03-reactbits-catalog.md` — reactbits.dev full catalog with story-beat mapping
- `research/researcher-04-benchmarks-stats.md` — Opal/Proton/Duolingo lessons; Pew 2023, Microsoft 2024 stats
- `research/researcher-05-swiftui-feasibility.md` — iOS 17.3 API map, perf budgets, traps

## Key dependencies

- Owner sign-off on the 7 unresolved questions in `concept-final.md` (dark canvas, arrival bridge, Loox brand voice, stats, macOS, JA review, 17.3 snap verify)
- Prototype `.viewAligned` full-height snapping on a 17.3 simulator before locking the scroll mechanic
- On-device Instruments pass (iPhone 12-class) before merge
