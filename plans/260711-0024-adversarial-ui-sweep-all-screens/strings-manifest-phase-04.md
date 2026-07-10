# Strings Manifest — Phase 4 (Items + Folders + Vault)

No new or changed user-facing strings. All fixes were token/geometry/haptics substitutions with
no copy changes. Two new `accessibilityLabel` calls were added (icon-only Sort menus in
`ItemListScreen`/`FolderItemsScreen`/`TagItemsScreen`, icon-only Add button in
`ManageFoldersScreen`) — both reuse keys **already present** in `Vaultify/Localizable.xcstrings`
with EN + VI:

| Key | EN | VI | Reused in |
| --- | --- | --- | --- |
| `Sort` | (source = key) | Sắp xếp | ItemListScreen, FolderItemsScreen, TagItemsScreen (Sort menu a11y label) |
| `New Space` | New Space | Nhóm mới | ManageFoldersScreen (Add-Space toolbar button a11y label) |

No orchestrator merge action required for this phase.
