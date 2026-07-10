# Phase 4 findings — Items + Folders + Vault (persisted by orchestrator; agent's write was hook-blocked)

20 findings, 17 fixed (3 high, 9 medium, 5 low), 3 pass-with-note. Compile green (app+extension). No new strings (2 a11y labels reuse existing keys `Sort`, `New Space`).

| Surface | Finding | Fix | Severity | Status |
|---|---|---|---|---|
| VaultItemRow | raw `.font(.body/.caption/.caption2)` ×5 | `.vaultType(.body/.caption)` | High | Fixed |
| VaultItemRow | pin badge `Color.accentColor` ignores theme accent presets | `Color(rgb: env.theme.active.accent)` | Medium | Fixed |
| VaultItemRow | favorite badge `cornerRadius: 5` magic number | `Radius.xs` | Low | Fixed |
| VaultItemRowLink | favorite/pin toggle fired no haptic | `Haptics.tap()` both | Medium | Fixed |
| VaultItemRowLink | swipe Trash/Archive/Restore haptic considered, skipped (native removal feedback đủ, reversible) | none | — | Pass |
| ItemsScreen | leadingTile flat `cornerRadius: 8` inside `Radius.lg` card inset `Space.s4` | `Radius.concentric(outer: .lg, inset: .s4)` | High | Fixed |
| ItemListScreen/FolderItemsScreen/TagItemsScreen | icon-only Sort menu no a11y label | `.accessibilityLabel(Text("Sort"))` ×3 | Medium | Fixed |
| TrashScreen | raw `.font(.footnote)` | `.vaultType(.footnote)` | Low | Fixed |
| TrashScreen | Empty Trash destructive confirm no haptic | `Haptics.error()` | Medium | Fixed |
| FolderEditorSheet | delete fired `Haptics.success()` — sai verb vocabulary | `Haptics.error()` | Medium | Fixed |
| FolderPickerSheet | "None" tile radius 8 vs FolderBadge `size*0.28` formula | matched formula | Low | Fixed |
| FolderPickerSheet | checkmark `Color.accentColor` | theme accent | Medium | Fixed |
| FolderPickerSheet | `spacing: 12` literal | `Space.s3` | Low | Fixed |
| IconColorPicker | color swatch tap target 34pt < 44 | invisible 44×44 hit frame, visual giữ 34 | High | Fixed |
| IconColorPicker | `Color.primary.opacity(0.6)` raw trên themed surface | `theme.color(.primary).opacity(0.6)` | High | Fixed |
| IconColorPicker | icon tile radius 12 magic (50pt tile) | `Radius.md` ×2 | Medium | Fixed |
| IconColorPicker | captions raw `.font(.subheadline.semibold)` | `.vaultType(.sectionLabel)` | Medium | Fixed |
| IconColorPicker | grid `spacing: 12` ×2 | `Space.s3` | Low | Fixed |
| ManageFoldersScreen | icon-only Add button no a11y label | `.accessibilityLabel(Text("New Space"))` | Medium | Fixed |
| ItemsScreen/Archive/Trash/FolderBadge/FolderItems/TagItems/FolderEditor/FolderPicker/IconColorPicker/ManageFolders | protagonist/copy/empty-state/concentricity checks | — | — | Pass |

Deferred (low): 30pt row-badge và 50pt icon-tile chưa có Metric token đặt tên — giá trị đã nhất quán, chỉ chưa named; không file shared-component request.
Geometry ripple: none — mọi fix VaultItemRow là font/màu/radius token, không đổi size/layout (an toàn cho Home/Search/Sharing).
