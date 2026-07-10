# Phase 6 — Item Editor

**Status**: done · **Wave**: W2 · **Owns**: `ItemEditor/*` (12 surfaces).
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
"Enter this item's data with the least friction." Everything else (icon, tags, rotation) is secondary.

## Cluster hotspots
- **ItemEditorScreen / LoginEditorSections**: category-driven form (Login → Credentials/Websites/Custom/Notes).
  Section grouping = true semantic cards, not decoration. Save (check) disabled until title or a field filled;
  discard-changes dialog on interactive-dismiss ("Discard changes?", honest, no `!`).
- **EditorFieldRow / WebsiteFieldRow**: secure fields mask 16 dots unfocused / `Font.vaultCode` focused;
  website row → https chip suggestion with favicon; hit targets ≥44; reorder/delete (Edit mode) reachable.
- **TOTPScannerSheet / QRScannerView**: full-screen dark camera (exempt from theme roles), hint copy honest;
  "Choose a screenshot" + paste-key fallbacks; error "That doesn't look like a 2FA setup code." (no `!`).
- **ItemIconPickerSheet / AttachmentPickerSheet**: 5-col Polaris icon grid + Choose File/Photo — grid reflows
  at SE; sheet scaffold X-left / action-right consistent with `VaultSheetScaffold`.
- **TagChipEditor**: `#` chips with delete + "Add tag" field (return/comma commit, dedup); chips wrap, don't clip.
- **GenerateChip** (floating, sticks under focused password field): opens Generator, value flows back;
  slider haptic = `Haptics.tap` (single). 
- **KNOWN GAP** (map §10): Date fields render as plain text — flag as a finding ("no date picker"); fix if
  in-scope-cheap, else record for follow-up (do not silently expand scope without noting it).

## Deliverables / Todo
`reports/phase-06-findings.md` · `strings-manifest-phase-06.md` · fixes.
- [x] Protocol answers (12). [x] 6 greps. [x] Save-disabled + discard-dialog states walked.
- [x] Icon/attachment grids reflow at SE. [x] Date-field gap logged. [x] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; every category form renders SE↔Pro Max, DT XL, EN+VI; discard/save states
intentional; secure fields masked. Risk: editor is large + stateful — a token/layout fix must not break the
draft-restore or discard-guard logic (Med×Med) → keep edits presentational.
</content>
