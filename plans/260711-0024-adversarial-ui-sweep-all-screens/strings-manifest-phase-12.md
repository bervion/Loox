# Phase 12 — Strings Manifest (Sharing: Quick Link + Quick View + Shared-with-Me)

No new or changed user-facing strings. Every fix in this phase was a layout/action-hierarchy/token
change — `ButtonStyle` swaps (default → `.themedTinted` for the new quiet-secondary slot),
`controlMedium`→`controlLarge` on single/primary CTAs, and repositioning existing controls (Share +
Shorten moved into a small utility row) — all using the SAME existing `LocalizedStringResource`
literals ("Copy Link", "Link Copied", "Done", "Share Link", "Shorten Link", "Creating short link…",
"Create Link", "Try Again", "Continue", "Approve with Face ID", "Close", etc.). Verified every key
already has both EN + VI entries in `Vaultify/Localizable.xcstrings` (spot-checked programmatically)
before reusing them — zero catalog changes required.

One haptic reclassification (`Haptics.success()` → `Haptics.tap()` in `QuickLinkResultView.shorten()`)
— not a string, no catalog impact.

| key | EN | VI | context |
|---|---|---|---|
| — | — | — | none this phase |
