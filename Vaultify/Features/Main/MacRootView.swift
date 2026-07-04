#if os(macOS)
import SwiftUI

/// What the Mac shell's middle (list) column shows. Sidebar selection drives it;
/// an active search query overrides it (results replace the list, like Mail).
enum MacVaultFilter: Hashable {
    case allItems, favorites, watchtower, archive, trash
    case space(String)
    case tag(String)
}

/// The macOS unlocked shell, laid out like the reference password manager:
///
///     ┌─────────┬──────────────────────────────┐
///     │         │  HEADER (search · New Item)  │   ← spans columns 2+3
///     │ Sidebar ├───────────┬──────────────────┤
///     │         │  Column 2 │     Column 3     │
///     └─────────┴───────────┴──────────────────┘
///
/// `NavigationSplitView` can't span a toolbar across its columns, so the right
/// side is hand-built: a custom header band over an `HSplitView` of list and
/// detail. Search lives in that header with a floating suggestions panel.
struct MacRootView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var filter: MacVaultFilter = .allItems
    @State private var selectedItemID: String?
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var editorTarget: EditorTarget?
    @State private var showProfile = false

    private var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationSplitView {
            MacSidebarList(filter: $filter, onProfile: { showProfile = true })
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            rightSide
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

    // MARK: Right side (header band + columns 2/3)

    private var rightSide: some View {
        VStack(spacing: 0) {
            MacHeaderBar(searchQuery: $searchQuery,
                         searchFocus: $searchFocused,
                         onNewItem: { editorTarget = .new($0) })
            Divider()
            HSplitView {
                listPane
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 420)
                detailColumn
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Floating search suggestions over both columns, anchored under the field.
        // Visibility keys off the QUERY, not field focus: on macOS a mousedown on the
        // panel defocuses the field first, which would tear the button out from under
        // the click. Esc / the clear button / selecting all empty the query to hide it.
        .overlay(alignment: .topLeading) {
            if isSearching {
                MacSearchSuggestionsPanel(query: searchQuery) { id in
                    selectedItemID = id
                    searchQuery = ""
                    searchFocused = false
                }
                .padding(.leading, Space.s4)
                .offset(y: 56)
                .zIndex(1)
            }
        }
    }

    // MARK: Column 2 (list)

    private var listPane: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()
            listContent
        }
        .background(Color(rgb: env.theme.active.background))
    }

    /// Column-2 header: the context title, plus the Space dropdown when browsing items.
    private var listHeader: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(listTitle).vaultType(.headline)
            if isSpaceFilterable {
                Menu {
                    Button { filter = .allItems } label: { Text("All Spaces") }
                    ForEach(env.repository.folders) { folder in
                        Button { filter = .space(folder.id) } label: {
                            Label { Text(verbatim: folder.name) } icon: { PolarisIcon(folder.iconAsset) }
                        }
                    }
                } label: {
                    HStack(spacing: Space.s1) {
                        Text(currentSpaceName).vaultType(.subhead).themedForeground(.secondary)
                        PolarisIcon(Icons.chevronDown, size: 10).themedForeground(.secondary)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    @ViewBuilder private var listContent: some View {
        // While typing, results live in the floating panel (reference behavior);
        // the list keeps showing the current sidebar context underneath.
        Group {
            switch filter {
            case .allItems:
                MacItemListColumn(items: env.repository.items, selection: $selectedItemID)
            case .favorites:
                MacItemListColumn(items: env.repository.items.filter(\.favorite), selection: $selectedItemID)
            case .space(let id):
                MacItemListColumn(items: env.repository.items.filter { $0.folderId == id }, selection: $selectedItemID)
            case .tag(let tag):
                MacItemListColumn(items: env.repository.items.filter { item in
                    item.tags.contains { $0.lowercased() == tag.lowercased() }
                }, selection: $selectedItemID)
            case .watchtower:
                WatchtowerScreen()
            case .archive:
                NavigationStack { ArchiveScreen().vaultNavigationDestinations() }
            case .trash:
                NavigationStack { TrashScreen().vaultNavigationDestinations() }
            }
        }
    }

    private var listTitle: LocalizedStringResource {
        switch filter {
        case .allItems: return "All Items"
        case .favorites: return "Favorites"
        case .watchtower: return "Watchtower"
        case .archive: return "Archive"
        case .trash: return "Recently Deleted"
        case .space(let id):
            let name = env.repository.folders.first { $0.id == id }?.name ?? ""
            return LocalizedStringResource(stringLiteral: name)
        case .tag(let tag):
            return LocalizedStringResource(stringLiteral: "#\(tag)")
        }
    }

    // MARK: Column 3 (detail)

    @ViewBuilder private var detailColumn: some View {
        if let selectedItemID, env.repository.item(id: selectedItemID) != nil {
            NavigationStack {
                ItemDetailScreen(itemID: selectedItemID)
                    .vaultNavigationDestinations()
            }
            .id(selectedItemID) // fresh stack per item — no stale pushed state
            .environment(\.themedSurfaceStyle, .plain)
        } else {
            emptyDetail
        }
    }

    /// Blank-slate detail on the plain background — canvas, not a gray pane.
    private var emptyDetail: some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.lockFill, size: 56).themedForeground(.disabled)
            Text("Select an item to view its details.")
                .vaultType(.subhead).themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(rgb: env.theme.active.background))
    }

    // MARK: Helpers

    private var isSpaceFilterable: Bool {
        if case .space = filter { return true }
        return filter == .allItems
    }

    private var currentSpaceId: String? {
        if case .space(let id) = filter { return id }
        return nil
    }

    private var currentSpaceName: String {
        if case .space(let id) = filter,
           let name = env.repository.folders.first(where: { $0.id == id })?.name {
            return name
        }
        return appString("All Spaces")
    }
}
#endif
