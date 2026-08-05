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
| phase-01 foundation (flags, seam, skeleton) | In progress |
| phase-02 stage engine | Pending |
| phase-03 beats 1–4 | Pending |
| phase-04 beats 5–6 + arrival | Pending |
| phase-05 accessibility + Reader | Pending |
| phase-06 l10n, tests, macOS, polish | Pending |
| macOS Arc-style research (researcher-06) | Running in background |

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
