# Phase 4 — Items + Folders + Vault

**Status**: pending · **Wave**: W2 · **Owns**: `Items/*`, `Folders/*`, `Vault/*` (20 surfaces).
Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Items = "organize and jump into a Space/category/tag". Vault lists = "scan and open one item".
Folders = "shape my Spaces".

## Cluster hotspots
- **ItemsScreen**: card groups (Spaces / Categories / Tags / Archive+Trash); count badges hide when 0;
  "Create Space" always present (never fully empty). Verify grouping cards exist for TRUE semantic grouping
  (rule 2), not decoration.
- **VaultItemRow / VaultItemRowLink**: the highest-frequency row in the app — favicon + title + subtitle
  must not clip long VI titles at SE; full-row tap target; pin/shared markers legible in light+dark.
- **FolderBadge / IconColorPicker / FolderEditorSheet**: 64pt live badge preview; 24-icon + color grid
  reflow at SE; destructive "Delete Space" → dialog "Items move to Unfiled" (honest, no `!`), red = role.
- **ArchiveScreen / TrashScreen**: swipe actions (Unarchive/Trash, Restore/Delete-permanent); empty states
  ("No archived items", "Trash is empty") intentional; "Empty" trash → confirm dialog with irreversible copy.
- **FolderItemsScreen / TagItemsScreen / FolderPickerSheet**: list + Sort menu; empty "No items here" +
  category icon; picker "None" + list + "New Space…".
- Concentricity: nested tiles/badges inside cards use `Radius.concentric`, not scale picks.

## Deliverables / Todo
`reports/findings-phase-04.md` · `strings-manifest-phase-04.md` · fixes.
- [ ] Protocol answers (20). [ ] 6 greps. [ ] Long-VI title clip test on VaultItemRow at SE.
- [ ] Swipe-action + empty states walked. [ ] Concentric nesting verified. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; rows never truncate VI at SE; every list has an intentional empty state; nested
radii concentric. Risk: `VaultItemRow` is reused widely — a geometry change ripples into Home/Search/Shared
lists (Med×High) → prefer token/copy fixes; if geometry must change, flag for phases 3/5/11/12 re-verify.
</content>
