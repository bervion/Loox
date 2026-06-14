import SwiftUI

/// The Vault tab. The landing is a Home dashboard (Quick Access, Spaces, Tags)
/// followed by the items grouped by category. The header offers a filter
/// (Space / Type / Sort) and a smart search that matches Space names too.
struct VaultListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editorTarget: EditorTarget?
    @State private var showTrash = false
    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var filterCategory: ItemCategory?
    @State private var filterSpace: SpaceFilter = .all
    @State private var sort: VaultSort = .updated

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isSearching: Bool { !query.isEmpty }
    private var isFilterActive: Bool { filterCategory != nil || filterSpace != .all }

    /// Smart search: every space-separated token must appear in the item's
    /// searchable text (title, fields, tags) OR its Space name — so "github work"
    /// finds the GitHub login filed under the "Work" space.
    private var searchResults: [VaultItem] {
        let tokens = query.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        let spaceNames = Dictionary(env.repository.folders.map { ($0.id, $0.name.lowercased()) },
                                    uniquingKeysWith: { a, _ in a })
        return env.repository.items.filter { item in
            let hay = item.searchText + " " + (item.folderId.flatMap { spaceNames[$0] } ?? "")
            return tokens.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if env.repository.items.isEmpty {
                    emptyState
                } else if isSearching {
                    searchList
                } else {
                    HomeDashboard(path: $path, filterCategory: filterCategory,
                                  filterSpace: filterSpace, sort: sort)
                }
            }
            .navigationTitle("Vault")
            .searchable(text: $search, prompt: "Search vault")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar { toolbar }
            .navigationDestination(for: String.self) { ItemDetailScreen(itemID: $0) }
            .navigationDestination(for: VaultRoute.self) { route in
                switch route {
                case .folder(let id): FolderItemsScreen(folderId: id)
                case .tag(let tag): TagItemsScreen(tag: tag)
                case .manageFolders: ManageFoldersScreen()
                }
            }
            .navigationDestination(isPresented: $showTrash) { TrashScreen() }
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
        }
    }

    @ViewBuilder private var searchList: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            List(searchResults) { VaultItemRowLink(item: $0) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label { Text("Your vault is empty") } icon: { PolarisIcon(Icons.lockFill, size: 48) }
        } description: {
            Text("Add your first login, card, or secure note.")
        } actions: {
            Menu { addMenu } label: { Text("Add Item") }.buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button { showTrash = true } label: { Label("Trash", image: Icons.trash) }
            } label: {
                PolarisIcon("ic_menu_horizontal", size: 24)
            }
        }
        ToolbarItem(placement: .topBarTrailing) { filterMenu }
        ToolbarItem(placement: .topBarTrailing) {
            Menu { addMenu } label: { PolarisIcon(Icons.add, size: 26) }
        }
    }

    private var filterMenu: some View {
        Menu {
            if !env.repository.folders.isEmpty {
                Picker("Space", selection: $filterSpace) {
                    Text("All").tag(SpaceFilter.all)
                    if env.repository.unfiledCount > 0 { Text("Unfiled").tag(SpaceFilter.unfiled) }
                    ForEach(env.repository.folders) { Text($0.name).tag(SpaceFilter.folder($0.id)) }
                }
            }
            Picker("Type", selection: $filterCategory) {
                Text("All").tag(ItemCategory?.none)
                ForEach(ItemCategory.allCases) { Text($0.title).tag(ItemCategory?.some($0)) }
            }
            Divider()
            Picker("Sort", selection: $sort) {
                ForEach(VaultSort.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            PolarisIcon("ic_filter", size: 22)
                .foregroundStyle(isFilterActive ? Color.accentColor : Color.primary)
        }
    }

    @ViewBuilder private var addMenu: some View {
        ForEach(ItemCategory.allCases) { category in
            Button {
                editorTarget = .new(category)
            } label: {
                Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
            }
        }
    }
}
