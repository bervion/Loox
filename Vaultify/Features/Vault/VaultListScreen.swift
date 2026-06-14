import SwiftUI

/// The Vault tab. The landing is a Home dashboard (Quick Access, Spaces, Tags,
/// All Items); the search bar filters globally across all items. Add and Trash
/// live in the toolbar; folder/tag/all browse via pushed destinations.
struct VaultListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editorTarget: EditorTarget?
    @State private var showTrash = false
    @State private var search = ""

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isSearching: Bool { !query.isEmpty }
    private var searchResults: [VaultItem] {
        env.repository.items.filter { $0.searchText.contains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if env.repository.items.isEmpty && env.repository.folders.isEmpty {
                    emptyState
                } else if isSearching {
                    searchList
                } else {
                    HomeDashboard()
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
                case .all: AllItemsScreen()
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
        ToolbarItem(placement: .topBarTrailing) {
            Menu { addMenu } label: { PolarisIcon(Icons.add, size: 26) }
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
