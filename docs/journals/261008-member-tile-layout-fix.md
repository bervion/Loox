---
date: 2026-10-08
session: member-tile-layout-fix
status: verified-working-tree
branch: codex/loox-member-card-layout
---

# Member tile layout follow-up

## Context

The Member overhaul in `1f6d0a64` allowed localized metrics to wrap. Its `LazyVGrid`
kept different intrinsic heights across rows, so the six feature tiles lost their
uniform geometry. Resting tiles also used `surfacePressed`, giving Day an overly
dark gray fill. [Overhaul plan](../../plans/261007-1825-loox-member-and-private-email-ux-overhaul/plan.md).

## What happened

The bounded working-tree fix introduces the shared `EqualHeightTileLayout` and
`surfaceInset`. A multi-column grid measures all tiles at the proposed column width
and uses the tallest intrinsic height throughout the section. Accessibility sizes
keep a single column and natural heights. The resting fill resolves to
`secondaryBackground` in light themes and `controlBackground` in dark themes.

## Reflection and decisions

Wrapping is necessary for Vietnamese and Dynamic Type. Grid-level measurement keeps
the geometry consistent as content grows. Resting and pressed surfaces need separate
semantic tokens; neither tile content nor feature screens should guess their colors.
Preserve full labels without fixed heights, truncation or text shrinking.

## Next

Fresh native/theme verification passed: 41 existing theme units and one temporary
unit-host native probe, zero failures. Nineteen final configurations produced 33
before/after PNG receipts; multi-column height spread is effectively zero.
Accessibility uses one column with natural heights. Root inspected VI light/dark
at 430pt and Accessibility3 at 375pt with unclipped labels. RTL now follows SwiftUI
mirroring once. After removing the probe, Tuist regeneration and generic Simulator
compilation of the app and embedded extensions passed. The
[follow-up report](../../plans/261007-1825-loox-member-and-private-email-ux-overhaul/reports/member-tile-layout-fix-261008.md)
records the receipts and limits. Snapshot/UI suites were not run, and CI was unchanged.
Reduce Motion/Transparency behavior was inspected statically, without runtime overrides.
The overhaul remains at 21/34 acceptance criteria, with its five phases in progress.
TestFlight 1.57.0 (96) predates this fix. This journal stays local.
