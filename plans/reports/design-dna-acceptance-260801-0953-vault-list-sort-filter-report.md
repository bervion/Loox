# DNA acceptance — vault list sort/filter/sections + Space terms (260801)

Scope: FolderItems/TagItems/ItemList/FilteredItems toolbars + sections, Search chip row,
ItemsScreen Create-Space row, seed Space display name/icon.

- **Tokens only**: no new hardcoded visuals. Spacing `Space.s1-s4`/`gutter`, sizes
  `Metric.hitMin/iconCompact/iconTileLarge/rowHeight`, type `.vaultType(.sectionLabel/.subhead)`,
  colors via `themedForeground`/`theme.color` (FilterChip reuses existing token pair).
- **Hit targets (rule 6)**: FilterChip visual capsule ~36pt gains invisible
  `.frame(minHeight: Metric.hitMin)` + `.contentShape`; Search sort menu label framed 44x44;
  toolbar menu is the standard 44pt ToolbarItem; Create-Space row keeps `Metric.rowHeight`.
- **Haptics (one event = one haptic)**: `Haptics.tap` fired on the Menu host `.onChange`
  (menu content unmounts on close and can miss the change), chips fire in their action;
  no double-fire path: pickers have no own haptic, chip taps mutate state observed nowhere else.
- **Sort/filter altitude (rule 7)**: browse lists keep them behind the trailing toolbar menu
  (F2/F3), never a button wall. Search uses chips because rule 10 explicitly wants quick
  filters on the search surface, and the iOS 26 Search nav bar is hidden (toolbar invisible).
- **Copy**: no "!", no em dash, no "·" in new strings. All 9 new keys ship EN key + VI + JA
  (verified by script). Longest-label check: VI "Tất cả phân loại", "Dùng thường xuyên" fit
  chips/menu rows (chips scroll horizontally; menu rows wrap natively).
- **A11y**: chips carry `.isSelected` trait; icon-only menus keep
  `accessibilityLabel` ("Sort"/"Filter"); month headers are plain Text (VoiceOver reads).
- **Theme/motion**: no new materials, no motion added; chips/menu inherit live theme tokens;
  Reduce Transparency/Motion unaffected (no glass, no animation introduced).
- **Multi-device**: macOS slice compiles (destination platform=macOS, exit 0); menus use
  `.menuStyle(.button)` pattern where label-only (Search) to avoid macOS bordered pull-down;
  toolbar menus use `platformPrimaryAction`.
- **Storage safety**: stored folder name/iconAsset bytes never rewritten; display mapping
  render-layer only; editor sheet still round-trips raw values; dedupe widened via frozen
  historical name set + canonical icon fold (tests pin both).

Verified: iOS app+extension compile, macOS compile, full VaultifyTests pass (pre-existing
red baseline untouched: 2 UI + 3 snapshot are known-red on main, not run here).
