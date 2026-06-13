import SwiftUI

/// The Vault tab: items grouped into per-type sections (1Password-style), with a
/// search bar, a header filter/sort menu (next to the add button), and favicon
/// row avatars. Tapping the filter menu narrows to a single type.
struct VaultListScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editorTarget: EditorTarget?
    @State private var filter: ItemCategory?
    @State private var sort: SortOrder = .updated
    @State private var showTrash = false
    @State private var search = ""

    enum SortOrder: String, CaseIterable { case updated, title }

    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isSearching: Bool { !query.isEmpty }
    private var searchResults: [VaultItem] {
        env.repository.items.filter { $0.searchText.contains(query) }
    }

    private func items(for category: ItemCategory) -> [VaultItem] {
        let list = env.repository.items.filter { $0.category == category }
        switch sort {
        case .updated: return list.sorted { $0.updatedAt > $1.updatedAt }
        case .title: return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    private var visibleCategories: [ItemCategory] {
        if let filter { return [filter] }
        return ItemCategory.allCases.filter { !items(for: $0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if env.repository.items.isEmpty {
                    emptyState
                } else if isSearching {
                    searchList
                } else {
                    groupedList
                }
            }
            .navigationTitle("Vault")
            .searchable(text: $search, prompt: "Search vault")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar { toolbar }
            .navigationDestination(for: String.self) { ItemDetailScreen(itemID: $0) }
            .navigationDestination(isPresented: $showTrash) { TrashScreen() }
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
        }
    }

    private var groupedList: some View {
        List {
            ForEach(visibleCategories) { category in
                let categoryItems = items(for: category)
                Section {
                    rows(categoryItems)
                } header: {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text("\(categoryItems.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private var searchList: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            List(searchResults) { item in
                NavigationLink(value: item.id) { VaultItemRow(item: item) }
            }
        }
    }

    private func rows(_ items: [VaultItem]) -> some View {
        ForEach(items) { item in
            NavigationLink(value: item.id) { VaultItemRow(item: item) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { try? env.repository.moveToTrash(item) } label: {
                        Label("Trash", image: Icons.trash)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button { try? env.repository.toggleFavorite(item) } label: {
                        Label("Favorite", image: item.favorite ? Icons.starFill : Icons.star)
                    }
                    .tint(VaultColors.strengthMedium)
                }
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
            Picker("Show", selection: $filter) {
                Label { Text("All Items") } icon: { PolarisIcon("ic_apps_filled") }.tag(ItemCategory?.none)
                ForEach(ItemCategory.allCases) { category in
                    Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
                        .tag(ItemCategory?.some(category))
                }
            }
            Divider()
            Picker("Sort", selection: $sort) {
                Text("Recently Updated").tag(SortOrder.updated)
                Text("Title").tag(SortOrder.title)
            }
        } label: {
            PolarisIcon("ic_filter", size: 22)
                .foregroundStyle(filter == nil ? Color.accentColor : Color.white)
                .padding(7)
                .background(Circle().fill(filter == nil ? Color.clear : Color.accentColor))
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
