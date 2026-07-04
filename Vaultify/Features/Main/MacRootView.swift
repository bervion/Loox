#if os(macOS)
import SwiftUI

/// What the Mac shell's middle (list) column shows. Sidebar selection drives it;
/// an active search query overrides it (results replace the list, like Mail).
enum MacVaultFilter: Hashable {
    case allItems, favorites, watchtower, archive, trash
    case space(String)
    case tag(String)
}

/// The macOS unlocked shell: a 1Password-style three-column split —
/// sidebar (filters/Spaces/tags) · item list · item detail — with an always-visible
/// toolbar search field whose suggestions jump straight to an item. The iPhone Home
/// and Search screens don't exist on the Mac; search lives in the toolbar and the
/// list column IS the browsing surface.
struct MacRootView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var filter: MacVaultFilter = .allItems
    @State private var selectedItemID: String?
    @State private var searchQuery = ""
    @State private var editorTarget: EditorTarget?
    @State private var showProfile = false

    var body: some View {
        NavigationSplitView {
            MacSidebarList(filter: $filter, onProfile: { showProfile = true })
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            listColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            detailColumn
        }
        .searchable(text: $searchQuery, placement: .sidebar, prompt: Text("Search vault"))
        .searchSuggestions { MacSearchSuggestions(query: searchQuery) { select($0) } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { newItemMenu }
        }
        .tint(env.theme.uiTint)
        .vaultShellBehaviors()
        .sheet(item: $editorTarget) { ItemEditorScreen(target: $0, preselectedFolderId: currentSpaceId) }
        .sheet(isPresented: $showProfile) { ProfileScreen() }
        // Switching sidebar context drops a selection that no longer belongs to it.
        .onChange(of: filter) { _, _ in
            selectedItemID = nil
            env.session.registerActivity()
        }
    }

    // MARK: Columns

    @ViewBuilder private var listColumn: some View {
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            MacItemListColumn(items: env.repository.search(searchQuery), selection: $selectedItemID)
                .navigationTitle(Text("Search"))
        } else {
            switch filter {
            case .allItems:
                MacItemListColumn(items: env.repository.items, selection: $selectedItemID)
                    .navigationTitle(Text("All Items"))
            case .favorites:
                MacItemListColumn(items: env.repository.items.filter(\.favorite), selection: $selectedItemID)
                    .navigationTitle(Text("Favorites"))
            case .space(let id):
                MacItemListColumn(items: env.repository.items.filter { $0.folderId == id }, selection: $selectedItemID)
                    .navigationTitle(spaceTitle(id))
            case .tag(let tag):
                MacItemListColumn(items: env.repository.items.filter { item in
                    item.tags.contains { $0.lowercased() == tag.lowercased() }
                }, selection: $selectedItemID)
                .navigationTitle(Text(verbatim: "#\(tag)"))
            case .watchtower:
                // Report screen — self-contained stack; detail stays on the empty state.
                WatchtowerScreen()
            case .archive:
                NavigationStack { ArchiveScreen().vaultNavigationDestinations() }
            case .trash:
                NavigationStack { TrashScreen().vaultNavigationDestinations() }
            }
        }
    }

    @ViewBuilder private var detailColumn: some View {
        if let selectedItemID, env.repository.item(id: selectedItemID) != nil {
            NavigationStack {
                ItemDetailScreen(itemID: selectedItemID)
                    .vaultNavigationDestinations()
            }
            .id(selectedItemID) // fresh stack per item — no stale pushed state
        } else {
            emptyDetail
        }
    }

    /// Blank-slate detail on a plain (non-grouped) background — the wide right
    /// column reads as canvas, not as another gray settings pane.
    private var emptyDetail: some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.lockFill, size: 56).themedForeground(.disabled)
            Text("Select an item to view its details.")
                .vaultType(.subhead).themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(rgb: env.theme.active.background))
    }

    // MARK: Toolbar

    private var newItemMenu: some View {
        Menu {
            ForEach(ItemCategory.allCases) { category in
                Button { editorTarget = .new(category) } label: {
                    Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
                }
            }
        } label: {
            Label { Text("New Item") } icon: { PolarisIcon(Icons.add) }
        }
        .accessibilityLabel(Text("New Item"))
    }

    // MARK: Helpers

    private var currentSpaceId: String? {
        if case .space(let id) = filter { return id }
        return nil
    }

    private func spaceTitle(_ id: String) -> Text {
        Text(verbatim: env.repository.folders.first { $0.id == id }?.name ?? "")
    }

    private func select(_ itemID: String) {
        selectedItemID = itemID
    }
}

/// Toolbar-search dropdown: top item hits (thumbnail · bold title — subtitle),
/// like the reference password-manager suggest list. Selecting one opens it in
/// the detail column; the full result list is already live in the list column.
private struct MacSearchSuggestions: View {
    @Environment(AppEnvironment.self) private var env
    let query: String
    let onSelect: (String) -> Void

    private var hits: [VaultItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return Array(env.repository.search(trimmed).prefix(8))
    }

    var body: some View {
        ForEach(hits) { item in
            Button { onSelect(item.id) } label: {
                HStack(spacing: Space.s3) {
                    ItemThumbnail(title: item.title, category: item.category,
                                  iconAsset: item.iconAsset, size: 20)
                    Text(item.title).fontWeight(.semibold)
                    if let subtitle = item.subtitle {
                        Text(subtitle).themedForeground(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}
#endif
